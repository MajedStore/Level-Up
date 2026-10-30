import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  MONGODB_URI: z.string().min(1),
  MONGODB_DATABASE: z
    .string()
    .regex(/^[a-zA-Z0-9_-]{1,64}$/)
    .default("level_up"),
  JWT_SECRET: z
    .string()
    .min(32)
    .refine((v) => !v.startsWith("replace-"), "Generate a random JWT key."),
  JWT_ISSUER: z.string().default("level-up-api"),
  JWT_AUDIENCE: z.string().default("level-up-android"),
  ACCESS_TOKEN_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  REFRESH_TOKEN_DAYS: z.coerce.number().int().min(1).max(90).default(30),
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(0),
  CORS_ORIGINS: z.string().default(""),
});

export function loadConfig(env = process.env) {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success)
    throw new Error(
      `Invalid server configuration: ${parsed.error.issues.map((i) => i.path.join(".")).join(", ")}`,
    );
  const value = parsed.data;
  const origins = value.CORS_ORIGINS.split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (origins.includes("*"))
    throw new Error("CORS_ORIGINS must contain explicit origins.");
  if (
    value.NODE_ENV === "production" &&
    origins.some((s) => !s.startsWith("https://"))
  ) {
    throw new Error("Production browser origins must use HTTPS.");
  }
  return { ...value, origins };
}
