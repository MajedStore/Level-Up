import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { OAuth2Client } from "google-auth-library";
import { SignJWT } from "jose";
import { AuthService, GoogleIdentityVerifier, ResendPasswordResetSender } from "../src/auth.js";

const audience = "local-auth-test.apps.googleusercontent.com";
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const client = new OAuth2Client();
// Use the real Google verification code with a local disposable signing key.
// Only certificate retrieval is replaced; no Google credential is required.
client.getFederatedSignonCertsAsync = async () => ({
  certs: { "local-test-key": publicKey.export({ type: "spki", format: "pem" }) },
});
const verifier = new GoogleIdentityVerifier(audience, { client });
const token = (claims = {}, signingKey = privateKey) => {
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({
    sub: "google-test-subject",
    email: "User@Example.test",
    email_verified: true,
    iss: "https://accounts.google.com",
    aud: audience,
    iat: now - 30,
    exp: now + 3600,
    ...claims,
  }).setProtectedHeader({ alg: "RS256", kid: "local-test-key" }).sign(signingKey);
};

test("Google verification checks a real signature and normalizes verified identity", async () => {
  assert.deepEqual(await verifier.verify(await token()), {
    subject: "google-test-subject",
    email: "user@example.test",
  });
});

test("Google verification rejects wrong audience, expired token, issuer, signature and unverified email", async () => {
  const other = generateKeyPairSync("rsa", { modulusLength: 2048 });
  for (const value of [
    await token({ aud: "another-app.apps.googleusercontent.com" }),
    await token({ iat: Math.floor(Date.now() / 1000) - 7200, exp: Math.floor(Date.now() / 1000) - 3600 }),
    await token({ iss: "https://attacker.example.test" }),
    await token({ email_verified: false }),
    await token({}, other.privateKey),
  ]) {
    await assert.rejects(verifier.verify(value), {
      status: 401,
      code: "invalid_google_token",
      message: "Google sign-in could not be verified.",
    });
  }
});

test("Google configuration is required and arbitrary client identities are not accepted", async () => {
  await assert.rejects(new GoogleIdentityVerifier("").verify(await token()), {
    status: 503,
    code: "google_not_configured",
  });
  await assert.rejects(verifier.verify("client-supplied-user-id"), {
    status: 401,
    code: "invalid_google_token",
  });
});

test("password policy counts Unicode characters rather than UTF-16 halves", () => {
  const auth = new AuthService({}, { JWT_SECRET: "local-test-key" }, { hashCost: 4 });
  assert.throws(() => auth.password("😀".repeat(6)), { code: "weak_password" });
  assert.equal(auth.password("😀".repeat(12)), "😀".repeat(12));
});

test("email sender has a bounded request and never returns provider error details", async () => {
  let options;
  const sender = new ResendPasswordResetSender({
    apiKey: "local-test-mail-key",
    from: "Level Up <test@example.test>",
    fetch: async (_, value) => {
      options = value;
      return { ok: false };
    },
  });
  await assert.rejects(sender.send({ email: "user@example.test", token: "local-test-reset-code" }), {
    status: 503,
    code: "password_reset_unavailable",
    message: "Password reset is not available right now.",
  });
  assert.ok(options.signal instanceof AbortSignal);
});

test("access verification requires expiry and rejects wrong issuer or audience", async () => {
  const config = {
    JWT_SECRET: "local-test-signing-key-with-at-least-thirty-two-bytes",
    JWT_ISSUER: "level-up-api",
    JWT_AUDIENCE: "level-up-android",
  };
  const now = new Date();
  const service = new AuthService({
    clock: () => now,
    db: { collection: () => ({ findOne: async () => ({ _id: "sid" }) }) },
  }, config, { hashCost: 4 });
  const key = new TextEncoder().encode(config.JWT_SECRET);
  const build = (changes = {}, expires = true) => {
    let jwt = new SignJWT({
      sub: "owner",
      sid: "sid",
      iat: Math.floor(now.getTime() / 1000),
      iss: config.JWT_ISSUER,
      aud: config.JWT_AUDIENCE,
      ...changes,
    }).setProtectedHeader({ alg: "HS256" });
    if (expires) jwt = jwt.setExpirationTime(Math.floor(now.getTime() / 1000) + 900);
    return jwt.sign(key);
  };
  assert.equal(await service.verify(`Bearer ${await build()}`), "owner");
  for (const jwt of [
    await build({}, false),
    await build({ iss: "other-service" }),
    await build({ aud: "other-client" }),
  ]) {
    await assert.rejects(service.verify(`Bearer ${jwt}`), { status: 401, code: "unauthorized" });
  }
});
