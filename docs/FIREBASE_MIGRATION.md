# Firebase migration and secure rollout

## Current implementation state

Level Up now includes a Firebase transport that is activated only after valid
Firebase options are present. It provides Firebase email/password auth, Google
credential exchange, password-reset links, Firebase session restoration, a
Firestore state listener, and a callable sync path. Until then, the existing
Express/Render/Mongo transport remains active so current accounts and queued
planner data are not interrupted.

The repository did not contain a Firebase project configuration, Android
`google-services.json`, or generated `firebase_options.dart`. No Firebase
project ID, OAuth client, API key, or other configuration was invented.

## Data model and trust boundary

The canonical planner snapshot is stored at:

```text
users/{firebaseUid}/planner/state
```

It contains the revision, planner state, compact app settings, time zone and a
server timestamp. Idempotency records are private subdocuments below it at
`mutations/{mutationId}`. The client can listen to its own state document but
cannot write it directly. `syncPlannerState` is a second-generation callable
function that verifies Firebase Auth and App Check, checks the mutation hash
and revision inside a Firestore transaction, then runs the existing Level Up
server-side transition/XP rules before committing.

This keeps duplicate retries idempotent and prevents a modified client from
minting XP. Firestore document size is deliberately capped below 1 MiB. A state
that is too large remains queued locally and must stay on the existing backend
or be migrated to a future chunked model; it is never silently truncated.

## Required Firebase Console work

1. Create or select the Firebase project that should own Level Up. Register its
   Android app using the existing package ID `com.streak.app`.
2. Add the SHA-1 of the actual release signing certificate. Add the Play App
   Signing SHA-1 too if Play distributes the app. Enable the Google provider in
   Firebase Authentication and add the Android OAuth client in the same Google
   Cloud project.
3. Enable Email/Password and Google under **Authentication -> Sign-in method**.
   Configure the password-reset email template and approved continue URLs.
4. Create a Firestore database in production mode, then deploy the included
   restrictive rules. Do not replace them with test-mode rules.
5. Enable Play Integrity in **App Check** for the Android app before deploying
   the callable. Register debug devices only for development. The callable
   enforces App Check.
6. Firebase Functions requires a billing-enabled Firebase/Google Cloud project.
   Install the Firebase CLI, select the existing project, then deploy from the
   repository root. The Firebase CLI is not installed in this workspace, so
   these commands are intentionally documented rather than run here:

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android --out=lib/firebase_options.dart
npm install
npm run firebase:check
firebase deploy --only firestore:rules,functions:syncPlannerState
```

`flutterfire configure` replaces the safe, unconfigured
`lib/firebase_options.dart` starter with the generated configuration for the
chosen project. Its identifiers are configuration, not server secrets. Do not
put service-account JSON, OAuth client secrets, MongoDB credentials, Resend
keys, or JWT signing keys into the Flutter app.

## Android build configuration

The Google identity package still needs the Web OAuth client ID to obtain an ID
token. Build with that client ID; never use a client secret:

```powershell
flutter build apk --release `
  --dart-define=LEVEL_UP_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

For local App Check development only, add
`--dart-define=LEVEL_UP_FIREBASE_DEBUG_APP_CHECK=true`, enroll the displayed
debug token in Firebase Console, and never use that define for a release build.

## Existing-account migration

MongoDB password hashes cannot be converted into Firebase passwords, and an
existing Mongo user ID is not proof of a Firebase UID. Do not auto-create or
merge Firebase accounts from old records. Keep Render/Mongo online during the
transition. First verify a disposable Firebase account end to end, then choose
an explicit migration per account: export/restore local data after Firebase
sign-in, or run a separately reviewed admin-only migration that maps a verified
old account to a verified Firebase UID and invokes the trusted transition.

Do not disable the existing backend until registration, Google sign-in,
password reset, offline retry, multi-device updates, and data migration have
been verified with real Firebase configuration.

## Verification completed locally

- `flutter pub get` completed with the Firebase packages.
- The changed Firebase/authentication/sync Dart files analyze cleanly. The full
  project analyzer has no errors or warnings; it reports eight pre-existing
  Flutter deprecation infos in unrelated widgets.
- Focused account, Google, API and synchronization tests: **52 passed**.
- Full Flutter suite: **747 passed, 3 expected skips**.
- Existing backend validation: **54 passed**, static check passed, production
  dependency audit found zero vulnerabilities.
- The Firebase callable module passes `npm run firebase:check`, imports
  successfully, and its production dependency audit found zero vulnerabilities.
- A debug Android APK built successfully after the Firebase Auth dependency
  required Kotlin 2.4 support. Its SHA-256 is
  `7E9ACF5ED8C7EB976DB7C3DDE1B27024EC815EE869CBBA7B3621F4723852E030`.

The Firebase CLI, a Firebase project, generated FlutterFire options, deployed
rules/functions, App Check enrollment, and a real Firebase account are not
available in this workspace. Therefore no live Firebase registration, Google
sign-in, Firestore write, listener, or migration is claimed as tested.
