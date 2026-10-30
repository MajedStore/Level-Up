# Firebase migration and secure rollout

## Current implementation state

Level Up now includes a Firebase transport that is activated only after valid
Firebase options are present. It provides Firebase email/password auth, Google
credential exchange, password-reset links, Firebase session restoration, a
Firestore state listener, and callable synchronization. Until configuration is
present, the app remains local-only. It has no alternate HTTP account or data
transport.

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
that is too large remains queued locally for a future chunked model; it is
never silently truncated.

Habits, categories, notes, focus sessions, to-dos and tags use a second
account-owned document at `users/{firebaseUid}/private/state`. It is read-only
to the signed-in user and every mutation goes through the App-Check-protected
`syncPrivateData` callable. It has an independent revision and idempotency
record, so pending offline local work is retained instead of overwriting a
newer device. Device settings, backup locations, credentials, local journals
and planner XP state are deliberately excluded.

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
Push-Location functions
npm ci
npm run check
Pop-Location
firebase deploy --only firestore:rules,functions:syncPlannerState,functions:syncPrivateData
```

`flutterfire configure` replaces the safe, unconfigured
`lib/firebase_options.dart` starter with the generated configuration for the
chosen project. Its identifiers are configuration, not server secrets. Do not
put service-account JSON, OAuth client secrets, or any server signing key into
the Flutter app.

## Google Sign-In configuration

`LEVEL_UP_GOOGLE_SERVER_CLIENT_ID` is read only by
[`GoogleSignInService`](../lib/services/google_sign_in_service.dart) through a
Flutter compile-time `String.fromEnvironment`. It is the **Web OAuth client
ID**, not a secret. It belongs in the Flutter build/CI variable because the
Google Sign-In Android plugin requests an ID token for that audience. It does
not belong in Firebase Functions configuration or a Functions secret: Firebase
Authentication verifies the credential when the app calls
`signInWithCredential`.

To configure it:

1. In Firebase Console, open your project, then **Authentication -> Sign-in
   method -> Google** and enable it. Save the project support email.
2. Open **Project settings -> General -> Your apps -> Android app**. Add the
   debug/release/Play signing SHA-1 fingerprints as applicable.
3. Open the linked Google Cloud project’s **APIs & Services -> Credentials**.
   Copy the OAuth 2.0 client of type **Web application**; its ID ends in
   `.apps.googleusercontent.com`. Do not copy a client secret.
4. Enter that ID as the GitHub repository variable
   `LEVEL_UP_GOOGLE_SERVER_CLIENT_ID` (or the workflow dispatch input), or pass
   it locally as the Dart define below.

`flutterfire configure` selects the Firebase project, registers/updates the
platform app, generates `lib/firebase_options.dart`, and downloads Android
configuration as needed. It does not create a Web OAuth client secret, enable
providers, add SHA fingerprints, or set this Dart build variable.

Build with the Web client ID; never use a client secret:

```powershell
flutter build apk --release `
  --dart-define=LEVEL_UP_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

For local App Check development only, add
`--dart-define=LEVEL_UP_FIREBASE_DEBUG_APP_CHECK=true`, enroll the displayed
debug token in Firebase Console, and never use that define for a release build.

## Existing-account migration

Credentials from a retired service cannot be converted into Firebase passwords,
and a retired account ID is not proof of a Firebase UID. Do not auto-create or
merge Firebase accounts from an unverified export. First verify a disposable
Firebase account end to end, then perform an explicit, separately reviewed
admin migration that maps a verified retired account to a verified Firebase UID
and invokes the trusted callable paths. Preserve revision order and never write
Firestore directly from an export script.

No import utility is retained in this repository because no completed,
verified export mapping exists. Any future one-time utility must be kept outside
the Flutter runtime, use Firebase Admin credentials from a secret manager, and
be removed after the migration is audited.

## Verification completed locally

- `flutter pub get` completed with the Firebase packages.
- The changed Firebase/authentication/sync Dart files analyze cleanly. The full
  project analyzer has no errors or warnings; it reports eight pre-existing
  Flutter deprecation infos in unrelated widgets.
- Focused account, Google and synchronization tests passed before this cleanup.
- The Firebase callable module is checked from `functions/` with `npm run check`.
- A debug Android APK built successfully after the Firebase Auth dependency
  required Kotlin 2.4 support. Its SHA-256 is
  `7E9ACF5ED8C7EB976DB7C3DDE1B27024EC815EE869CBBA7B3621F4723852E030`.

The Firebase CLI, a Firebase project, generated FlutterFire options, deployed
rules/functions, App Check enrollment, and a real Firebase account are not
available in this workspace. Therefore no live Firebase registration, Google
sign-in, Firestore write, listener, or migration is claimed as tested.
