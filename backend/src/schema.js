import { z } from "zod";
import { DateTime } from "luxon";
import { ApiError } from "./errors.js";

const id = z
  .string()
  .min(1)
  .max(240)
  .refine((s) => !/[\0$]/.test(s));
const nodeId = id.refine((s) => !s.includes("/") && !s.includes("@"));
const title = z.string().trim().min(1).max(200);
const text = z.string().max(4000).default("");
const xp = z.number().int().min(0).max(1_000_000);
const minute = z.number().int().min(0).max(1439);
const date = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((s) => DateTime.fromISO(s).isValid);
const instant = z
  .string()
  .min(10)
  .max(40)
  .refine((s) => DateTime.fromISO(s).isValid);
const reminder = z
  .object({
    enabled: z.boolean().default(false),
    minute: minute.nullable().default(null),
    offsetMinutes: z.number().int().min(0).max(10080).default(0),
    sound: z.string().max(100).default("default"),
    vibrate: z.boolean().default(true),
  })
  .strict();
const rule = {
  id: nodeId,
  title,
  description: text,
  startMinute: minute.nullable().default(null),
  steps: z.array(z.string().trim().min(1).max(500)).max(100).default([]),
  dependencies: z.array(nodeId).max(200).default([]),
  target: z.number().finite().positive().max(1e12).nullable().default(null),
  unit: z.string().max(100).default(""),
  reminder: reminder.default({}),
};
export const routineSchema = z
  .object({
    ...rule,
    date,
    category: z.string().max(200).default("Personal"),
    endMinute: minute.nullable().default(null),
    overnight: z.boolean().default(false),
    recurrence: z.enum(["once", "daily", "weekdays", "weekly"]).default("once"),
    weekdays: z.array(z.number().int().min(1).max(7)).max(7).default([]),
    everyWeeks: z.number().int().min(1).max(52).default(1),
    xp: xp.default(10),
  })
  .strict();
export const taskSchema = z
  .object({
    ...rule,
    dayOffsets: z
      .array(z.number().int().min(0).max(365))
      .min(1)
      .max(366)
      .default([0]),
    type: z.enum(["flexible", "scheduled", "group"]).optional(),
    parentId: nodeId.nullable().default(null),
    durationMinutes: z.number().int().min(1).max(1440).default(30),
    rewardXp: xp.default(10),
    skipPenalty: xp.default(5),
    mandatory: z.boolean().default(true),
  })
  .strict()
  .transform((t) => ({
    ...t,
    type: t.type ?? (t.startMinute === null ? "flexible" : "scheduled"),
  }));
export const templateSchema = z
  .object({
    id: nodeId,
    name: title,
    description: text,
    difficulty: z.enum(["easy", "medium", "hard"]).nullable().default(null),
    durationDays: z.number().int().min(1).max(366).default(1),
    tasks: z.array(taskSchema).min(1).max(1000),
    completionXp: xp,
    failurePenalty: xp.default(0),
    skipPenalty: xp.nullable().default(null),
    prerequisiteTemplateIds: z.array(nodeId).max(200).default([]),
    rewardMode: z
      .enum(["legacyPerTask", "packageOnly"])
      .default("legacyPerTask"),
    categoryId: nodeId.nullable().default(null),
    categoryName: z.string().max(200).default(""),
    createdAt: instant.nullable().default(null),
    updatedAt: instant.nullable().default(null),
  })
  .strict();
const record = z
  .object({
    status: z.enum(["pending", "completed", "skipped"]).default("pending"),
    completedSteps: z
      .array(z.number().int().min(0).max(99))
      .max(100)
      .default([]),
    amount: z.number().finite().min(0).max(1e12).default(0),
    at: instant.nullable().default(null),
  })
  .strict();
const instance = z
  .object({
    id: nodeId,
    snapshot: templateSchema,
    startedAt: instant,
    startDate: date,
    deadline: instant,
    status: z.enum(["active", "completed", "failed"]),
    endedAt: instant.nullable().default(null),
  })
  .strict();
const selection = z
  .object({
    targetDate: date,
    deadline: instant,
    penalty: xp,
    instanceId: nodeId.nullable().default(null),
    missedAt: instant.nullable().default(null),
    acknowledged: z.boolean().default(false),
  })
  .strict();
const ledger = z
  .object({
    id,
    reason: z.string().max(1000),
    change: z.number().int().min(-1e12).max(1e12),
    type: z.enum([
      "task_completion",
      "task_skip",
      "challenge_completion",
      "challenge_failure",
      "missed_selection",
    ]),
    at: instant,
    idempotencyKey: id,
    relatedId: id.nullable().default(null),
  })
  .strict();
export const stateSchema = z
  .object({
    schemaVersion: z.number().int().min(1).max(4),
    items: z.array(routineSchema).max(5000).default([]),
    overrides: z.record(id, routineSchema).default({}),
    exclusions: z.array(id).max(20000).default([]),
    records: z.record(id, record).default({}),
    instances: z.array(instance).max(5000).default([]),
    ledger: z.array(ledger).max(30000).default([]),
    achievements: z
      .array(z.object({ id: nodeId, title, unlockedAt: instant }).strict())
      .max(100)
      .default([]),
    reminders: z.record(id, reminder).default({}),
    templates: z.array(templateSchema).max(1000).default([]),
    templatesInitialized: z.boolean().default(false),
    categories: z
      .array(z.object({ id: nodeId, name: title }).strict())
      .max(1000)
      .default([]),
    selections: z.array(selection).max(20000).default([]),
    selectionDeadlineMinute: minute.default(1439),
    missedSelectionPenalty: xp.default(5),
    lastObservedAt: instant.nullable().default(null),
  })
  .strict();
export const syncSchema = z
  .object({
    mutationId: z
      .string()
      .min(1)
      .max(128)
      .regex(/^[a-zA-Z0-9_-]+$/),
    baseRevision: z.number().int().min(0),
    state: stateSchema,
    settings: z
      .object({ locale: z.enum(["en", "ar"]).default("en") })
      .strict()
      .default({ locale: "en" }),
    timeZone: z
      .string()
      .min(1)
      .max(100)
      .refine((s) => {
        try {
          new Intl.DateTimeFormat("en", { timeZone: s });
          return true;
        } catch {
          return false;
        }
      }),
  })
  .strict();

export function parse(schema, body) {
  const result = schema.safeParse(body);
  if (!result.success)
    throw new ApiError(
      422,
      "validation_failed",
      "The request contains invalid or unsupported fields.",
    );
  return result.data;
}
