export const reminder = {
  enabled: false,
  minute: null,
  offsetMinutes: 0,
  sound: "default",
  vibrate: true,
};
export const pending = () => ({
  status: "pending",
  completedSteps: [],
  amount: 0,
  at: null,
});
export function task(id = "leaf", extra = {}) {
  return {
    id,
    title: id,
    description: "",
    dayOffsets: [0],
    type: "flexible",
    parentId: null,
    startMinute: null,
    durationMinutes: 30,
    steps: [],
    dependencies: [],
    target: null,
    unit: "",
    rewardXp: 0,
    skipPenalty: 0,
    mandatory: true,
    reminder: { ...reminder },
    ...extra,
  };
}
export function template(extra = {}) {
  return {
    id: "package",
    name: "Morning Routine",
    description: "",
    difficulty: null,
    durationDays: 1,
    tasks: [task()],
    completionXp: 80,
    failurePenalty: 5,
    skipPenalty: 4,
    prerequisiteTemplateIds: [],
    rewardMode: "packageOnly",
    categoryId: null,
    categoryName: "",
    createdAt: null,
    updatedAt: null,
    ...extra,
  };
}
export function routine(extra = {}) {
  return {
    id: "routine",
    title: "Read",
    description: "",
    category: "Personal",
    date: "2026-10-29",
    startMinute: null,
    endMinute: null,
    overnight: false,
    recurrence: "daily",
    weekdays: [],
    everyWeeks: 1,
    steps: [],
    dependencies: [],
    target: null,
    unit: "",
    xp: 10,
    reminder: { ...reminder },
    ...extra,
  };
}
export function empty(extra = {}) {
  return {
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
    templatesInitialized: true,
    categories: [],
    selections: [],
    selectionDeadlineMinute: 1439,
    missedSelectionPenalty: 5,
    lastObservedAt: null,
    ...extra,
  };
}
export function instance(snapshot = template(), extra = {}) {
  return {
    id: "instance",
    snapshot,
    startedAt: "2026-10-28T15:00:00.000Z",
    startDate: "2026-10-29",
    deadline: "2026-10-30T00:00:00.000Z",
    status: "active",
    endedAt: null,
    ...extra,
  };
}
export function ledger(key, change, type, relatedId, extra = {}) {
  return {
    id: `event-${key}`,
    reason: "Recorded action",
    change,
    type,
    at: "2026-10-29T10:00:00.000Z",
    idempotencyKey: key,
    relatedId,
    ...extra,
  };
}
