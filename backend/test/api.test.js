import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { MongoMemoryReplSet } from "mongodb-memory-server";
import { MongoClient } from "mongodb";
import request from "supertest";
import { PlannerStore } from "../src/store.js";
import { createApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { empty, routine } from "./fixtures.js";
let replica, client, store, app, config, alice, bob;
let clock = new Date("2026-10-29T12:00:00.000Z");
const password = "A-long-test-password-123";
const auth = (account) => `Bearer ${account.accessToken}`;
const sync = (account, input) =>
  request(app)
    .post("/api/v1/sync")
    .set("Authorization", auth(account))
    .send(input);
before(
  async () => {
    replica = await MongoMemoryReplSet.create({
      binary: { version: "8.0.17" },
      replSet: { count: 1, storageEngine: "wiredTiger" },
    });
    client = new MongoClient(replica.getUri(), {
      serverSelectionTimeoutMS: 5000,
    });
    await client.connect();
    store = new PlannerStore(client, "level_up_api_tests", {
      clock: () => clock,
    });
    await store.initialize();
    config = loadConfig({
      NODE_ENV: "test",
      MONGODB_URI: replica.getUri(),
      JWT_SECRET: "test-only-random-secret-with-more-than-thirty-two-bytes",
    });
    app = createApp({ store, config, hashCost: 8, authLimit: 100 });
  },
  { timeout: 240000 },
);
after(async () => {
  await client?.close();
  await replica?.stop();
});
test("health endpoint is connected to a real Mongo replica set", async () => {
  await request(app).get("/health").expect(200, { status: "ok" });
});
test("register, case-insensitive unique email, login and safe passwords", async () => {
  alice = (
    await request(app)
      .post("/api/v1/auth/register")
      .send({ email: "Alice@example.test", password })
      .expect(201)
  ).body;
  bob = (
    await request(app)
      .post("/api/v1/auth/register")
      .send({ email: "bob@example.test", password })
      .expect(201)
  ).body;
  await request(app)
    .post("/api/v1/auth/register")
    .send({ email: "alice@example.test", password })
    .expect(409);
  await request(app)
    .post("/api/v1/auth/login")
    .send({ email: "alice@example.test", password: "wrong-long-password" })
    .expect(401);
  await request(app)
    .post("/api/v1/auth/register")
    .send({ email: "short@example.test", password: "tiny" })
    .expect(422);
  const user = await store.db
    .collection("users")
    .findOne({ _id: alice.user.id });
  assert.notEqual(user.passwordHash, password);
  assert.match(user.passwordHash, /^\$2/);
  const logged = (
    await request(app)
      .post("/api/v1/auth/login")
      .send({ email: "ALICE@example.test", password })
      .expect(200)
  ).body;
  assert.equal(logged.user.id, alice.user.id);
});
test("protected endpoints reject missing, forged and expired access tokens", async () => {
  await request(app).get("/api/v1/state").expect(401);
  await request(app)
    .get("/api/v1/state")
    .set("Authorization", "Bearer forged.token.value")
    .expect(401);
  clock = new Date("2026-10-29T12:16:00.000Z");
  await request(app)
    .get("/api/v1/state")
    .set("Authorization", auth(alice))
    .expect(401);
  clock = new Date("2026-10-29T12:00:00.000Z");
});
test("cloud import is acknowledged, split across collections, restored and owner-isolated", async () => {
  const initial = await request(app)
    .get("/api/v1/state")
    .set("Authorization", auth(alice))
    .expect(200);
  assert.equal(initial.body.state, null);
  const input = {
    mutationId: "import-one",
    baseRevision: 0,
    state: empty({ items: [routine()] }),
    settings: { locale: "ar" },
    timeZone: "UTC",
  };
  const saved = (await sync(alice, input).expect(200)).body;
  assert.equal(saved.revision, 1);
  assert.equal(saved.state.items.length, 1);
  assert.equal(saved.settings.locale, "ar");
  const fresh = (
    await request(app)
      .get("/api/v1/state")
      .set("Authorization", auth(alice))
      .expect(200)
  ).body;
  assert.equal(fresh.state.items[0].title, "Read");
  const other = (
    await request(app)
      .get("/api/v1/state")
      .set("Authorization", auth(bob))
      .query({ ownerId: alice.user.id })
      .expect(200)
  ).body;
  assert.equal(other.state, null);
  assert.equal(
    await store.db
      .collection("routines")
      .countDocuments({ ownerId: alice.user.id }),
    1,
  );
  assert.equal(
    await store.db
      .collection("accountSettings")
      .countDocuments({ ownerId: alice.user.id }),
    1,
  );
});
test("repeated and concurrent retries cannot duplicate a transaction; stale updates conflict", async () => {
  const snapshot = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  const input = {
    mutationId: "change-one",
    baseRevision: snapshot.revision,
    state: { ...snapshot.state, items: [routine({ title: "Updated" })] },
    settings: snapshot.settings,
    timeZone: "UTC",
  };
  const replies = await Promise.all([sync(alice, input), sync(alice, input)]);
  assert.deepEqual(
    replies.map((r) => r.status),
    [200, 200],
  );
  assert.equal(replies[0].body.revision, replies[1].body.revision);
  assert.equal(
    await store.db
      .collection("syncMutations")
      .countDocuments({ ownerId: alice.user.id, mutationId: "change-one" }),
    1,
  );
  const reorder = (value) =>
    Array.isArray(value)
      ? value.map(reorder)
      : value && typeof value === "object"
        ? Object.fromEntries(
            Object.entries(value)
              .reverse()
              .map(([k, v]) => [k, reorder(v)]),
          )
        : value;
  await sync(alice, reorder(input)).expect(200);
  const conflict = await sync(alice, { ...input, mutationId: "stale" }).expect(
    409,
  );
  assert.equal(conflict.body.error.code, "revision_conflict");
  assert.equal(conflict.body.state.items[0].title, "Updated");
  await sync(alice, { ...input, state: { ...input.state, items: [] } }).expect(
    409,
  );
  const latest = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  await sync(alice, {
    mutationId: "advance",
    baseRevision: latest.revision,
    state: latest.state,
    settings: latest.settings,
    timeZone: "UTC",
  }).expect(200);
  const acceptedButAdvanced = await sync(alice, input).expect(409);
  assert.equal(acceptedButAdvanced.body.error.code, "revision_conflict");
});
test("invalid fields and arbitrary XP cannot modify accepted cloud data", async () => {
  const snapshot = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  await sync(alice, {
    mutationId: "foreign-user",
    baseRevision: snapshot.revision,
    state: snapshot.state,
    settings: snapshot.settings,
    timeZone: "UTC",
    userId: bob.user.id,
  }).expect(422);
  const tampered = structuredClone(snapshot.state);
  tampered.ledger.push({
    id: "cheat",
    reason: "cheat",
    change: 999,
    type: "challenge_completion",
    at: clock.toISOString(),
    idempotencyKey: "package:cheat",
    relatedId: "cheat",
  });
  await sync(alice, {
    mutationId: "xp-cheat",
    baseRevision: snapshot.revision,
    state: tampered,
    settings: snapshot.settings,
    timeZone: "UTC",
  }).expect(422);
  const unchanged = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  assert.equal(unchanged.revision, snapshot.revision);
  assert.deepEqual(unchanged.state.ledger, []);
});
test("additive initialization preserves existing data and indexes", async () => {
  await store.initialize();
  assert.equal(
    await store.db
      .collection("routines")
      .countDocuments({ ownerId: alice.user.id }),
    1,
  );
  const indexes = await store.db.collection("xpLedger").indexes();
  assert.equal(indexes.find((i) => i.name === "owner_xp_event").unique, true);
});

test("runtime initialization avoids collMod while explicit migrations apply validators", async () => {
  const originalCommand = store.db.command;
  const modified = [];
  store.db.command = async function (command, ...args) {
    if (command.collMod) modified.push(command.collMod);
    return originalCommand.call(this, command, ...args);
  };
  try {
    await store.initialize();
    assert.deepEqual(modified, []);
    await store.initialize({ applyValidators: true });
    assert.ok(modified.includes("users"));
    assert.ok(modified.includes("xpLedger"));
    assert.equal(
      await store.db
        .collection("routines")
        .countDocuments({ ownerId: alice.user.id }),
      1,
    );
  } finally {
    store.db.command = originalCommand;
  }
});
test("multi-collection sync rolls back completely when a later write fails", async () => {
  const snapshot = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  const original = store.replaceRecords;
  store.replaceRecords = async function (name, ...args) {
    if (name === "xpLedger")
      throw new Error("Injected test transaction interruption");
    return original.call(this, name, ...args);
  };
  try {
    await sync(alice, {
      mutationId: "rollback",
      baseRevision: snapshot.revision,
      state: {
        ...snapshot.state,
        items: [routine({ title: "Must not persist" })],
      },
      settings: snapshot.settings,
      timeZone: "UTC",
    }).expect(503);
  } finally {
    store.replaceRecords = original;
  }
  const after = (
    await request(app).get("/api/v1/state").set("Authorization", auth(alice))
  ).body;
  assert.equal(after.revision, snapshot.revision);
  assert.equal(after.state.items[0].title, "Updated");
  assert.equal(
    await store.db
      .collection("syncMutations")
      .countDocuments({ ownerId: alice.user.id, mutationId: "rollback" }),
    0,
  );
});
test("refresh rotates opaque hashed token and revokes old access; logout revokes new access", async () => {
  const refresh = (
    await request(app)
      .post("/api/v1/auth/refresh")
      .send({ refreshToken: alice.refreshToken })
      .expect(200)
  ).body;
  assert.notEqual(refresh.refreshToken, alice.refreshToken);
  await request(app)
    .post("/api/v1/auth/refresh")
    .send({ refreshToken: alice.refreshToken })
    .expect(401);
  await request(app)
    .get("/api/v1/state")
    .set("Authorization", auth(alice))
    .expect(401);
  const saved = await store.db
    .collection("sessions")
    .findOne({ ownerId: alice.user.id, revokedAt: null });
  assert.notEqual(saved.tokenHash, refresh.refreshToken);
  await request(app)
    .get("/api/v1/state")
    .set("Authorization", auth(refresh))
    .expect(200);
  await request(app)
    .post("/api/v1/auth/logout")
    .send({ refreshToken: refresh.refreshToken })
    .expect(204);
  await request(app)
    .get("/api/v1/state")
    .set("Authorization", auth(refresh))
    .expect(401);
});
test("strict CORS and rate limiting are enabled", async () => {
  await request(app)
    .get("/health")
    .set("Origin", "https://untrusted.example")
    .expect(403);
  const limited = createApp({ store, config, hashCost: 8, authLimit: 1 });
  await request(limited)
    .post("/api/v1/auth/login")
    .send({ email: "bob@example.test", password })
    .expect(200);
  const response = await request(limited)
    .post("/api/v1/auth/login")
    .send({ email: "bob@example.test", password })
    .expect(429);
  assert.equal(response.body.error.code, "rate_limited");
});
