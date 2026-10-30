// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import { randomBytes, randomUUID, createHash } from "node:crypto";
import bcrypt from "bcryptjs";
import { OAuth2Client } from "google-auth-library";
import { SignJWT, jwtVerify } from "jose";
import { ApiError } from "./errors.js";

const hashToken = (value) => createHash("sha256").update(value).digest("hex");

const normalizeEmail = (value) =>
  typeof value === "string" ? value.trim().toLowerCase() : "";

const validEmail = (value) =>
  value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

const allowedKeys = (body, keys) =>
  body &&
  typeof body === "object" &&
  !Array.isArray(body) &&
  Object.keys(body).every((key) => keys.includes(key));

export class GoogleIdentityVerifier {
  constructor(audience, { client = new OAuth2Client() } = {}) {
    this.audience = audience;
    this.client = client;
  }

  async verify(idToken) {
    if (typeof idToken !== "string" || idToken.length < 20 || idToken.length > 12000)
      throw new ApiError(422, "validation_failed", "A Google ID token is required.");
    if (!this.audience)
      throw new ApiError(
        503,
        "google_not_configured",
        "Google sign-in is not available right now.",
      );
    try {
      const ticket = await this.client.verifyIdToken({
        idToken,
        audience: this.audience,
      });
      const payload = ticket.getPayload();
      const email = normalizeEmail(payload?.email);
      if (
        !payload ||
        typeof payload.sub !== "string" ||
        payload.sub.length < 8 ||
        !validEmail(email) ||
        payload.email_verified !== true ||
        !["accounts.google.com", "https://accounts.google.com"].includes(
          payload.iss,
        )
      )
        throw new Error("invalid Google identity");
      return { subject: payload.sub, email };
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError(
        401,
        "invalid_google_token",
        "Google sign-in could not be verified.",
      );
    }
  }
}

export class ResendPasswordResetSender {
  constructor({ apiKey, from, fetch = globalThis.fetch }) {
    this.apiKey = apiKey;
    this.from = from;
    this.fetch = fetch;
  }

  get configured() {
    return Boolean(this.apiKey && this.from);
  }

  async send({ email, token }) {
    if (!this.configured)
      throw new ApiError(
        503,
        "password_reset_unavailable",
        "Password reset is not available right now.",
      );
    const response = await this.fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: this.from,
        to: [email],
        subject: "Your Level Up password reset code",
        text: `Use this one-time code in the Level Up app to reset your password:\n\n${token}\n\nIt expires in 30 minutes. If you did not request this, you can ignore this email.`,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      throw new ApiError(
        503,
        "password_reset_unavailable",
        "Password reset is not available right now.",
      );
    }
  }
}

export class AuthService {
  constructor(
    store,
    config,
    { hashCost = 12, googleVerifier, passwordResetSender } = {},
  ) {
    this.store = store;
    this.config = config;
    this.hashCost = hashCost;
    this.key = new TextEncoder().encode(config.JWT_SECRET);
    this.googleVerifier =
      googleVerifier ?? new GoogleIdentityVerifier(config.GOOGLE_OAUTH_WEB_CLIENT_ID);
    this.passwordResetSender =
      passwordResetSender ??
      new ResendPasswordResetSender({
        apiKey: config.RESEND_API_KEY,
        from: config.EMAIL_FROM,
      });
    this.dummyHash = bcrypt.hashSync(
      "not-a-real-password-for-timing",
      hashCost,
    );
  }
  credentials(body) {
    if (
      !allowedKeys(body, ["email", "password"])
    )
      throw new ApiError(
        422,
        "validation_failed",
        "Email and password are required.",
      );
    const email = this.email(body.email), password = this.password(body.password);
    return { email, password };
  }
  email(value) {
    const email = normalizeEmail(value);
    if (!validEmail(email))
      throw new ApiError(422, "invalid_email", "Enter a valid email address.");
    return email;
  }
  password(value) {
    if (
      typeof value !== "string" ||
      Array.from(value).length < 12 ||
      Buffer.byteLength(value, "utf8") > 72
    )
      throw new ApiError(
        422,
        "weak_password",
        "Use at least 12 characters and no more than 72 UTF-8 bytes.",
      );
    return value;
  }
  userResponse(user) {
    return {
      id: user._id,
      email: user.email,
      hasPassword: user.passwordEnabled !== false,
      hasGoogle: typeof user.googleSubject === "string" && user.googleSubject.length > 0,
    };
  }
  async register(body) {
    const { email, password } = this.credentials(body),
      passwordHash = await bcrypt.hash(password, this.hashCost);
    const user = {
      _id: randomUUID(),
      email,
      passwordHash,
      passwordEnabled: true,
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
      user?.passwordEnabled === false ? this.dummyHash : user?.passwordHash ?? this.dummyHash,
    );
    if (!valid || !user || user.passwordEnabled === false)
      throw new ApiError(
        401,
        "invalid_credentials",
        "Email or password is incorrect.",
      );
    return this.store.transaction((session) => this.issue(user, session));
  }
  async issue(user, session) {
    // All session issuance writes the account document before inserting the
    // session. Password reset writes that same document before revocation, so
    // MongoDB serializes the operations instead of permitting a stale password
    // login to create a session after reset has revoked earlier sessions.
    const account = await this.store.db.collection("users").updateOne(
      { _id: user._id, passwordHash: user.passwordHash },
      { $inc: { sessionIssueSerial: 1 } },
      { session },
    );
    if (account.matchedCount !== 1)
      throw new ApiError(401, "invalid_credentials", "Email or password is incorrect.");
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
      user: this.userResponse(user),
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
  googleToken(body) {
    if (!allowedKeys(body, ["idToken"]))
      throw new ApiError(422, "validation_failed", "A Google ID token is required.");
    return body.idToken;
  }
  async googleLogin(body) {
    const identity = await this.googleVerifier.verify(this.googleToken(body));
    try {
      return await this.store.transaction(async (session) => {
        let user = await this.store.db
          .collection("users")
          .findOne({ googleSubject: identity.subject }, { session });
        if (user) return this.issue(user, session);
        const sameEmail = await this.store.db
          .collection("users")
          .findOne({ email: identity.email }, { session });
        if (sameEmail)
          throw new ApiError(
            409,
            "google_link_required",
            "Sign in with your password first to link Google.",
          );
        user = {
          _id: randomUUID(),
          email: identity.email,
          // The schema deliberately keeps a non-null string for legacy and
          // migration compatibility. No user knows this random value, and
          // passwordEnabled keeps it out of password authentication.
          passwordHash: await bcrypt.hash(
            randomBytes(48).toString("base64url"),
            this.hashCost,
          ),
          passwordEnabled: false,
          googleSubject: identity.subject,
          createdAt: this.store.clock(),
        };
        await this.store.db.collection("users").insertOne(user, { session });
        return this.issue(user, session);
      });
    } catch (error) {
      if (error?.code !== 11000) throw error;
      // A concurrent sign-in can win either the provider or e-mail index. The
      // next request receives the deterministic, non-merging result.
      const owner = await this.store.db
        .collection("users")
        .findOne({ googleSubject: identity.subject });
      if (owner) return this.store.transaction((session) => this.issue(owner, session));
      throw new ApiError(
        409,
        "google_link_required",
        "Sign in with your password first to link Google.",
      );
    }
  }
  async linkGoogle(ownerId, body) {
    const identity = await this.googleVerifier.verify(this.googleToken(body));
    try {
      return await this.store.transaction(async (session) => {
        const user = await this.store.db
          .collection("users")
          .findOne({ _id: ownerId }, { session });
        if (!user) throw new ApiError(401, "unauthorized", "Sign in to access your data.");
        if (user.email !== identity.email)
          throw new ApiError(
            409,
            "google_email_mismatch",
            "Choose the Google account with the same email address.",
          );
        if (user.googleSubject && user.googleSubject !== identity.subject)
          throw new ApiError(
            409,
            "google_already_linked",
            "This account is already linked to a different Google account.",
          );
        const existing = await this.store.db
          .collection("users")
          .findOne({ googleSubject: identity.subject }, { session });
        if (existing && existing._id !== ownerId)
          throw new ApiError(
            409,
            "google_already_linked",
            "This Google account is already linked to another account.",
          );
        if (!existing)
          await this.store.db
            .collection("users")
            .updateOne({ _id: ownerId }, { $set: { googleSubject: identity.subject } }, { session });
        return { user: this.userResponse({ ...user, googleSubject: identity.subject }) };
      });
    } catch (error) {
      if (error?.code === 11000)
        throw new ApiError(
          409,
          "google_already_linked",
          "This Google account is already linked to another account.",
        );
      throw error;
    }
  }
  passwordResetRequest(body) {
    if (!allowedKeys(body, ["email"]))
      throw new ApiError(422, "validation_failed", "Enter a valid email address.");
    return this.email(body.email);
  }
  async requestPasswordReset(body) {
    const email = this.passwordResetRequest(body);
    if (!this.passwordResetSender.configured)
      throw new ApiError(
        503,
        "password_reset_unavailable",
        "Password reset is not available right now.",
      );
    let resetId;
    try {
      const user = await this.store.db.collection("users").findOne({ email });
      // Keep public responses identical for unknown and Google-only accounts,
      // and for delivery failures. This response confirms the request only;
      // it deliberately does not assert that an email was delivered.
      if (!user || user.passwordEnabled === false) return { accepted: true };
      const token = randomBytes(32).toString("hex");
      const created = await this.store.transaction(async (session) => {
        const now = this.store.clock();
        // Serialize concurrent recovery requests, including when this user has
        // no previous codes yet. Also refuse a code derived from stale account
        // data after a concurrent credential change.
        const account = await this.store.db.collection("users").updateOne(
          { _id: user._id, passwordHash: user.passwordHash },
          { $inc: { resetRequestSerial: 1 } },
          { session },
        );
        if (account.matchedCount !== 1) return false;
        resetId = randomUUID();
        await this.store.db.collection("passwordResets").updateMany(
          { ownerId: user._id, usedAt: null },
          { $set: { usedAt: now } },
          { session },
        );
        await this.store.db.collection("passwordResets").insertOne(
          {
            _id: resetId,
            ownerId: user._id,
            tokenHash: hashToken(token),
            createdAt: now,
            expiresAt: new Date(now.getTime() + 30 * 60 * 1000),
            usedAt: null,
          },
          { session },
        );
        return true;
      });
      if (!created) return { accepted: true };
      await this.passwordResetSender.send({ email: user.email, token });
    } catch {
      // An unsent code must not remain usable. Do not let a failure specific to
      // one recipient reveal account existence through a different HTTP result.
      if (resetId) {
        try {
          await this.store.db.collection("passwordResets").updateOne(
            { _id: resetId, usedAt: null },
            { $set: { usedAt: this.store.clock() } },
          );
        } catch {
          // No raw token was exposed or logged. It is still short-lived and
          // cannot be used without possession of the undelivered random code.
        }
      }
      console.error("Password reset delivery failed");
    }
    return { accepted: true };
  }
  passwordResetConfirmation(body) {
    if (!allowedKeys(body, ["email", "token", "password"]))
      throw new ApiError(422, "validation_failed", "Enter the reset code and a new password.");
    const token = typeof body.token === "string" ? body.token.trim() : "";
    if (token.length < 32 || token.length > 200)
      throw new ApiError(422, "invalid_reset_token", "The reset code is invalid or expired.");
    return { email: this.email(body.email), token, password: this.password(body.password) };
  }
  async completePasswordReset(body) {
    const { email, token, password } = this.passwordResetConfirmation(body);
    const passwordHash = await bcrypt.hash(password, this.hashCost);
    return this.store.transaction(async (session) => {
      const now = this.store.clock();
      const reset = await this.store.db
        .collection("passwordResets")
        .findOneAndUpdate(
          {
            tokenHash: hashToken(token),
            usedAt: null,
            expiresAt: { $gt: now },
          },
          { $set: { usedAt: now } },
          { session, returnDocument: "before" },
        );
      if (!reset)
        throw new ApiError(422, "invalid_reset_token", "The reset code is invalid or expired.");
      const user = await this.store.db
        .collection("users")
        .findOne({ _id: reset.ownerId, email }, { session });
      if (!user)
        throw new ApiError(422, "invalid_reset_token", "The reset code is invalid or expired.");
      await this.store.db.collection("users").updateOne(
        { _id: user._id },
        { $set: { passwordHash, passwordEnabled: true, passwordChangedAt: now } },
        { session },
      );
      await this.store.db.collection("sessions").updateMany(
        { ownerId: user._id, revokedAt: null },
        { $set: { revokedAt: now } },
        { session },
      );
      return { reset: true };
    });
  }
  async verify(header) {
    if (typeof header !== "string" || !header.startsWith("Bearer "))
      throw new ApiError(401, "unauthorized", "Sign in to access your data.");
    let payload;
    try {
      ({ payload } = await jwtVerify(header.slice(7), this.key, {
        algorithms: ["HS256"],
        issuer: this.config.JWT_ISSUER,
        audience: this.config.JWT_AUDIENCE,
        requiredClaims: ["sub", "sid", "iat", "exp"],
        currentDate: this.store.clock(),
      }));
      if (typeof payload.sub !== "string" || typeof payload.sid !== "string")
        throw new Error();
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError(
        401,
        "unauthorized",
        "Your session has expired. Sign in again.",
      );
    }
    // Database unavailability is an availability failure, not proof that an
    // otherwise valid session has expired. Let the safe API handler return 503
    // so an offline client preserves its credentials and queued private data.
    const session = await this.store.db.collection("sessions").findOne({
      _id: payload.sid,
      ownerId: payload.sub,
      revokedAt: null,
      expiresAt: { $gt: this.store.clock() },
    });
    if (!session)
      throw new ApiError(401, "unauthorized", "Your session has expired. Sign in again.");
    return payload.sub;
  }
}
