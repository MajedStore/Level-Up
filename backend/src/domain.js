// Level Up — Based on Streak by InlitX. GPL-3.0-only.
// This module never accepts an XP delta as authority. Every delta is computed
// from a verified occurrence, frozen package rule, or daily-selection outcome.
import { randomUUID } from "node:crypto";
import { DateTime } from "luxon";
import { invalid, requireRule as rule } from "./errors.js";

export const clone = (value) => structuredClone(value);
const sortKeys = (v) =>
  Array.isArray(v)
    ? v.map(sortKeys)
    : v && typeof v === "object"
      ? Object.fromEntries(
          Object.keys(v)
            .sort()
            .map((k) => [k, sortKeys(v[k])]),
        )
      : v;
export const equal = (a, b) =>
  JSON.stringify(sortKeys(a)) === JSON.stringify(sortKeys(b));
const byId = (list) => new Map(list.map((v) => [v.id, v]));
const unique = (list, key = "id") =>
  list.length === new Set(list.map((x) => x[key])).size;
const iso = (value, zone) => DateTime.fromISO(value, { zone, setZone: true });
const millis = (value, zone) => iso(value, zone).toMillis();
const utc = (value) => value.toUTC().toISO({ suppressMilliseconds: false });
const day = (value, zone) => DateTime.fromISO(value, { zone }).startOf("day");
const dateKey = (date) => date.toISODate();
const datesBetween = (a, b) =>
  Math.round(day(b, "UTC").diff(day(a, "UTC"), "days").days);
const blankRecord = () => ({
  status: "pending",
  completedSteps: [],
  amount: 0,
  at: null,
});
export const balance = (state) =>
  state.ledger.reduce((sum, e) => sum + e.change, 0);

function isRequired(template, task) {
  const map = byId(template.tasks),
    seen = new Set();
  while (task) {
    if (!task.mandatory || seen.has(task.id)) return false;
    seen.add(task.id);
    if (task.parentId === null) return true;
    task = map.get(task.parentId);
  }
  return false;
}
function validateTime(t) {
  if (t.startMinute === null)
    rule(
      t.endMinute === undefined || t.endMinute === null,
      "Flexible activities cannot have an end time.",
    );
  else if (t.endMinute !== undefined)
    rule(
      t.endMinute !== null &&
        (t.overnight
          ? t.endMinute <= t.startMinute
          : t.endMinute > t.startMinute),
      "The activity time interval is invalid.",
    );
  if (t.reminder.enabled)
    rule(
      t.reminder.minute !== null || t.startMinute !== null,
      "An enabled reminder needs a time.",
    );
  if (t.target !== null)
    rule(t.unit.trim().length > 0, "A quantity target needs a unit.");
  if (t.recurrence === "weekdays" || t.recurrence === "weekly")
    rule(t.weekdays.length > 0, "Select at least one repeat day.");
  rule(
    new Set(t.dependencies).size === t.dependencies.length,
    "Duplicate prerequisites are invalid.",
  );
}
function validateTemplate(t) {
  rule(unique(t.tasks), "Task identifiers must be unique.");
  const map = byId(t.tasks);
  for (const node of t.tasks) {
    rule(
      node.dayOffsets.every((d) => d < t.durationDays),
      "A task falls outside its package duration.",
    );
    rule(
      node.parentId === null || map.get(node.parentId)?.type === "group",
      "A task parent must be a group.",
    );
    const seen = new Set([node.id]);
    let parent = node.parentId;
    while (parent !== null) {
      rule(!seen.has(parent), "Task groups cannot form cycles.");
      seen.add(parent);
      parent = map.get(parent)?.parentId ?? null;
    }
    rule(
      node.dependencies.every(
        (d) =>
          map.has(d) &&
          map.get(d).type !== "group" &&
          node.dayOffsets.every((o) => map.get(d).dayOffsets.includes(o)),
      ),
      "Invalid task prerequisites.",
    );
    if (node.type === "group") {
      const children = t.tasks.filter((c) => c.parentId === node.id);
      rule(
        children.length > 0 && children.some((c) => c.mandatory),
        "Groups need required children.",
      );
      rule(
        node.startMinute === null &&
          !node.reminder.enabled &&
          node.steps.length === 0 &&
          node.target === null &&
          node.dependencies.length === 0,
        "Groups cannot have leaf-task rules.",
      );
    } else {
      rule(
        (node.type === "scheduled") === (node.startMinute !== null),
        "The task type and schedule disagree.",
      );
      validateTime(node);
    }
  }
  rule(
    t.tasks.some((n) => n.type !== "group" && isRequired(t, n)),
    "A package needs required leaf tasks.",
  );
  const visited = new Set(),
    active = new Set();
  function visit(id) {
    if (visited.has(id)) return;
    rule(!active.has(id), "Task prerequisites cannot form cycles.");
    active.add(id);
    for (const dep of map.get(id).dependencies) visit(dep);
    active.delete(id);
    visited.add(id);
  }
  for (const id of map.keys()) visit(id);
}
function validateState(state, zone) {
  for (const list of [
    state.items,
    state.instances,
    state.templates,
    state.categories,
    state.achievements,
  ])
    rule(unique(list), "Duplicate identifiers are invalid.");
  rule(
    unique(state.selections, "targetDate"),
    "Daily assignments must be unique.",
  );
  rule(
    unique(state.ledger, "idempotencyKey") && unique(state.ledger),
    "XP event identifiers must be unique.",
  );
  rule(
    new Set(
      state.categories.map((category) => category.name.trim().toLowerCase()),
    ).size === state.categories.length,
    "Category names must be unique.",
    "history_conflict",
  );
  for (const template of state.templates)
    if (template.categoryId !== null)
      rule(
        state.categories.some(
          (category) => category.id === template.categoryId,
        ),
        "A package category reference is missing.",
        "history_conflict",
      );
  const validOccurrenceKey = (key) => {
    const split = key.lastIndexOf("@");
    const suffix = key.slice(split + 1);
    return (
      split > 0 &&
      /^\d{4}-\d{2}-\d{2}$/.test(suffix) &&
      day(suffix, "UTC").isValid &&
      dateKey(day(suffix, "UTC")) === suffix
    );
  };
  for (const [key, override] of Object.entries(state.overrides))
    rule(
      validOccurrenceKey(key) &&
        key.startsWith(`${override.id}@`) &&
        state.items.some((item) => item.id === override.id) &&
        override.recurrence === "once",
      "An occurrence override has an invalid original identifier.",
      "history_conflict",
    );
  for (const template of [
    ...state.templates,
    ...state.instances.map((i) => i.snapshot),
  ])
    validateTemplate(template);
  for (const item of [...state.items, ...Object.values(state.overrides)])
    validateTime(item);
  const routineMap = byId(state.items),
    visited = new Set(),
    active = new Set();
  function visitRoutine(id) {
    if (visited.has(id)) return;
    rule(!active.has(id), "Routine prerequisites cannot form cycles.");
    active.add(id);
    const item = routineMap.get(id);
    rule(
      item.dependencies.every((d) => routineMap.has(d)),
      "A routine prerequisite is missing.",
    );
    for (const d of item.dependencies) visitRoutine(d);
    active.delete(id);
    visited.add(id);
  }
  for (const id of routineMap.keys()) visitRoutine(id);
  for (const instance of state.instances) {
    rule(
      millis(instance.startedAt, zone) <= millis(instance.deadline, zone),
      "The package lifecycle is invalid.",
    );
    rule(
      instance.status === "active"
        ? instance.endedAt === null
        : instance.endedAt !== null,
      "The package end status is invalid.",
    );
    rule(
      millis(instance.deadline, zone) ===
        day(instance.startDate, zone)
          .plus({ days: instance.snapshot.durationDays })
          .toMillis(),
      "The saved package deadline does not match its captured duration.",
      "history_conflict",
    );
    for (const id of requiredAndOptionalIds(instance)) {
      const record = state.records[id];
      const taskId = id.slice(instance.id.length + 1, id.lastIndexOf("@"));
      const task = instance.snapshot.tasks.find((entry) => entry.id === taskId);
      rule(
        record && record.completedSteps.length <= task.steps.length,
        "A challenge task record is missing or inconsistent.",
        "history_conflict",
      );
    }
  }
  for (const selection of state.selections) {
    rule(
      !(selection.instanceId && selection.missedAt),
      "A daily selection cannot be selected and missed.",
      "history_conflict",
    );
    if (selection.instanceId)
      rule(
        state.instances.some(
          (instance) =>
            instance.id === selection.instanceId &&
            instance.startDate === selection.targetDate &&
            millis(instance.startedAt, zone) < millis(selection.deadline, zone),
        ),
        "A daily selection references an invalid commitment.",
        "history_conflict",
      );
    if (selection.missedAt)
      rule(
        millis(selection.missedAt, zone) === millis(selection.deadline, zone),
        "A missed selection timestamp does not match its frozen deadline.",
        "history_conflict",
      );
  }
  for (const [id, record] of Object.entries(state.records)) {
    rule(
      validOccurrenceKey(id),
      "A task occurrence has an invalid date identifier.",
      "history_conflict",
    );
    rule(
      new Set(record.completedSteps).size === record.completedSteps.length &&
        record.completedSteps.every((_, index) =>
          record.completedSteps.includes(index),
        ) &&
        (record.status === "pending" || record.at !== null),
      "Task completion steps or timestamp are inconsistent.",
      "history_conflict",
    );
  }
}

function migrate(candidate) {
  const state = clone(candidate);
  for (const t of state.templates) {
    if (state.schemaVersion < 3 && t.rewardMode === "legacyPerTask") {
      t.completionXp += t.tasks
        .filter((t) => t.type !== "group")
        .reduce((s, n) => s + n.rewardXp * new Set(n.dayOffsets).size, 0);
      t.rewardMode = "packageOnly";
    }
    if (state.schemaVersion < 4) t.skipPenalty ??= 0;
  }
  state.schemaVersion = 4;
  return state;
}
function routineOccurs(item, date) {
  const delta = datesBetween(item.date, date);
  if (delta < 0) return false;
  const weekday = day(date, "UTC").weekday;
  return item.recurrence === "once"
    ? delta === 0
    : item.recurrence === "daily"
      ? true
      : item.recurrence === "weekdays"
        ? item.weekdays.includes(weekday)
        : item.weekdays.includes(weekday) &&
          Math.floor(
            datesBetween(dateKey(day(item.date, "UTC").startOf("week")), date) /
              7,
          ) %
            item.everyWeeks ===
            0;
}
export function resolveOccurrence(state, id) {
  const split = id.lastIndexOf("@");
  rule(split > 0, "Invalid occurrence identifier.");
  const itemId = id.slice(0, split),
    date = id.slice(split + 1);
  rule(/^\d{4}-\d{2}-\d{2}$/.test(date), "Invalid occurrence date.");
  const slash = itemId.indexOf("/");
  if (slash >= 0) {
    const instance = state.instances.find(
      (i) => i.id === itemId.slice(0, slash),
    );
    const task = instance?.snapshot.tasks.find(
      (t) => t.id === itemId.slice(slash + 1),
    );
    rule(
      instance &&
        task &&
        task.type !== "group" &&
        task.dayOffsets.includes(datesBetween(instance.startDate, date)),
      "The challenge occurrence is not part of its captured package.",
    );
    return {
      instance,
      task,
      date,
      id,
      record: state.records[id] ?? blankRecord(),
    };
  }
  const overridden = state.overrides[id];
  const task = overridden ?? state.items.find((i) => i.id === itemId);
  rule(
    task &&
      (overridden || routineOccurs(task, date)) &&
      !state.exclusions.includes(id),
    "The routine occurrence does not exist.",
  );
  return {
    instance: null,
    task,
    // Moving one recurrence preserves its occurrence ID and record key, but
    // availability and prerequisites use the edited activity's actual day.
    date: overridden?.date ?? date,
    anchorDate: date,
    id,
    record: state.records[id] ?? blankRecord(),
  };
}
const requiredIds = (instance) =>
  instance.snapshot.tasks
    .filter((t) => t.type !== "group" && isRequired(instance.snapshot, t))
    .flatMap((t) =>
      [...new Set(t.dayOffsets)].map(
        (offset) =>
          `${instance.id}/${t.id}@${dateKey(day(instance.startDate, "UTC").plus({ days: offset }))}`,
      ),
    );
function dependenciesCompleted(state, occurrence) {
  for (const dependency of occurrence.task.dependencies) {
    const id = `${occurrence.instance ? `${occurrence.instance.id}/` : ""}${dependency}@${occurrence.date}`;
    const oneOff = occurrence.instance
      ? null
      : state.items.find(
          (item) => item.id === dependency && item.recurrence === "once",
        );
    rule(
      state.records[id]?.status === "completed" ||
        (oneOff &&
          state.records[`${dependency}@${oneOff.date}`]?.status ===
            "completed"),
      "Complete the prerequisite tasks first.",
    );
  }
}
function completeAllowed(state, occurrence, record) {
  rule(
    record.completedSteps.every((i) => i < occurrence.task.steps.length),
    "A step index does not exist.",
  );
  if (record.status === "completed") {
    rule(
      record.completedSteps.length === occurrence.task.steps.length &&
        (occurrence.task.target === null ||
          record.amount >= occurrence.task.target),
      "Complete the required steps and target first.",
    );
    dependenciesCompleted(state, occurrence);
  }
}
function actionTimestampAllowed(occurrence, record, now, zone) {
  rule(
    record.at !== null && millis(record.at, zone) <= now.toMillis() + 300000,
    "The task action timestamp is invalid.",
  );
  rule(
    dateKey(iso(record.at, zone).setZone(zone)) >= occurrence.date,
    "A task action cannot precede its scheduled day.",
  );
  if (occurrence.instance)
    rule(
      millis(record.at, zone) >= millis(occurrence.instance.startedAt, zone),
      "A task action cannot precede its commitment.",
    );
}
function ledgerRequest(state, key) {
  return state.ledger.find((e) => e.idempotencyKey === key);
}
function event(
  state,
  candidate,
  key,
  requested,
  type,
  related,
  at,
  reason,
  zone,
  { required = false, preserveAt = true } = {},
) {
  if (state.ledger.some((e) => e.idempotencyKey === key)) return;
  const supplied = ledgerRequest(candidate, key);
  if (required)
    rule(
      supplied,
      "The imported history is missing an XP event.",
      "history_conflict",
    );
  if (supplied) {
    rule(
      supplied.type === type && supplied.relatedId === related,
      "An XP event references the wrong action.",
      "history_conflict",
    );
    rule(
      millis(supplied.at, zone) <= millis(at, zone) + 300000,
      "An XP event is in the future.",
      "history_conflict",
    );
  }
  const actual = Math.max(-balance(state), requested) || 0;
  if (required)
    rule(
      supplied.change === actual,
      "An imported XP delta cannot be verified from the captured rule.",
      "history_conflict",
    );
  state.ledger.push({
    id: supplied?.id ?? randomUUID(),
    reason: supplied?.reason ?? reason,
    change: actual,
    type,
    at: supplied && preserveAt ? supplied.at : at,
    idempotencyKey: key,
    relatedId: related,
  });
}
function expectedLedgerRule(state, e, zone) {
  const key = e.idempotencyKey;
  if (key.startsWith("complete:") || key.startsWith("skip:")) {
    const occurrence = resolveOccurrence(
      state,
      key.slice(key.indexOf(":") + 1),
    );
    const skip = key.startsWith("skip:");
    rule(
      occurrence.record.status === (skip ? "skipped" : "completed"),
      "XP must correspond to a recorded action.",
      "history_conflict",
    );
    completeAllowed(state, occurrence, occurrence.record);
    rule(
      e.relatedId === occurrence.id &&
        e.type === (skip ? "task_skip" : "task_completion"),
      "An XP event has invalid provenance.",
      "history_conflict",
    );
    if (!occurrence.instance) {
      rule(!skip, "Routine skips do not have XP events.", "history_conflict");
      return occurrence.task.xp;
    }
    const snapshot = occurrence.instance.snapshot;
    if (skip) {
      rule(
        snapshot.rewardMode === "legacyPerTask" ||
          snapshot.skipPenalty !== null,
        "This captured package has no skip XP event.",
        "history_conflict",
      );
      return -(snapshot.rewardMode === "legacyPerTask"
        ? occurrence.task.skipPenalty
        : snapshot.skipPenalty);
    }
    rule(
      snapshot.rewardMode === "legacyPerTask",
      "Package-only tasks do not grant individual XP.",
      "history_conflict",
    );
    return occurrence.task.rewardXp;
  }
  if (key.startsWith("package:") || key.startsWith("failure:")) {
    const instance = state.instances.find(
      (i) => i.id === key.slice(key.indexOf(":") + 1),
    );
    const failed = key.startsWith("failure:");
    rule(
      instance &&
        e.relatedId === instance.id &&
        instance.status === (failed ? "failed" : "completed") &&
        e.type === (failed ? "challenge_failure" : "challenge_completion"),
      "Package XP must match its outcome.",
      "history_conflict",
    );
    if (failed)
      rule(
        millis(instance.endedAt, zone) >= millis(instance.deadline, zone),
        "The package did not reach its deadline.",
        "history_conflict",
      );
    else
      rule(
        requiredIds(instance).every(
          (id) => state.records[id]?.status === "completed",
        ) && millis(instance.endedAt, zone) < millis(instance.deadline, zone),
        "The package is incomplete.",
        "history_conflict",
      );
    return failed
      ? -instance.snapshot.failurePenalty
      : instance.snapshot.completionXp;
  }
  if (key.startsWith("missed_selection:")) {
    const selection = state.selections.find(
      (s) => s.targetDate === key.slice(17),
    );
    rule(
      selection &&
        !selection.instanceId &&
        selection.missedAt &&
        e.type === "missed_selection" &&
        e.relatedId === selection.targetDate &&
        millis(selection.missedAt, zone) >= millis(selection.deadline, zone),
      "The daily selection XP event is invalid.",
      "history_conflict",
    );
    return -selection.penalty;
  }
  invalid("Unknown XP event type.", "history_conflict");
}
function achievementEvidence(state, zone) {
  const evidence = new Map();
  const first = (values) => (values.length ? Math.min(...values) : null);
  const completed = Object.values(state.records).filter(
    (record) => record.status === "completed" && record.at !== null,
  );
  const firstTask = first(completed.map((record) => millis(record.at, zone)));
  if (firstTask !== null) evidence.set("first-task", firstTask);
  const packages = state.instances.filter(
    (instance) => instance.status === "completed",
  );
  const firstPackage = first(
    packages.map((instance) => millis(instance.endedAt, zone)),
  );
  if (firstPackage !== null) evidence.set("first-package", firstPackage);
  const firstHard = first(
    packages
      .filter((instance) => instance.snapshot.difficulty === "hard")
      .map((instance) => millis(instance.endedAt, zone)),
  );
  if (firstHard !== null) evidence.set("first-hard", firstHard);
  const days = new Map();
  for (const record of completed) {
    const date = dateKey(iso(record.at, zone).setZone(zone));
    days.set(
      date,
      Math.min(days.get(date) ?? Infinity, millis(record.at, zone)),
    );
  }
  let streak = 0,
    previous = null;
  for (const date of [...days.keys()].sort()) {
    streak = previous && datesBetween(previous, date) === 1 ? streak + 1 : 1;
    if (streak >= 7) {
      evidence.set("seven-days", days.get(date));
      break;
    }
    previous = date;
  }
  return evidence;
}
function importHistory(candidate, now, zone) {
  const state = clone(candidate),
    old = state.ledger;
  state.ledger = [];
  for (const e of old) {
    rule(
      millis(e.at, zone) <= now.toMillis() + 300000,
      "Imported history is in the future.",
      "history_conflict",
    );
    const requested = expectedLedgerRule(candidate, e, zone),
      actual = Math.max(-balance(state), requested) || 0;
    rule(
      e.change === actual,
      "Imported XP cannot be verified from its captured rules.",
      "history_conflict",
    );
    state.ledger.push(clone(e));
  }
  for (const [id, record] of Object.entries(state.records)) {
    if (record.status === "pending" && record.at === null) continue;
    const o = resolveOccurrence(state, id);
    completeAllowed(state, o, record);
    actionTimestampAllowed(o, record, now, zone);
    if (o.instance) {
      rule(
        record.status === "pending" ||
          millis(record.at, zone) < millis(o.instance.deadline, zone),
        "An imported action occurred after expiration.",
        "history_conflict",
      );
      if (
        record.status === "completed" &&
        o.instance.snapshot.rewardMode === "legacyPerTask"
      )
        rule(
          ledgerRequest(state, `complete:${id}`),
          "An imported task reward is missing.",
          "history_conflict",
        );
      if (
        record.status === "skipped" &&
        (o.instance.snapshot.rewardMode === "legacyPerTask" ||
          o.instance.snapshot.skipPenalty !== null)
      )
        rule(
          ledgerRequest(state, `skip:${id}`),
          "An imported skip event is missing.",
          "history_conflict",
        );
    }
  }
  for (const instance of state.instances) {
    rule(
      millis(instance.startedAt, zone) <= now.toMillis() + 300000,
      "Imported commitment timestamp is in the future.",
      "history_conflict",
    );
    if (instance.status !== "active") {
      rule(
        millis(instance.endedAt, zone) <= now.toMillis() + 300000 &&
          millis(instance.endedAt, zone) >= millis(instance.startedAt, zone),
        "Imported outcome timestamp is invalid.",
        "history_conflict",
      );
      rule(
        ledgerRequest(
          state,
          `${instance.status === "completed" ? "package" : "failure"}:${instance.id}`,
        ),
        "An imported package outcome is missing its ledger event.",
        "history_conflict",
      );
    }
  }
  for (const selection of state.selections)
    if (selection.missedAt)
      rule(
        ledgerRequest(state, `missed_selection:${selection.targetDate}`),
        "An imported missed deadline is missing its ledger event.",
        "history_conflict",
      );
  const evidence = achievementEvidence(state, zone);
  for (const achievement of state.achievements) {
    const earnedAt = evidence.get(achievement.id);
    rule(
      earnedAt !== undefined,
      "The imported achievement has no verified qualifying activity.",
      "history_conflict",
    );
    const unlockedAt = millis(achievement.unlockedAt, zone);
    rule(
      unlockedAt >= earnedAt && unlockedAt <= now.toMillis() + 300000,
      "The imported achievement timestamp cannot be verified.",
      "history_conflict",
    );
  }
  return state;
}
function selectionFor(state, date, zone) {
  const deadline = day(date, zone)
    .minus({ days: 1 })
    .set({
      hour: Math.floor(state.selectionDeadlineMinute / 60),
      minute: state.selectionDeadlineMinute % 60,
    });
  const existing = state.instances
    .filter((i) => i.startDate === date)
    .sort(
      (a, b) =>
        millis(a.startedAt, zone) - millis(b.startedAt, zone) ||
        a.id.localeCompare(b.id),
    )[0];
  return {
    targetDate: date,
    deadline:
      existing && millis(existing.startedAt, zone) >= deadline.toMillis()
        ? utc(iso(existing.startedAt, zone).plus({ milliseconds: 1 }))
        : utc(deadline),
    penalty: state.missedSelectionPenalty,
    instanceId: existing?.id ?? null,
    missedAt: null,
    acknowledged: false,
  };
}
function reconcile(state, candidate, now, zone) {
  const tomorrow = dateKey(now.setZone(zone).startOf("day").plus({ days: 1 }));
  if (!state.selections.length)
    state.selections.push(selectionFor(state, tomorrow, zone));
  else {
    let latest = [...state.selections]
      .sort((a, b) => a.targetDate.localeCompare(b.targetDate))
      .at(-1).targetDate;
    rule(
      datesBetween(latest, tomorrow) <= 36525,
      "The selection catch-up range is invalid.",
    );
    while (latest < tomorrow) {
      latest = dateKey(day(latest, "UTC").plus({ days: 1 }));
      state.selections.push(selectionFor(state, latest, zone));
    }
  }
  for (const s of state.selections)
    if (
      !s.instanceId &&
      !s.missedAt &&
      now.toMillis() >= millis(s.deadline, zone)
    ) {
      s.missedAt = s.deadline;
      event(
        state,
        candidate,
        `missed_selection:${s.targetDate}`,
        -s.penalty,
        "missed_selection",
        s.targetDate,
        utc(now),
        `Missed package selection for ${s.targetDate} (configured penalty: ${s.penalty} XP)`,
        zone,
      );
    }
  for (const instance of state.instances)
    if (instance.status === "active") {
      if (now.toMillis() >= millis(instance.deadline, zone)) {
        instance.status = "failed";
        instance.endedAt = instance.deadline;
        event(
          state,
          candidate,
          `failure:${instance.id}`,
          -instance.snapshot.failurePenalty,
          "challenge_failure",
          instance.id,
          utc(now),
          `Failed ${instance.snapshot.name} (configured penalty: ${instance.snapshot.failurePenalty} XP)`,
          zone,
        );
      } else if (
        requiredIds(instance).every(
          (id) => state.records[id]?.status === "completed",
        )
      ) {
        instance.status = "completed";
        instance.endedAt =
          candidate.instances.find((i) => i.id === instance.id)?.endedAt ??
          utc(now);
        rule(
          millis(instance.endedAt, zone) <= now.toMillis() + 300000 &&
            millis(instance.endedAt, zone) < millis(instance.deadline, zone),
          "Invalid package completion timestamp.",
        );
        event(
          state,
          candidate,
          `package:${instance.id}`,
          instance.snapshot.completionXp,
          "challenge_completion",
          instance.id,
          utc(now),
          `Completed ${instance.snapshot.name}`,
          zone,
        );
      }
    }
  const evidence = achievementEvidence(state, zone);
  const unlock = (id, title, condition) => {
    if (condition && !state.achievements.some((a) => a.id === id)) {
      const supplied = candidate.achievements.find((a) => a.id === id);
      state.achievements.push({
        id,
        title,
        unlockedAt:
          supplied &&
          millis(supplied.unlockedAt, zone) >= evidence.get(id) &&
          millis(supplied.unlockedAt, zone) <= now.toMillis() + 300000
            ? supplied.unlockedAt
            : utc(now),
      });
    }
  };
  unlock(
    "first-task",
    "First task completed",
    Object.values(state.records).some((r) => r.status === "completed"),
  );
  unlock(
    "first-package",
    "First package completed",
    state.instances.some((i) => i.status === "completed"),
  );
  unlock(
    "first-hard",
    "First hard package completed",
    state.instances.some(
      (i) => i.status === "completed" && i.snapshot.difficulty === "hard",
    ),
  );
  const days = [
    ...new Set(
      Object.values(state.records)
        .filter((r) => r.status === "completed" && r.at)
        .map((r) => dateKey(iso(r.at, zone).setZone(zone))),
    ),
  ].sort();
  let streak = 0,
    best = 0,
    last = null;
  for (const d of days) {
    streak = last && datesBetween(last, d) === 1 ? streak + 1 : 1;
    best = Math.max(best, streak);
    last = d;
  }
  unlock("seven-days", "Seven days of qualifying activity", best >= 7);
  state.lastObservedAt = utc(now);
}

export function transition(
  previous,
  proposal,
  { now = new Date(), timeZone = "UTC" } = {},
) {
  const at = DateTime.fromJSDate(now, { zone: "UTC" }),
    candidate = migrate(proposal);
  validateState(candidate, timeZone);
  if (previous === null) {
    const state = importHistory(candidate, at, timeZone);
    reconcile(state, candidate, at, timeZone);
    return state;
  }
  const old = migrate(previous),
    state = clone(old);
  // A stale proposal cannot erase any accepted event. Conflicts retain the
  // caller's durable draft and require an explicit reconciliation choice.
  for (const entry of old.ledger)
    rule(
      candidate.ledger.some((e) => equal(e, entry)),
      "The proposal omits or alters accepted XP history.",
      "history_conflict",
    );
  for (const entry of old.achievements)
    rule(
      candidate.achievements.some((e) => equal(e, entry)),
      "Accepted achievements cannot be changed.",
      "history_conflict",
    );
  for (const instance of old.instances) {
    const proposed = candidate.instances.find((i) => i.id === instance.id);
    rule(
      proposed &&
        equal(proposed.snapshot, instance.snapshot) &&
        proposed.startedAt === instance.startedAt &&
        proposed.startDate === instance.startDate &&
        proposed.deadline === instance.deadline,
      "Active and historical package snapshots are immutable.",
      "history_conflict",
    );
    if (instance.status !== "active")
      rule(
        equal(proposed, instance),
        "A historical package cannot be changed.",
        "history_conflict",
      );
  }
  state.items = clone(candidate.items);
  state.overrides = clone(candidate.overrides);
  state.exclusions = clone(candidate.exclusions);
  state.templates = clone(candidate.templates);
  state.categories = clone(candidate.categories);
  state.reminders = clone(candidate.reminders);
  state.templatesInitialized = candidate.templatesInitialized;
  state.selectionDeadlineMinute = candidate.selectionDeadlineMinute;
  state.missedSelectionPenalty = candidate.missedSelectionPenalty;
  for (const template of state.templates) {
    rule(
      template.rewardMode === "packageOnly" && template.skipPenalty !== null,
      "Editable packages must use package-level rules.",
    );
    if (template.categoryId !== null)
      rule(
        state.categories.some(
          (c) =>
            c.id === template.categoryId && c.name === template.categoryName,
        ),
        "Package category is invalid.",
      );
  }
  const tomorrow = dateKey(at.setZone(timeZone).plus({ days: 1 }));
  // Apply only still-open rule changes before deadline reconciliation.
  for (let i = 0; i < state.selections.length; i++) {
    const s = state.selections[i],
      proposed = candidate.selections.find(
        (p) => p.targetDate === s.targetDate,
      );
    rule(
      proposed,
      "Daily-selection history cannot be removed.",
      "history_conflict",
    );
    if (s.instanceId || s.missedAt)
      rule(
        equal(proposed, s) ||
          equal({ ...proposed, acknowledged: s.acknowledged }, s),
        "Closed selection rules cannot be changed.",
        "history_conflict",
      );
    else if (
      s.targetDate === tomorrow &&
      at.toMillis() < millis(s.deadline, timeZone) &&
      (old.selectionDeadlineMinute !== state.selectionDeadlineMinute ||
        old.missedSelectionPenalty !== state.missedSelectionPenalty)
    )
      state.selections[i] = selectionFor(state, s.targetDate, timeZone);
    if (s.missedAt && proposed.acknowledged)
      state.selections[i].acknowledged = true;
  }
  reconcile(state, candidate, at, timeZone);
  for (const proposed of candidate.instances)
    if (!old.instances.some((i) => i.id === proposed.id)) {
      rule(
        proposed.startDate === tomorrow,
        "New commitments must be selected for tomorrow.",
      );
      const selection = state.selections.find((s) => s.targetDate === tomorrow);
      rule(
        selection &&
          !selection.instanceId &&
          !selection.missedAt &&
          at.toMillis() < millis(selection.deadline, timeZone),
        "The daily selection deadline has passed.",
        "deadline_passed",
      );
      const template = state.templates.find(
        (t) => t.id === proposed.snapshot.id,
      );
      rule(
        template && equal(template, proposed.snapshot),
        "A new instance must snapshot the current saved template.",
      );
      rule(
        template.prerequisiteTemplateIds.every((id) =>
          state.instances.some(
            (i) => i.snapshot.id === id && i.status === "completed",
          ),
        ),
        "Complete prerequisite packages first.",
      );
      const expected = day(tomorrow, timeZone).plus({
        days: template.durationDays,
      });
      rule(
        millis(proposed.deadline, timeZone) === expected.toMillis(),
        "The instance deadline does not match its duration.",
      );
      rule(
        millis(proposed.startedAt, timeZone) <= at.toMillis() + 300000 &&
          millis(proposed.startedAt, timeZone) >=
            at.setZone(timeZone).startOf("day").toMillis(),
        "The commitment timestamp is stale.",
        "deadline_passed",
      );
      const instance = {
        ...clone(proposed),
        snapshot: clone(template),
        status: "active",
        endedAt: null,
      };
      state.instances.push(instance);
      selection.instanceId = instance.id;
      for (const id of requiredAndOptionalIds(instance))
        state.records[id] = blankRecord();
    }
  const newActions = [];
  for (const [id, record] of Object.entries(candidate.records)) {
    const prior = old.records[id] ?? blankRecord();
    if (equal(prior, record)) continue;
    rule(
      prior.status === "pending",
      "Completed and skipped records cannot be changed.",
      "history_conflict",
    );
    const occurrence = resolveOccurrence(state, id);
    rule(
      occurrence.date <= dateKey(at.setZone(timeZone)),
      "Future tasks cannot be completed or skipped.",
    );
    if (occurrence.instance)
      rule(
        occurrence.instance.status === "active" &&
          at.toMillis() < millis(occurrence.instance.deadline, timeZone),
        "The package deadline has passed.",
        "deadline_passed",
      );
    rule(
      prior.completedSteps.every((s) => record.completedSteps.includes(s)),
      "Completed steps cannot be removed.",
      "history_conflict",
    );
    actionTimestampAllowed(occurrence, record, at, timeZone);
    completeAllowed(state, occurrence, record);
    state.records[id] = clone(record);
    if (record.status !== "pending") newActions.push({ ...occurrence, record });
  }
  for (const [id, record] of Object.entries(old.records))
    if (record.status !== "pending")
      rule(
        equal(candidate.records[id], record),
        "Action history cannot be removed or changed.",
        "history_conflict",
      );
  newActions.sort((a, b) => {
    const ka = `${a.record.status === "skipped" ? "skip" : "complete"}:${a.id}`,
      kb = `${b.record.status === "skipped" ? "skip" : "complete"}:${b.id}`;
    return (
      candidate.ledger.findIndex((e) => e.idempotencyKey === ka) -
      candidate.ledger.findIndex((e) => e.idempotencyKey === kb)
    );
  });
  for (const o of newActions)
    if (o.instance) {
      const snapshot = o.instance.snapshot,
        skip = o.record.status === "skipped";
      if (
        skip &&
        (snapshot.rewardMode === "legacyPerTask" ||
          snapshot.skipPenalty !== null)
      )
        event(
          state,
          candidate,
          `skip:${o.id}`,
          -(snapshot.rewardMode === "legacyPerTask"
            ? o.task.skipPenalty
            : snapshot.skipPenalty),
          "task_skip",
          o.id,
          utc(at),
          `Skipped ${o.task.title}`,
          timeZone,
        );
      else if (!skip && snapshot.rewardMode === "legacyPerTask")
        event(
          state,
          candidate,
          `complete:${o.id}`,
          o.task.rewardXp,
          "task_completion",
          o.id,
          utc(at),
          `Completed ${o.task.title}`,
          timeZone,
        );
    }
  reconcile(state, candidate, at, timeZone);
  // Extra client ledger entries are never copied into authoritative storage.
  rule(
    candidate.ledger.every((e) =>
      state.ledger.some((s) => s.idempotencyKey === e.idempotencyKey),
    ),
    "An XP event has no verified underlying action.",
    "history_conflict",
  );
  return state;
}
function requiredAndOptionalIds(instance) {
  return instance.snapshot.tasks
    .filter((t) => t.type !== "group")
    .flatMap((t) =>
      [...new Set(t.dayOffsets)].map(
        (offset) =>
          `${instance.id}/${t.id}@${dateKey(day(instance.startDate, "UTC").plus({ days: offset }))}`,
      ),
    );
}
