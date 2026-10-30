// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import { MongoClient } from "mongodb";
import { ApiError } from "./errors.js";
import { transition, clone } from "./domain.js";

const lists = {
  items: "routines",
  templates: "packageTemplates",
  instances: "challengeInstances",
  ledger: "xpLedger",
  achievements: "achievements",
  categories: "categories",
  selections: "dailyAssignments",
};
const maps = {
  overrides: "routineOverrides",
  records: "completionRecords",
  reminders: "occurrenceReminders",
};
const allCollections = [
  "users",
  "sessions",
  "accountSettings",
  "syncMutations",
  "routineExclusions",
  ...Object.values(lists),
  ...Object.values(maps),
];
export class PlannerStore {
  constructor(client, dbName, { clock = () => new Date() } = {}) {
    this.client = client;
    this.db = client.db(dbName);
    this.clock = clock;
  }
  static async connect(config) {
    const client = new MongoClient(config.MONGODB_URI, {
      appName: "level-up-api",
      serverSelectionTimeoutMS: 5000,
      connectTimeoutMS: 5000,
      socketTimeoutMS: 15000,
      maxPoolSize: 20,
    });
    await client.connect();
    return new PlannerStore(client, config.MONGODB_DATABASE);
  }
  async initialize({ applyValidators = false } = {}) {
    const existing = new Set(
      (await this.db.listCollections({}, { nameOnly: true }).toArray()).map(
        (c) => c.name,
      ),
    );
    for (const name of allCollections) {
      // Additive initialization; never drops, clears, or renames user data.
      const validator = {
        $jsonSchema: {
          bsonType: "object",
          required:
            name === "users"
              ? ["_id", "email", "passwordHash"]
              : ["_id", "ownerId"],
          properties: {
            ownerId: { bsonType: "string" },
            email: { bsonType: "string" },
            passwordHash: { bsonType: "string" },
          },
        },
      };
      if (!existing.has(name))
        await this.db.createCollection(name, {
          validator,
          validationLevel: "strict",
        });
      // Existing validator changes require collMod, which is deliberately not
      // granted to the runtime readWrite user. Only db:init opts into migration.
      else if (applyValidators)
        await this.db.command({
          collMod: name,
          validator,
          validationLevel: "moderate",
        });
    }
    await this.db
      .collection("users")
      .createIndex({ email: 1 }, { unique: true, name: "unique_email" });
    await this.db
      .collection("sessions")
      .createIndex(
        { tokenHash: 1 },
        { unique: true, name: "unique_refresh_hash" },
      );
    await this.db
      .collection("sessions")
      .createIndex(
        { expiresAt: 1 },
        { expireAfterSeconds: 0, name: "expired_refresh_sessions" },
      );
    await this.db
      .collection("syncMutations")
      .createIndex(
        { ownerId: 1, mutationId: 1 },
        { unique: true, name: "owner_mutation" },
      );
    await this.db
      .collection("xpLedger")
      .createIndex(
        { ownerId: 1, "value.idempotencyKey": 1 },
        { unique: true, name: "owner_xp_event" },
      );
    await this.db
      .collection("dailyAssignments")
      .createIndex(
        { ownerId: 1, "value.targetDate": 1 },
        { unique: true, name: "owner_target_date" },
      );
    for (const name of [
      ...Object.values(lists),
      ...Object.values(maps),
      "routineExclusions",
    ])
      await this.db
        .collection(name)
        .createIndex(
          { ownerId: 1, key: 1 },
          { unique: true, name: "owner_record" },
        );
    await this.db
      .collection("accountSettings")
      .createIndex({ ownerId: 1 }, { unique: true, name: "owner_settings" });
    await this.db.collection("schemaMigrations").updateOne(
      { _id: 1 },
      {
        $setOnInsert: {
          appliedAt: this.clock(),
          description:
            "Owner-scoped planner collections and idempotency indexes",
        },
      },
      { upsert: true },
    );
  }
  async transaction(action) {
    const session = this.client.startSession();
    try {
      return await session.withTransaction(() => action(session), {
        readConcern: { level: "snapshot" },
        writeConcern: { w: "majority" },
        readPreference: "primary",
        maxCommitTimeMS: 10000,
      });
    } finally {
      await session.endSession();
    }
  }
  async snapshot(ownerId, session) {
    const meta = await this.db
      .collection("accountSettings")
      .findOne({ ownerId }, { session });
    if (!meta)
      return {
        revision: 0,
        state: null,
        settings: { locale: "en" },
        serverTime: this.clock().toISOString(),
      };
    const state = { ...clone(meta.rules), schemaVersion: 4 };
    // A transaction uses sequential operations; driver transactions do not
    // support Promise.all on the same session.
    for (const [property, name] of Object.entries(lists))
      state[property] = (
        await this.db
          .collection(name)
          .find({ ownerId }, { session })
          .sort({ order: 1 })
          .toArray()
      ).map((d) => d.value);
    for (const [property, name] of Object.entries(maps))
      state[property] = Object.fromEntries(
        (
          await this.db
            .collection(name)
            .find({ ownerId }, { session })
            .sort({ order: 1 })
            .toArray()
        ).map((d) => [d.key, d.value]),
      );
    state.exclusions = (
      await this.db
        .collection("routineExclusions")
        .find({ ownerId }, { session })
        .sort({ order: 1 })
        .toArray()
    ).map((d) => d.key);
    return {
      revision: meta.revision,
      state,
      settings: meta.settings,
      timeZone: meta.timeZone,
      serverTime: this.clock().toISOString(),
    };
  }
  async get(ownerId) {
    return this.transaction(async (session) => {
      const snapshot = await this.snapshot(ownerId, session);
      if (!snapshot.state) return snapshot;
      const meta = await this.db
        .collection("accountSettings")
        .findOne({ ownerId }, { session });
      // Reconciliation is independent of the phone being awake. GET can advance
      // expired deadlines and returns the new revision, never a silent stale copy.
      const next = transition(snapshot.state, snapshot.state, {
        now: this.clock(),
        timeZone: meta.timeZone,
      });
      const stripClock = (s) => ({ ...s, lastObservedAt: null });
      if (
        JSON.stringify(stripClock(next)) !==
        JSON.stringify(stripClock(snapshot.state))
      ) {
        await this.write(
          ownerId,
          next,
          meta.settings,
          meta.timeZone,
          meta.revision + 1,
          session,
        );
        return {
          revision: meta.revision + 1,
          state: next,
          settings: meta.settings,
          serverTime: this.clock().toISOString(),
        };
      }
      return snapshot;
    });
  }
  async sync(ownerId, input) {
    return this.transaction(async (session) => {
      const accepted = await this.db
        .collection("syncMutations")
        .findOne({ ownerId, mutationId: input.mutationId }, { session });
      if (accepted) {
        // A mutation ID is bound to the exact original payload, so accidental ID
        // reuse cannot acknowledge a different write.
        if (accepted.requestHash !== input.requestHash)
          throw new ApiError(
            409,
            "mutation_reused",
            "This mutation identifier was already used.",
          );
        const current = await this.snapshot(ownerId, session);
        if (current.revision !== accepted.revision)
          throw new ApiError(
            409,
            "revision_conflict",
            "This write was accepted, but newer cloud data now requires review.",
            current,
          );
        return current;
      }
      const current = await this.snapshot(ownerId, session);
      if (current.revision !== input.baseRevision)
        throw new ApiError(
          409,
          "revision_conflict",
          "Cloud data changed. Review the retained local changes before retrying.",
          current,
        );
      const next = transition(current.state, input.state, {
        now: this.clock(),
        timeZone: input.timeZone,
      });
      const revision = current.revision + 1;
      await this.write(
        ownerId,
        next,
        input.settings,
        input.timeZone,
        revision,
        session,
      );
      await this.db.collection("syncMutations").insertOne(
        {
          _id: `${ownerId}:${input.mutationId}`,
          ownerId,
          mutationId: input.mutationId,
          requestHash: input.requestHash,
          revision,
          createdAt: this.clock(),
        },
        { session },
      );
      return {
        revision,
        state: next,
        settings: input.settings,
        serverTime: this.clock().toISOString(),
      };
    });
  }
  async write(ownerId, state, settings, timeZone, revision, session) {
    const timestamp = this.clock();
    for (const [property, name] of Object.entries(lists))
      await this.replaceRecords(
        name,
        ownerId,
        state[property].map((value, order) => ({
          key: property === "selections" ? value.targetDate : value.id,
          value,
          order,
        })),
        session,
        timestamp,
      );
    for (const [property, name] of Object.entries(maps))
      await this.replaceRecords(
        name,
        ownerId,
        Object.entries(state[property]).map(([key, value], order) => ({
          key,
          value,
          order,
        })),
        session,
        timestamp,
      );
    await this.replaceRecords(
      "routineExclusions",
      ownerId,
      state.exclusions.map((key, order) => ({ key, value: true, order })),
      session,
      timestamp,
    );
    const rules = {
      templatesInitialized: state.templatesInitialized,
      selectionDeadlineMinute: state.selectionDeadlineMinute,
      missedSelectionPenalty: state.missedSelectionPenalty,
      lastObservedAt: state.lastObservedAt,
    };
    await this.db.collection("accountSettings").updateOne(
      { ownerId },
      {
        $set: { revision, rules, settings, timeZone, updatedAt: timestamp },
        $setOnInsert: { _id: ownerId, ownerId, createdAt: timestamp },
      },
      { upsert: true, session },
    );
  }
  async replaceRecords(name, ownerId, entries, session, timestamp) {
    const collection = this.db.collection(name);
    const keys = entries.map((e) => e.key);
    await collection.deleteMany({ ownerId, key: { $nin: keys } }, { session });
    if (entries.length)
      await collection.bulkWrite(
        entries.map((e) => ({
          updateOne: {
            filter: { ownerId, key: e.key },
            update: {
              $set: { value: e.value, order: e.order, updatedAt: timestamp },
              $setOnInsert: {
                _id: `${ownerId}:${e.key}`,
                ownerId,
                key: e.key,
                createdAt: timestamp,
              },
            },
            upsert: true,
          },
        })),
        { session, ordered: true },
      );
  }
}
