import test from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadConfig } from "../src/config.js";
import { createApp } from "../src/app.js";

const base = {
  MONGODB_URI: "mongodb://127.0.0.1:27017",
  JWT_SECRET: "local-test-only-secret-with-more-than-thirty-two-bytes",
};

test("production binds all interfaces and honors Render PORT while development stays local", () => {
  const production = loadConfig({
    ...base,
    NODE_ENV: "production",
    PORT: "10000",
  });
  assert.equal(production.HOST, "0.0.0.0");
  assert.equal(production.PORT, 10000);
  assert.equal(
    loadConfig({ ...base, NODE_ENV: "production", RENDER: "true" })
      .TRUST_PROXY_HOPS,
    1,
  );
  assert.equal(
    loadConfig({
      ...base,
      NODE_ENV: "production",
      RENDER: "true",
      TRUST_PROXY_HOPS: "0",
    }).TRUST_PROXY_HOPS,
    0,
  );
  assert.equal(loadConfig(base).HOST, "127.0.0.1");
  assert.equal(loadConfig({ ...base, RENDER: "false" }).TRUST_PROXY_HOPS, 0);
  assert.equal(loadConfig({ ...base, HOST: "127.0.0.2" }).HOST, "127.0.0.2");
});

test("optional identity and email configuration fails safely when malformed or incomplete", () => {
  assert.throws(() => loadConfig({ ...base, GOOGLE_OAUTH_WEB_CLIENT_ID: "wrong-client" }), /GOOGLE_OAUTH_WEB_CLIENT_ID/);
  assert.throws(() => loadConfig({ ...base, RESEND_API_KEY: "synthetic-test-key" }), /together/);
  assert.throws(() => loadConfig({ ...base, EMAIL_FROM: "test@example.test" }), /together/);
  assert.throws(() => loadConfig({ ...base, RESEND_API_KEY: "synthetic-test-key", EMAIL_FROM: "test@example.test\r\nInjected: value" }), /single sender/);
});

test("startup database failure exits before opening the API and omits connection details", () => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL("../src/server.js", import.meta.url))], {
    encoding: "utf8",
    timeout: 15000,
    env: {
      PATH: process.env.PATH,
      SystemRoot: process.env.SystemRoot,
      NODE_ENV: "test",
      MONGODB_URI: "invalid-connection-with-private-sentinel",
      JWT_SECRET: "local-test-key-with-at-least-thirty-two-bytes",
    },
  });
  assert.equal(result.status, 1);
  assert.doesNotMatch(result.stdout, /listening/i);
  assert.match(result.stderr, /Server startup failed: MongoParseError/);
  assert.doesNotMatch(result.stderr, /private-sentinel/);
});

test("production health accepts an internal HTTP probe while APIs still require HTTPS", async () => {
  const config = loadConfig({
    ...base,
    NODE_ENV: "production",
    TRUST_PROXY_HOPS: "1",
  });
  let pinged = false;
  const store = {
    db: {
      command: async (command, options) => {
        assert.deepEqual(command, { ping: 1 });
        assert.equal(options.timeoutMS, 3000);
        pinged = true;
        return { ok: 1 };
      },
    },
  };
  const app = createApp({ store, config, hashCost: 8 });
  await request(app).get("/health").expect(200, { status: "ok" });
  assert.equal(pinged, true);
  const insecure = await request(app).get("/api/v1/state").expect(426);
  assert.equal(insecure.body.error.code, "https_required");
  const forwarded = await request(app)
    .get("/api/v1/state")
    .set("X-Forwarded-Proto", "https")
    .expect(401);
  assert.equal(forwarded.body.error.code, "unauthorized");
  const untrustedApp = createApp({
    store,
    config: loadConfig({ ...base, NODE_ENV: "production" }),
    hashCost: 8,
  });
  await request(untrustedApp)
    .get("/api/v1/state")
    .set("X-Forwarded-Proto", "https")
    .expect(426);
});

test("database readiness failure returns no credentials or internal error details", async () => {
  const store = {
    db: {
      command: async () => {
        throw new Error("private diagnostic sentinel");
      },
    },
  };
  const app = createApp({
    store,
    config: loadConfig({ ...base, NODE_ENV: "production" }),
    hashCost: 8,
  });
  const response = await request(app).get("/health").expect(503);
  assert.equal(response.body.error.code, "service_unavailable");
  assert.equal(
    JSON.stringify(response.body).includes("private diagnostic sentinel"),
    false,
  );
  assert.equal(JSON.stringify(response.body).includes("mongodb://"), false);
});

test("readiness has a three-second deadline even if database I/O never settles", async () => {
  const store = { db: { command: async () => new Promise(() => {}) } };
  const app = createApp({
    store,
    config: loadConfig({ ...base, NODE_ENV: "production" }),
    hashCost: 8,
  });
  const started = Date.now();
  const response = await request(app).get("/health").expect(503);
  assert.equal(response.body.error.code, "service_unavailable");
  assert.ok(Date.now() - started < 5000);
});
