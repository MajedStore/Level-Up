import test from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
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
  assert.equal(loadConfig(base).HOST, "127.0.0.1");
  assert.equal(loadConfig({ ...base, HOST: "127.0.0.2" }).HOST, "127.0.0.2");
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
