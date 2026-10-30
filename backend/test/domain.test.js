import test from "node:test";
import assert from "node:assert/strict";
import { transition, balance } from "../src/domain.js";
import { parse, stateSchema } from "../src/schema.js";
import {
  empty,
  task,
  template,
  routine,
  instance,
  pending,
  ledger,
} from "./fixtures.js";
const now = new Date("2026-10-29T12:00:00.000Z");
const apply = (previous, next, at = now) =>
  transition(previous, parse(stateSchema, next), { now: at, timeZone: "UTC" });

test("imports provable legacy 15 XP and schema3 snapshots without retrofitting skip rules", () => {
  const t = template({
    rewardMode: "legacyPerTask",
    skipPenalty: null,
    tasks: [task("leaf", { skipPenalty: 5, rewardXp: 10 })],
    completionXp: 30,
  });
  const state = empty({
    schemaVersion: 3,
    items: [routine(), routine({ id: "second" })],
    instances: [instance(t)],
    records: {
      "routine@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T09:00:00.000Z",
      },
      "second@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T11:00:00.000Z",
      },
      "instance/leaf@2026-10-29": {
        ...pending(),
        status: "skipped",
        at: "2026-10-29T10:00:00.000Z",
      },
    },
    ledger: [
      ledger(
        "complete:routine@2026-10-29",
        10,
        "task_completion",
        "routine@2026-10-29",
      ),
      ledger(
        "skip:instance/leaf@2026-10-29",
        -5,
        "task_skip",
        "instance/leaf@2026-10-29",
      ),
      ledger(
        "complete:second@2026-10-29",
        10,
        "task_completion",
        "second@2026-10-29",
      ),
    ],
  });
  const result = apply(null, state);
  assert.equal(balance(result), 15);
  assert.equal(result.schemaVersion, 4);
  assert.equal(result.instances[0].snapshot.skipPenalty, null);
  assert.deepEqual(result.ledger, state.ledger);
});
test("rejects arbitrary imported XP and preserves caller input", () => {
  const state = empty({
    items: [routine()],
    records: {
      "routine@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T10:00:00.000Z",
      },
    },
    ledger: [
      ledger(
        "complete:routine@2026-10-29",
        999,
        "task_completion",
        "routine@2026-10-29",
      ),
    ],
  });
  const before = structuredClone(state);
  assert.throws(
    () => apply(null, state),
    (e) => e.code === "history_conflict",
  );
  assert.deepEqual(state, before);
});
test("new routine completion never creates challenge XP", () => {
  const old = apply(null, empty({ items: [routine()] })),
    next = structuredClone(old);
  next.records["routine@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  assert.equal(balance(apply(old, next)), 0);
});
test("package skip is once, clamps at zero, blocks completion, keeps active until deadline", () => {
  const t = template(),
    old = apply(
      null,
      empty({
        instances: [instance(t)],
        records: { "instance/leaf@2026-10-29": pending() },
      }),
    );
  const next = structuredClone(old);
  next.records["instance/leaf@2026-10-29"] = {
    ...pending(),
    status: "skipped",
    at: now.toISOString(),
  };
  next.ledger.push(
    ledger(
      "skip:instance/leaf@2026-10-29",
      -999,
      "task_skip",
      "instance/leaf@2026-10-29",
    ),
  );
  let result = apply(old, next);
  assert.equal(result.ledger.length, 1);
  assert.equal(result.ledger[0].change, 0);
  assert.equal(result.instances[0].status, "active");
  result = apply(result, result);
  assert.equal(result.ledger.length, 1);
  result = apply(result, result, new Date("2026-10-30T00:00:00.000Z"));
  assert.equal(result.instances[0].status, "failed");
  assert.equal(
    result.ledger.filter((e) => e.type === "challenge_failure").length,
    1,
  );
});
test("legacy packageOnly null skip preserves no-skip-ledger capture", () => {
  const old = apply(
      null,
      empty({
        instances: [instance(template({ skipPenalty: null }))],
        records: { "instance/leaf@2026-10-29": pending() },
      }),
    ),
    next = structuredClone(old);
  next.records["instance/leaf@2026-10-29"] = {
    ...pending(),
    status: "skipped",
    at: now.toISOString(),
  };
  assert.equal(apply(old, next).ledger.length, 0);
});
test("nested group completes only when every required descendant completes and XP is derived once", () => {
  const t = template({
      tasks: [
        task("group", { type: "group" }),
        task("one", { parentId: "group" }),
        task("deeper", { type: "group", parentId: "group" }),
        task("two", { parentId: "deeper" }),
      ],
    }),
    old = apply(
      null,
      empty({
        instances: [instance(t)],
        records: {
          "instance/one@2026-10-29": pending(),
          "instance/two@2026-10-29": pending(),
        },
      }),
    );
  let next = structuredClone(old);
  next.records["instance/one@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  let result = apply(old, next);
  assert.equal(result.instances[0].status, "active");
  next = structuredClone(result);
  next.records["instance/two@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  next.ledger.push(
    ledger("package:instance", 999, "challenge_completion", "instance"),
  );
  result = apply(result, next);
  assert.equal(result.instances[0].status, "completed");
  assert.equal(balance(result), 80);
  assert.equal(apply(result, result).ledger.length, 1);
});
test("invalid trees, parent-completion records and immutable snapshot changes are rejected", () => {
  assert.throws(
    () =>
      apply(
        null,
        empty({
          templates: [template({ tasks: [task("g", { type: "group" })] })],
        }),
      ),
    /required children/,
  );
  const old = apply(
      null,
      empty({
        instances: [instance()],
        records: { "instance/leaf@2026-10-29": pending() },
      }),
    ),
    next = structuredClone(old);
  next.instances[0].snapshot.completionXp = 999;
  assert.throws(
    () => apply(old, next),
    (e) => e.code === "history_conflict",
  );
});
test("late offline completion is rejected using server receipt time", () => {
  const old = apply(
      null,
      empty({
        instances: [instance()],
        records: { "instance/leaf@2026-10-29": pending() },
      }),
    ),
    next = structuredClone(old);
  next.records["instance/leaf@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  assert.throws(
    () => apply(old, next, new Date("2026-10-30T01:00:00.000Z")),
    (e) => e.code === "deadline_passed",
  );
});
test("missed selection deadline creates one event through repeated resume", () => {
  let result = apply(null, empty());
  result = apply(result, result, new Date("2026-10-29T23:59:00.000Z"));
  assert.equal(result.selections[0].missedAt, "2026-10-29T23:59:00.000Z");
  assert.equal(
    result.ledger.filter((e) => e.type === "missed_selection").length,
    1,
  );
  assert.equal(
    apply(result, result, new Date("2026-10-30T00:01:00.000Z")).ledger.filter(
      (e) => e.type === "missed_selection",
    ).length,
    1,
  );
});
test("tampered post-import client ledger delta cannot mint XP", () => {
  const old = apply(null, empty()),
    next = structuredClone(old);
  next.ledger.push(
    ledger("package:made-up", 5000, "challenge_completion", "made-up"),
  );
  assert.throws(
    () => apply(old, next),
    (e) => e.code === "history_conflict",
  );
});
test("assignment captures template, unique target date and server-derived timezone deadline", () => {
  const old = apply(null, empty({ templates: [template()] })),
    next = structuredClone(old);
  next.instances.push(
    instance(template(), {
      id: "tomorrow-instance",
      startedAt: now.toISOString(),
      startDate: "2026-10-30",
      deadline: "2026-10-31T00:00:00.000Z",
    }),
  );
  next.selections[0].instanceId = "tomorrow-instance";
  next.records["tomorrow-instance/leaf@2026-10-30"] = pending();
  const result = apply(old, next);
  assert.equal(result.instances.length, 1);
  assert.equal(result.selections[0].instanceId, "tomorrow-instance");
  assert.equal(
    result.records["tomorrow-instance/leaf@2026-10-30"].status,
    "pending",
  );
  const edited = structuredClone(result);
  edited.templates[0].name = "Renamed reusable package";
  assert.equal(
    apply(result, edited).instances[0].snapshot.name,
    "Morning Routine",
  );
  const duplicate = structuredClone(result);
  duplicate.instances.push({ ...duplicate.instances[0], id: "other" });
  duplicate.records["other/leaf@2026-10-30"] = pending();
  assert.throws(
    () => apply(result, duplicate),
    (e) => e.code === "deadline_passed",
  );
});
test("rule change cannot reopen an expired daily selection", () => {
  const old = apply(null, empty({ selectionDeadlineMinute: 720 }));
  assert.equal(old.selections[0].missedAt !== null, true);
  const next = structuredClone(old);
  next.selectionDeadlineMinute = 1439;
  assert.equal(
    apply(old, next).selections[0].missedAt,
    old.selections[0].missedAt,
  );
});
test("group records cannot auto-complete child tasks", () => {
  const t = template({
      tasks: [task("g", { type: "group" }), task("child", { parentId: "g" })],
    }),
    old = apply(
      null,
      empty({
        instances: [instance(t)],
        records: { "instance/child@2026-10-29": pending() },
      }),
    ),
    next = structuredClone(old);
  next.records["instance/g@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  assert.throws(() => apply(old, next));
  assert.equal(old.records["instance/child@2026-10-29"].status, "pending");
});

test("a routine moved earlier is available on its actual day while retaining the anchor ID", () => {
  const id = "routine@2026-10-30";
  const old = apply(
    null,
    empty({
      items: [routine(), routine({ id: "prerequisite" })],
      overrides: {
        [id]: routine({
          date: "2026-10-29",
          recurrence: "once",
          dependencies: ["prerequisite"],
        }),
      },
      records: {
        [id]: pending(),
        "prerequisite@2026-10-29": {
          ...pending(),
          status: "completed",
          at: now.toISOString(),
        },
      },
    }),
  );
  const next = structuredClone(old);
  next.records[id] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  const result = apply(old, next);
  assert.equal(result.records[id].status, "completed");
  assert.equal(result.records["routine@2026-10-29"], undefined);
  assert.equal(balance(result), 0);
});

test("a routine moved later cannot be completed before its actual day", () => {
  const id = "routine@2026-10-29";
  const old = apply(
    null,
    empty({
      items: [routine()],
      overrides: { [id]: routine({ date: "2026-10-30", recurrence: "once" }) },
      records: { [id]: pending() },
    }),
  );
  const next = structuredClone(old);
  next.records[id] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  assert.throws(() => apply(old, next), /Future tasks/);
  assert.equal(old.records[id].status, "pending");
});

test("routine prerequisites may use a completed earlier one-time occurrence", () => {
  const old = apply(
    null,
    empty({
      items: [
        routine({ dependencies: ["prerequisite"] }),
        routine({ id: "prerequisite", date: "2026-10-28", recurrence: "once" }),
      ],
      records: {
        "prerequisite@2026-10-28": {
          ...pending(),
          status: "completed",
          at: "2026-10-28T12:00:00.000Z",
        },
      },
    }),
  );
  const next = structuredClone(old);
  next.records["routine@2026-10-29"] = {
    ...pending(),
    status: "completed",
    at: now.toISOString(),
  };
  assert.equal(
    apply(old, next).records["routine@2026-10-29"].status,
    "completed",
  );
});

test("unearned, unknown, future and pre-qualification imported achievements are rejected", () => {
  const earned = empty({
    items: [routine()],
    records: {
      "routine@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T10:00:00.000Z",
      },
    },
  });
  for (const achievement of [
    { id: "first-hard", title: "Unearned", unlockedAt: now.toISOString() },
    { id: "unknown-legacy", title: "Unknown", unlockedAt: now.toISOString() },
    {
      id: "first-task",
      title: "Future",
      unlockedAt: "2030-01-01T00:00:00.000Z",
    },
    {
      id: "first-task",
      title: "Before activity",
      unlockedAt: "2026-10-28T00:00:00.000Z",
    },
  ])
    assert.throws(
      () => apply(null, { ...earned, achievements: [achievement] }),
      (error) => error.code === "history_conflict",
    );
});

test("earned imported first-task achievement retains its captured title and time", () => {
  const achievement = {
    id: "first-task",
    title: "Captured local achievement",
    unlockedAt: "2026-10-29T11:00:00.000Z",
  };
  const state = empty({
    items: [routine()],
    records: {
      "routine@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T10:00:00.000Z",
      },
    },
    achievements: [achievement],
  });
  assert.deepEqual(
    apply(null, state).achievements.find(
      (entry) => entry.id === achievement.id,
    ),
    achievement,
  );
});

test("earned hard-package and seven-day imported achievements require real qualifying history", () => {
  const hard = instance(template({ difficulty: "hard" }), {
    status: "completed",
    endedAt: "2026-10-29T11:00:00.000Z",
  });
  const hardAchievement = {
    id: "first-hard",
    title: "Captured hard",
    unlockedAt: "2026-10-29T11:30:00.000Z",
  };
  const hardState = empty({
    instances: [hard],
    records: {
      "instance/leaf@2026-10-29": {
        ...pending(),
        status: "completed",
        at: "2026-10-29T10:00:00.000Z",
      },
    },
    ledger: [
      ledger("package:instance", 80, "challenge_completion", "instance"),
    ],
    achievements: [hardAchievement],
  });
  assert.deepEqual(
    apply(null, hardState).achievements.find(
      (entry) => entry.id === "first-hard",
    ),
    hardAchievement,
  );
  const records = Object.fromEntries(
    Array.from({ length: 7 }, (_, index) => {
      const date = `2026-10-${23 + index}`;
      return [
        `routine@${date}`,
        { ...pending(), status: "completed", at: `${date}T10:00:00.000Z` },
      ];
    }),
  );
  const streakAchievement = {
    id: "seven-days",
    title: "Captured streak",
    unlockedAt: "2026-10-29T11:00:00.000Z",
  };
  const streakState = empty({
    items: [routine({ date: "2026-10-23" })],
    records,
    achievements: [streakAchievement],
  });
  assert.deepEqual(
    apply(null, streakState).achievements.find(
      (entry) => entry.id === "seven-days",
    ),
    streakAchievement,
  );
});

test("first import rejects orphan or mismatched daily assignment references", () => {
  const selection = {
    targetDate: "2026-10-30",
    deadline: "2026-10-29T23:59:00.000Z",
    penalty: 5,
    instanceId: "nonexistent",
    missedAt: null,
    acknowledged: false,
  };
  assert.throws(
    () => apply(null, empty({ selections: [selection] })),
    (error) => error.code === "history_conflict",
  );
  const state = empty({
    instances: [instance()],
    records: { "instance/leaf@2026-10-29": pending() },
    selections: [{ ...selection, instanceId: "instance" }],
  });
  assert.throws(
    () => apply(null, state),
    (error) => error.code === "history_conflict",
  );
  state.selections[0] = {
    ...selection,
    targetDate: "2026-10-29",
    deadline: state.instances[0].startedAt,
    instanceId: "instance",
  };
  assert.throws(
    () => apply(null, state),
    (error) => error.code === "history_conflict",
  );
});

test("first import rejects conflicting missed outcomes and invalid frozen deadlines", () => {
  const state = empty({
    instances: [instance()],
    records: { "instance/leaf@2026-10-29": pending() },
  });
  state.selections.push({
    targetDate: "2026-10-29",
    deadline: "2026-10-28T23:59:00.000Z",
    penalty: 5,
    instanceId: "instance",
    missedAt: "2026-10-28T23:59:00.000Z",
    acknowledged: false,
  });
  assert.throws(
    () => apply(null, state),
    (error) => error.code === "history_conflict",
  );
  state.selections = [];
  state.instances[0].deadline = "2026-10-31T00:00:00.000Z";
  assert.throws(
    () => apply(null, state),
    (error) => error.code === "history_conflict",
  );
});

test("first import rejects missing task records and noncontiguous legacy steps", () => {
  assert.throws(
    () => apply(null, empty({ instances: [instance()] })),
    (error) => error.code === "history_conflict",
  );
  const state = empty({
    instances: [
      instance(template({ tasks: [task("leaf", { steps: ["one", "two"] })] })),
    ],
    records: {
      "instance/leaf@2026-10-29": {
        ...pending(),
        completedSteps: [1],
        at: now.toISOString(),
      },
    },
  });
  assert.throws(
    () => apply(null, state),
    (error) => error.code === "history_conflict",
  );
});

test("selection deadline uses local wall-clock minutes across both DST transitions", () => {
  for (const [now, expected] of [
    ["2026-03-08T12:00:00.000Z", "2026-03-09T03:59:00.000Z"],
    ["2026-11-01T12:00:00.000Z", "2026-11-02T04:59:00.000Z"],
  ]) {
    const state = transition(null, parse(stateSchema, empty()), {
      now: new Date(now),
      timeZone: "America/New_York",
    });
    assert.equal(state.selections[0].deadline, expected);
  }
});
