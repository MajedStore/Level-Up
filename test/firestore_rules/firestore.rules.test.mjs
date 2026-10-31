import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { after, before, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  disableNetwork,
  enableNetwork,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "demo-level-up-rules";
const emptyPlanner = {
  schemaVersion: 4,
  items: [],
  overrides: {},
  exclusions: [],
  records: {},
  instances: [],
  ledger: [],
  achievements: [],
  reminders: {},
  templates: [],
  templatesInitialized: false,
  categories: [],
  selections: [],
  selectionDeadlineMinute: 1439,
  missedSelectionPenalty: 5,
  lastObservedAt: null,
};
const emptyPrivate = {
  habits: {},
  categories: {},
  notes: {},
  focus: {},
  todos: {},
  todoTags: {},
};

let environment;
let owner;
let stranger;
let unauthenticated;

const plannerRef = (db, uid) => doc(db, `users/${uid}/planner/state`);
const privateRef = (db, uid) => doc(db, `users/${uid}/private/state`);
const mutationRef = (db, uid, area, id) =>
  doc(db, `users/${uid}/${area}/state/mutations/${id}`);

const digest = (value) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");

async function transactSnapshot(db, uid, area, baseRevision, id, payload) {
  const state = doc(db, `users/${uid}/${area}/state`);
  const mutation = mutationRef(db, uid, area, id);
  const requestHash = digest({ baseRevision, id, payload });
  return runTransaction(db, async (transaction) => {
    const current = await transaction.get(state);
    assert.equal(current.data()?.revision ?? 0, baseRevision);
    const revision = baseRevision + 1;
    const envelope = area === "planner"
      ? {
          schemaVersion: 1,
          revision,
          state: payload.state,
          settings: payload.settings,
          timeZone: payload.timeZone,
          lastMutationId: id,
          updatedAt: serverTimestamp(),
        }
      : {
          schemaVersion: 1,
          revision,
          data: payload.data,
          lastMutationId: id,
          updatedAt: serverTimestamp(),
        };
    transaction.set(state, envelope);
    transaction.set(mutation, {
      requestHash,
      baseRevision,
      revision,
      createdAt: serverTimestamp(),
    });
    return revision;
  });
}

before(async () => {
  const rules = await readFile(new URL("../../firestore.rules", import.meta.url), "utf8");
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
  owner = environment.authenticatedContext("owner-uid").firestore();
  stranger = environment.authenticatedContext("other-uid").firestore();
  unauthenticated = environment.unauthenticatedContext().firestore();
});

after(async () => {
  await environment?.cleanup();
});

test("planner snapshot writes atomically for its owner and isolates other UIDs", async () => {
  await assertSucceeds(
    transactSnapshot(owner, "owner-uid", "planner", 0, "planner-first", {
      state: emptyPlanner,
      settings: { locale: "en" },
      timeZone: "Europe/Istanbul",
    }),
  );
  await assertSucceeds(getDoc(plannerRef(owner, "owner-uid")));
  await assertFails(getDoc(plannerRef(stranger, "owner-uid")));
  await assertFails(getDoc(plannerRef(unauthenticated, "owner-uid")));
  await assertFails(
    transactSnapshot(stranger, "owner-uid", "planner", 1, "attack-write", {
      state: emptyPlanner,
      settings: { locale: "en" },
      timeZone: "UTC",
    }),
  );
});

test("planner rules reject unknown fields, invalid schema and unpaired writes", async () => {
  const db = owner;
  const ref = plannerRef(db, "owner-uid");
  const malformed = {
    schemaVersion: 1,
    revision: 2,
    state: { ...emptyPlanner, injected: true },
    settings: { locale: "en" },
    timeZone: "UTC",
    lastMutationId: "unpaired-write",
    updatedAt: serverTimestamp(),
  };
  await assertFails(updateDoc(ref, malformed));
  await assertFails(
    transactSnapshot(db, "owner-uid", "planner", 1, "bad-locale", {
      state: emptyPlanner,
      settings: { locale: "secret" },
      timeZone: "UTC",
    }),
  );
});

test("revision transactions allow only one concurrent writer for the same base", async () => {
  const writes = await Promise.allSettled([
    transactSnapshot(owner, "owner-uid", "planner", 1, "planner-race-a", {
      state: emptyPlanner,
      settings: { locale: "en" },
      timeZone: "UTC",
    }),
    transactSnapshot(owner, "owner-uid", "planner", 1, "planner-race-b", {
      state: emptyPlanner,
      settings: { locale: "ar" },
      timeZone: "UTC",
    }),
  ]);
  assert.equal(writes.filter((value) => value.status === "fulfilled").length, 1);
  assert.equal((await getDoc(plannerRef(owner, "owner-uid"))).data().revision, 2);
});

test("private snapshots are owner scoped and reject invalid collection shapes", async () => {
  await assertSucceeds(
    transactSnapshot(owner, "owner-uid", "private", 0, "private-first", {
      data: emptyPrivate,
    }),
  );
  await assertSucceeds(getDoc(privateRef(owner, "owner-uid")));
  await assertFails(getDoc(privateRef(stranger, "owner-uid")));
  await assertFails(
    transactSnapshot(owner, "owner-uid", "private", 1, "private-invalid", {
      data: { ...emptyPrivate, settings: {} },
    }),
  );
});

test("mutation records are immutable and cannot advance a snapshot alone", async () => {
  const ref = mutationRef(owner, "owner-uid", "planner", "planner-first");
  await assertFails(updateDoc(ref, { revision: 100 }));
  await assertFails(
    setDoc(mutationRef(owner, "owner-uid", "planner", "forged-alone"), {
      requestHash: "a".repeat(64),
      baseRevision: 1,
      revision: 2,
      createdAt: serverTimestamp(),
    }),
  );
});

test("a pending snapshot sync completes after network is restored", async () => {
  const offlineClient = environment.authenticatedContext("offline-uid").firestore();
  await disableNetwork(offlineClient);
  const pendingSync = transactSnapshot(
    offlineClient,
    "offline-uid",
    "private",
    0,
    "offline-first",
    { data: emptyPrivate },
  );
  await enableNetwork(offlineClient);
  await assertSucceeds(pendingSync);
  assert.equal(
    (await getDoc(privateRef(offlineClient, "offline-uid"))).data().revision,
    1,
  );
});
