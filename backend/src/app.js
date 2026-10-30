// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import express from "express";
import helmet from "helmet";
import cors from "cors";
import { rateLimit } from "express-rate-limit";
import { createHash } from "node:crypto";
import { AuthService } from "./auth.js";
import { ApiError } from "./errors.js";
import { syncSchema, parse } from "./schema.js";

const canonical = (value) =>
  Array.isArray(value)
    ? value.map(canonical)
    : value && typeof value === "object"
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((key) => [key, canonical(value[key])]),
        )
      : value;

export function createApp({ store, config, hashCost = 12, authLimit = 20 }) {
  const app = express(),
    auth = new AuthService(store, config, { hashCost });
  app.disable("x-powered-by");
  app.set("trust proxy", config.TRUST_PROXY_HOPS);
  app.use(helmet());
  app.use((req, res, next) => {
    res.set("Cache-Control", "no-store");
    next();
  });
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || config.origins.includes(origin)) callback(null, true);
        else
          callback(
            new ApiError(
              403,
              "origin_not_allowed",
              "This origin is not permitted.",
            ),
          );
      },
      credentials: false,
      methods: ["GET", "POST"],
      allowedHeaders: ["Content-Type", "Authorization"],
    }),
  );
  // Render probes the process over its private HTTP network. Only this exact
  // read-only readiness route precedes HTTPS enforcement; API routes do not.
  app.get(/^\/health$/, async (req, res) => {
    let timer;
    try {
      await Promise.race([
        store.db.command({ ping: 1 }, { maxTimeMS: 2000, timeoutMS: 3000 }),
        new Promise((_, reject) => {
          timer = setTimeout(
            () =>
              reject(
                new ApiError(
                  503,
                  "service_unavailable",
                  "The service is temporarily unavailable.",
                ),
              ),
            3000,
          );
        }),
      ]);
      res.json({ status: "ok" });
    } finally {
      clearTimeout(timer);
    }
  });
  app.use((req, res, next) => {
    if (config.NODE_ENV === "production" && !req.secure)
      return next(
        new ApiError(
          426,
          "https_required",
          "Use HTTPS to access this service.",
        ),
      );
    next();
  });
  app.use(express.json({ limit: "2mb", strict: true }));
  const limitMessage = {
    error: {
      code: "rate_limited",
      message: "Too many requests. Try again later.",
    },
  };
  app.use(
    "/api/v1",
    rateLimit({
      windowMs: 60000,
      limit: 120,
      standardHeaders: "draft-8",
      legacyHeaders: false,
      message: limitMessage,
    }),
  );
  const authenticationLimit = rateLimit({
    windowMs: 15 * 60000,
    limit: authLimit,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: limitMessage,
  });
  app.post("/api/v1/auth/register", authenticationLimit, async (req, res) =>
    res.status(201).json(await auth.register(req.body)),
  );
  app.post("/api/v1/auth/login", authenticationLimit, async (req, res) =>
    res.json(await auth.login(req.body)),
  );
  app.post("/api/v1/auth/refresh", authenticationLimit, async (req, res) =>
    res.json(await auth.refresh(req.body)),
  );
  app.post("/api/v1/auth/logout", async (req, res) => {
    await auth.logout(req.body);
    res.status(204).end();
  });
  app.use("/api/v1", async (req, res, next) => {
    req.ownerId = await auth.verify(req.get("Authorization"));
    next();
  });
  app.get("/api/v1/state", async (req, res) =>
    res.json(await store.get(req.ownerId)),
  );
  app.post("/api/v1/sync", async (req, res) => {
    const input = parse(syncSchema, req.body);
    // Android's native JSON maps can reorder keys after a process restart.
    // Idempotency binds semantic JSON values, never map iteration order.
    const requestHash = createHash("sha256")
      .update(JSON.stringify(canonical(req.body)))
      .digest("hex");
    res.json(await store.sync(req.ownerId, { ...input, requestHash }));
  });
  app.use((req, res) =>
    res.status(404).json({
      error: { code: "not_found", message: "This endpoint does not exist." },
    }),
  );
  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);
    if (error instanceof ApiError)
      return res.status(error.status).json({
        error: { code: error.code, message: error.message },
        ...error.extra,
      });
    if (error.type === "entity.too.large")
      return res.status(413).json({
        error: {
          code: "validation_failed",
          message: "The request exceeds the allowed size.",
        },
      });
    if (error instanceof SyntaxError && error.status === 400)
      return res.status(400).json({
        error: {
          code: "validation_failed",
          message: "The request body must be valid JSON.",
        },
      });
    // Do not log request bodies, password hashes, tokens, Mongo URIs or personal
    // records. Operational logging can include only this stable category.
    console.error("API request failed:", error.name ?? "Error");
    res.status(503).json({
      error: {
        code: "service_unavailable",
        message:
          "The service is temporarily unavailable. Your changes have not been confirmed.",
      },
    });
  });
  return app;
}
