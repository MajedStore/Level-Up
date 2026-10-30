# Authentication and cloud-sync implementation report

## Verified deployment state

The production API origin is `https://level-up-5nmw.onrender.com`. On 30
October 2026, `/health` returned `200 {"status":"ok"}` and the safe,
credential-free `GET /api/v1/state` returned `401 unauthorized` after the
Render service was redeployed with `TRUST_PROXY_HOPS=1`. This verifies that
Render reaches Atlas and that forwarded HTTPS reaches authentication. It did
not create an account or change cloud data.

The former `426 https_required` response was the shared root cause of
registration, sign-in, and sync failures: the deployed server was not trusting
Render's forwarded HTTPS hop. It was not evidence of an Atlas outage.

## Delivered changes

- The backend supports hardened email/password sessions, refresh and logout,
  Google ID-token verification and explicit account linking, and hashed,
  single-use, 30-minute password-reset codes. Password resets revoke existing
  sessions after completion.
- Google identities are verified cryptographically by the server. A matching
  email alone never silently merges a Google account with an existing password
  account.
- Resend delivery is optional and fails safely. It needs a server-only API key
  and a Resend-verified sender in Render before password resets can be sent.
- The Flutter client adds Google sign-in, password-recovery screens, safe
  session parsing, retried durable cloud synchronization, account-bound local
  archives, and clear Arabic/English error states.
- Build and CI validation reject an unsafe API origin and require the public
  health endpoint plus the private-route `401` readiness result.

## Verification completed

| Check | Result |
| --- | --- |
| Backend tests | 54 passed |
| Backend static check | Passed |
| Production dependency audit | No known vulnerabilities |
| Deployment/helper tests | 17 passed |
| Focused Flutter authentication/sync tests | 51 passed |
| Live API safe readiness | `/health` 200; private route 401 |
| Local real-Mongo Flutter integration | Passed without production writes |
| Debug Android APK | Built against the production API origin |

The diagnostic APK is debug-signed. `android/key.properties` is absent, so no
new distributable release APK has been claimed or produced. Configure the
intended existing release identity before publishing or updating the Android
app.

## Remaining external configuration

1. Rotate the MongoDB password, JWT secret, and Resend API key that were
   exposed outside their intended secret stores. Update the replacements only
   in local ignored environment files and Render's environment settings.
2. In Render, set `GOOGLE_OAUTH_WEB_CLIENT_ID` to the Web OAuth client ID and
   set `RESEND_API_KEY` plus a Resend-verified `EMAIL_FROM`. Redeploy after
   each configuration change.
3. In Google Cloud, register package `com.streak.app` with the SHA-1 for the
   actual release signer (and Play App Signing certificate if applicable).
   Build Android with that same Web client ID in
   `LEVEL_UP_GOOGLE_SERVER_CLIENT_ID`.
4. Once those external settings are complete, create a disposable account to
   perform the end-to-end registration, Google, password-reset, multi-device
   sync, and offline-retry checks in [authentication configuration](AUTH_CONFIGURATION.md).

No production account was created as part of implementation or safe deployment
verification.
