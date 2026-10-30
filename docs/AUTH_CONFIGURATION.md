# Level Up authentication configuration

This guide covers the configuration that cannot be safely created by source
code. It uses the actual Android application ID, `com.streak.app`. Do not put a
database URI, JWT secret, Google client secret, reset code or mail API key in a
Dart define, an APK, Git, or chat.

## 1. Repair the deployed API first

The public readiness check at `https://level-up-5nmw.onrender.com/health`
currently returns `{"status":"ok"}`. That proves Render can reach Atlas. A
safe unauthenticated private-route check currently returns `426
https_required`, which proves the deployed service is not trusting Render's
forwarded HTTPS hop. It explains the shared registration, sign-in and sync
failure.

In Render, open the existing Web Service and set these environment values, then
use **Manual Deploy -> Deploy latest commit** after the code is uploaded:

| Variable | Value |
| --- | --- |
| `NODE_ENV` | `production` |
| `HOST` | `0.0.0.0` |
| `TRUST_PROXY_HOPS` | `1` |
| `MONGODB_DATABASE` | `level_up` |
| `MONGODB_URI` | your existing secret Atlas URI |
| `JWT_SECRET` | a newly rotated server-only secret |

The updated server also infers one proxy hop when Render supplies its `RENDER`
environment marker, but the explicit setting keeps the topology reviewable.
Do not set `TRUST_PROXY_HOPS` above the actual number of trusted proxies.

After deployment, run this safe check. It must report `state_unauth=401`, not
`426`; it creates no account and sends no credentials.

```powershell
node scripts/validate_api_origin.mjs https://level-up-5nmw.onrender.com --auth-readiness
curl.exe --silent --show-error --max-time 30 -o NUL -w "state_unauth=%{http_code}`n" https://level-up-5nmw.onrender.com/api/v1/state
```

## 2. Google Sign-In

The app uses `google_sign_in` and sends a short-lived Google **ID token** to the
API. The API verifies it with Google's server library before it creates a Level
Up session. The Web OAuth client ID is public configuration; the client secret
must not be used by the Android app or this API flow.

1. In Google Cloud Console, select or create a project and finish the OAuth
   consent-screen details for the audience you will test.
2. Create an **Android** OAuth 2.0 client with package name `com.streak.app`.
   Add the SHA-1 for every signing identity that will run the app: debug for
   local testing, your existing release keystore for direct APKs, and the Play
   App Signing certificate if Google Play distributes the app.
3. Create a **Web application** OAuth 2.0 client in the same project. The
   resulting client ID, ending in `.apps.googleusercontent.com`, is the single
   value used by both the Android build and server audience check. Leave web
   redirect/origin fields empty for this native ID-token flow unless you add a
   browser client later.
4. In Render add `GOOGLE_OAUTH_WEB_CLIENT_ID` with that Web client ID. It is an
   identifier, not a secret. Redeploy.
5. Build the APK with the same value:

```powershell
flutter build apk --release `
  --dart-define=LEVEL_UP_API_BASE_URL=https://level-up-5nmw.onrender.com `
  --dart-define=LEVEL_UP_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Obtain fingerprints without exposing a keystore password in source control:

```powershell
Set-Location android
.\gradlew signingReport
```

The existing APK was inspected with Android's `apksigner`: it uses the Android
Debug certificate, with SHA-1
`D3:34:2D:13:81:C5:CA:63:67:71:B0:B2:72:4A:5E:C7:7A:B6:2E:E3`.
This fingerprint applies only to this machine's current diagnostic signer.
`android/key.properties` is currently absent. Configure your intended existing
release identity and obtain its separate fingerprint before distributing a
release; do not create a replacement key to update an existing app.

If `android/key.properties` is configured, the Gradle report shows the actual
release variant. Google configuration errors commonly come from a missing/incorrect
SHA-1, package name, or Web `serverClientId`; the app shows a safe user-facing
message rather than treating an arbitrary Google user ID/email as proof.

Existing email/password accounts are never auto-merged merely because a Google
email matches. Sign in with the password account and choose **Link Google**;
the backend requires the signed-in account and a verified matching email.

## 3. Password reset delivery

Password reset is intentionally disabled until outbound email is configured.
The backend supports [Resend](https://resend.com): create an API key in Resend,
verify a sender domain/address, then set these Render variables directly in the
dashboard:

| Variable | Value |
| --- | --- |
| `RESEND_API_KEY` | Resend API key; secret |
| `EMAIL_FROM` | verified sender, such as `Level Up <support@your-domain>` |

After redeployment, the app's **Forgot password?** flow gives the same generic
acceptance for unknown accounts and delivery failures. Acceptance confirms only
the request. For an eligible account and successful delivery, the email contains
a 64-character one-time code that expires in 30 minutes. The API stores only its
hash and revokes all sessions when the code is used. Sender failure invalidates
the unsent code and logs only a stable error category. Responses are not claimed
to be constant-time. Test with a disposable account and check the mailbox; do
not share a reset code.

## 4. Offline synchronization and conflicts

Each saved planner change keeps its durable mutation ID and base revision.
Retries use the same checkpoint, so a repeated request cannot duplicate a task
or award XP twice. Active-app recovery retries after 2, 4, 8, 16 and 30 seconds,
then waits for a manual **Sync now** or another app session. Temporary network
or database errors preserve credentials and pending work. A rejected refresh
archives the account's private local work before clearing its credentials.

Conflicting revisions are never resolved by a silent full-state overwrite.
The app retains the local proposal and offers export or explicit cloud restore;
restore saves the pending proposal in an encrypted account archive. The server
continues to validate XP and deadline-sensitive transitions. Historic local
completion or overdue proposals that cannot be validated remain visible as
conflicts rather than being silently accepted or discarded.

## 5. End-to-end checks

1. Confirm `/health` is 200 and the private route check above is 401.
2. Register a disposable email/password account; restart the app and confirm
   its session restores.
3. Make a small planner change, wait for **Synchronized**, then sign in on a
   second device and verify only that account's data appears.
4. Turn the network off, make a change, relaunch, reconnect, and confirm it
   changes from **Pending** to **Synchronized** without duplicate XP.
5. Use password reset once, confirm the previous session becomes invalid, and
   sign in with the new password.
6. Test Google Sign-In on an APK signed by a registered certificate. Confirm a
   different account cannot read the first account's state.

Google sources: [Flutter's Google Sign-In package](https://pub.dev/packages/google_sign_in),
[Android package/signing registration guidance](https://developers.google.com/android/guides/client-auth),
and [the Android plugin's server client-ID guidance](https://pub.dev/packages/google_sign_in_android).
