# Firebase setup and synchronization

Level Up uses Firebase Authentication and Cloud Firestore directly. The
Flutter runtime no longer depends on Cloud Functions or an external HTTP API.
Firebase Authentication and Firestore can be used on Spark; this design does
not require Functions deployment or a billing-plan upgrade.

## Data layout and transaction behavior

Each signed-in user's planner snapshot lives at:

```text
users/{firebaseUid}/planner/state
```

The private habit/task snapshot lives at:

```text
users/{firebaseUid}/private/state
```

Both documents carry a monotonically increasing revision and a
`lastMutationId`. Each successful revision is paired atomically with an
immutable record at `state/mutations/{mutationId}`. Clients use Firestore
transactions to check the previous revision, detect duplicate retries, and
commit the state plus mutation record together. Realtime listeners watch only
the current user's state documents.

Planner edits are first persisted to the existing local planner queue. When
online, the queue submits its ordered mutations; conflicts retain the local
draft for the existing conflict/recovery flow. Private records stay in Hive,
with pending state retained across restarts. Transactions need a network
connection; offline edits remain local and are retried on a subsequent
foreground or account activation.

The rules enforce the UID path, document envelope, allowed top-level fields,
revision increments and paired mutation records. Private payloads are limited
to the six existing account-owned collections. They do not validate every
nested record or execute the former server-side planner transition algorithm.
Flutter keeps the existing model/progression validation for normal app use, but
a user who modifies the client can alter their own planner/XP document. Rules
still prevent that user from reading or writing another UID's documents. A
server-authoritative XP guarantee cannot be preserved on Spark using Firestore
Rules alone; that requires trusted server code such as Cloud Functions or
another backend.

The local rules test suite exercises authenticated ownership, cross-user
isolation, invalid document shapes, revision concurrency and recovery after a
network interruption. It does not test production project settings or
authenticated live data.

## Firebase Console checklist

1. In **Authentication → Sign-in method**, enable Email/Password and Google.
   Configure the support email and password-reset template/continue URLs.
2. In **Project settings → General → Your apps**, ensure the Android app has
   package ID `com.streak.app` and register the signing fingerprints used by
   your debug/release builds.
3. In **Firestore Database → Rules**, deploy the repository's `firestore.rules`
   after reviewing the owner-only rules. No rules deployment was performed as
   part of this code change.
4. In **App Check → Apps**, register the Android app with Play Integrity if you
   enforce App Check for Firestore. For emulator development, use the app's
   debug-provider define and register the generated debug token; never ship it
   in release builds.

The repository's `firebase.json` no longer configures a Functions deployment.
The old `functions/` source remains in the tree as a reference but is not
imported by Flutter or included in Firebase deployment configuration.

## Google Sign-In

On Android, `google_sign_in` reads the Web OAuth client ID from the generated
`default_web_client_id` resource produced by the Google Services Gradle plugin.
The client ID is therefore sourced from the same `google-services.json` as the
Firebase project; do not pass the old backend `.env` value as a Flutter define.
No OAuth client ID or secret needs to be copied into Flutter source.

Run Android builds without a Google OAuth define:

```powershell
flutter run
```

`flutterfire configure --project level-up-cf52d --platforms android` generates
or refreshes `lib/firebase_options.dart` for the selected Firebase project and
updates native Android Firebase configuration as needed. It does not enable
Authentication providers, register signing fingerprints, or complete a real
Google sign-in test.

## Existing-account migration

Credentials from a retired service cannot be converted into Firebase
passwords, and an old account ID is not proof of a Firebase UID. Do not merge
accounts from an unverified export. No migration utility is retained. Any
future import must be separately reviewed, map verified accounts to verified
Firebase UIDs, and preserve the local pending-change recovery path.

## Local verification

Run Flutter checks from the project root:

```powershell
flutter analyze
flutter test
```

Run the rules suite using the Firebase Emulator Suite and a JDK supported by
the installed Firebase CLI:

```powershell
npm install --prefix test\firestore_rules
firebase emulators:exec --only firestore --project demo-level-up-rules "npm --prefix test/firestore_rules test"
```

The test project ID is a demo-only ID; the emulator does not connect to or
modify the configured production Firebase project.
