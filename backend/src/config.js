import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  HOST: z.string().min(1).optional(),
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
  // This is the *web* OAuth client ID. It is an identifier rather than a
  // secret, but keeping the server's accepted audience in the environment
  // makes it impossible to accidentally accept tokens meant for another app.
  GOOGLE_OAUTH_WEB_CLIENT_ID: z.string().trim().refine(
    (value) => !value || /^[A-Za-z0-9][A-Za-z0-9._-]*\.apps\.googleusercontent\.com$/.test(value),
    "Use the Web OAuth client ID.",
  ).default(""),
  // Password recovery is deliberately disabled until a real sender is
  // configured. These values never go to Flutter.
  RESEND_API_KEY: z.string().trim().default(""),
  EMAIL_FROM: z.string().trim().default(""),
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(0),
  CORS_ORIGINS: z.string().default(""),
});

export function loadConfig(env = process.env) {
  // Render terminates TLS before proxying the request to this process. Its
  // environment marker makes the one-hop trust explicit for services created
  // without our Blueprint, while an explicit TRUST_PROXY_HOPS always wins.
  const parsed = envSchema.safeParse({
    ...env,
    TRUST_PROXY_HOPS:
      env.TRUST_PROXY_HOPS ?? (env.RENDER === "true" ? "1" : undefined),
  });
  if (!parsed.success)
    throw new Error(
      `Invalid server configuration: ${parsed.error.issues.map((i) => i.path.join(".")).join(", ")}`,
    );
  const value = parsed.data;
  if (Boolean(value.RESEND_API_KEY) !== Boolean(value.EMAIL_FROM))
    throw new Error("Configure RESEND_API_KEY and EMAIL_FROM together.");
  if (/[\r\n]/.test(value.EMAIL_FROM))
    throw new Error("EMAIL_FROM must contain a single sender address.");
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
  return {
    ...value,
    HOST:
      value.HOST ?? (value.NODE_ENV === "production" ? "0.0.0.0" : "127.0.0.1"),
    origins,
  };
}
