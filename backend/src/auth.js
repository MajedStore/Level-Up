// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import { randomBytes, randomUUID, createHash } from "node:crypto";
import bcrypt from "bcryptjs";
import { SignJWT, jwtVerify } from "jose";
import { ApiError } from "./errors.js";

const hashToken = (value) => createHash("sha256").update(value).digest("hex");
export class AuthService {
  constructor(store, config, { hashCost = 12 } = {}) {
    this.store = store;
    this.config = config;
    this.hashCost = hashCost;
    this.key = new TextEncoder().encode(config.JWT_SECRET);
    this.dummyHash = bcrypt.hashSync(
      "not-a-real-password-for-timing",
      hashCost,
    );
  }
  credentials(body) {
    if (
      !body ||
      typeof body !== "object" ||
      Array.isArray(body) ||
      Object.keys(body).some((k) => !["email", "password"].includes(k))
    )
      throw new ApiError(
        422,
        "validation_failed",
        "Email and password are required.",
      );
    const email =
      typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new ApiError(422, "invalid_email", "Enter a valid email address.");
    if (
      typeof body.password !== "string" ||
      body.password.length < 12 ||
      Buffer.byteLength(body.password, "utf8") > 72
    )
      throw new ApiError(
        422,
        "weak_password",
        "Use at least 12 characters and no more than 72 UTF-8 bytes.",
      );
    return { email, password: body.password };
  }
  async register(body) {
    const { email, password } = this.credentials(body),
      passwordHash = await bcrypt.hash(password, this.hashCost);
    const user = {
      _id: randomUUID(),
      email,
      passwordHash,
      createdAt: this.store.clock(),
    };
    try {
      return await this.store.transaction(async (session) => {
        await this.store.db.collection("users").insertOne(user, { session });
        return this.issue(user, session);
      });
    } catch (error) {
      if (error.code === 11000)
        throw new ApiError(
          409,
          "email_exists",
          "An account with that email already exists.",
        );
      throw error;
    }
  }
  async login(body) {
    const { email, password } = this.credentials(body),
      user = await this.store.db.collection("users").findOne({ email });
    const valid = await bcrypt.compare(
      password,
      user?.passwordHash ?? this.dummyHash,
    );
    if (!valid || !user)
      throw new ApiError(
        401,
        "invalid_credentials",
        "Email or password is incorrect.",
      );
    return this.store.transaction((session) => this.issue(user, session));
  }
  async issue(user, session) {
    const now = this.store.clock(),
      sid = randomUUID(),
      refreshToken = randomBytes(48).toString("base64url");
    await this.store.db
      .collection("sessions")
      .insertOne(
        {
          _id: sid,
          ownerId: user._id,
          tokenHash: hashToken(refreshToken),
          createdAt: now,
          expiresAt: new Date(
            now.getTime() + this.config.REFRESH_TOKEN_DAYS * 86400000,
          ),
          revokedAt: null,
        },
        { session },
      );
    const accessToken = await new SignJWT({ sid })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" })
      .setSubject(user._id)
      .setIssuer(this.config.JWT_ISSUER)
      .setAudience(this.config.JWT_AUDIENCE)
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(
        Math.floor(now.getTime() / 1000) + this.config.ACCESS_TOKEN_SECONDS,
      )
      .sign(this.key);
    return {
      user: { id: user._id, email: user.email },
      accessToken,
      refreshToken,
      expiresIn: this.config.ACCESS_TOKEN_SECONDS,
    };
  }
  refreshBody(body) {
    if (
      !body ||
      typeof body.refreshToken !== "string" ||
      body.refreshToken.length < 32 ||
      body.refreshToken.length > 256 ||
      Object.keys(body).some((k) => k !== "refreshToken")
    )
      throw new ApiError(
        422,
        "validation_failed",
        "A refresh token is required.",
      );
    return body.refreshToken;
  }
  async refresh(body) {
    const token = this.refreshBody(body);
    return this.store.transaction(async (session) => {
      const previous = await this.store.db
        .collection("sessions")
        .findOneAndUpdate(
          {
            tokenHash: hashToken(token),
            revokedAt: null,
            expiresAt: { $gt: this.store.clock() },
          },
          { $set: { revokedAt: this.store.clock() } },
          { session, returnDocument: "before" },
        );
      if (!previous)
        throw new ApiError(
          401,
          "session_expired",
          "Sign in again to continue.",
        );
      const user = await this.store.db
        .collection("users")
        .findOne({ _id: previous.ownerId }, { session });
      if (!user)
        throw new ApiError(
          401,
          "session_expired",
          "Sign in again to continue.",
        );
      return this.issue(user, session);
    });
  }
  async logout(body) {
    const token = this.refreshBody(body);
    await this.store.db
      .collection("sessions")
      .updateOne(
        { tokenHash: hashToken(token) },
        { $set: { revokedAt: this.store.clock() } },
      );
  }
  async verify(header) {
    if (typeof header !== "string" || !header.startsWith("Bearer "))
      throw new ApiError(401, "unauthorized", "Sign in to access your data.");
    try {
      const { payload } = await jwtVerify(header.slice(7), this.key, {
        algorithms: ["HS256"],
        issuer: this.config.JWT_ISSUER,
        audience: this.config.JWT_AUDIENCE,
        currentDate: this.store.clock(),
      });
      if (typeof payload.sub !== "string" || typeof payload.sid !== "string")
        throw new Error();
      const session = await this.store.db
        .collection("sessions")
        .findOne({
          _id: payload.sid,
          ownerId: payload.sub,
          revokedAt: null,
          expiresAt: { $gt: this.store.clock() },
        });
      if (!session) throw new Error();
      return payload.sub;
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError(
        401,
        "unauthorized",
        "Your session has expired. Sign in again.",
      );
    }
  }
}
