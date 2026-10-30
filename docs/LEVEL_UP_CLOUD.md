# Level Up 3.0.0+22 — accounts, cloud recovery and skip rules

For the later deployment preparation and successful local Atlas connection
check, see [the current deployment handoff](DEPLOYMENT.md). The release-time
Atlas configuration status recorded below describes the earlier implementation
verification before private credentials were supplied.

This release extends the existing Flutter app with an authenticated
Node.js/Express API backed by MongoDB, a durable local synchronization queue,
account isolation and package-level task skip penalties. It preserves the
continuous timeline, three main destinations, guided package builder, nested
groups, English LTR and Arabic RTL/Cairo.

**Atlas is not configured in this workspace.** The repository implementation
uses the official MongoDB driver and is ready for a server-side Atlas URI.
Verification uses a real local MongoDB replica set; it is not a claim that a
production Atlas deployment is live.

## Inspection and implementation plan

Before edits, the repository inspection found Flutter 3.47.7 / Dart 3.13.5,
Provider controllers, schema-3 planner models, Hive compatibility storage and
Android's authoritative AtomicFile under a foreground/headless transaction
lease. No backend, account authentication, Mongo integration, `.env` or deploy
configuration existed. The installed app contained five routines, two existing
challenge instances, three XP ledger entries (15 XP), five templates and a
tomorrow assignment. These are existing data to preserve, not disposable seeds.

The timeline already uses one lazy CustomScrollView with civil-time geometry,
overlap lanes, date anchors, current-time marker and viewport de-emphasis.
Retapping the selected Schedule destination already animates the existing
controller to the current time; ordinary tab navigation retains its viewport.
The header's calendar/Today icon called the same shortcut and was redundant.
The new release removes that icon while keeping Add Activity and the selected
Schedule shortcut. Profile retains settings, history and habit/focus tools.

The builder already separated identity/category, tasks/groups and outcomes.
The missing economic field was a package-level skip cost. Existing package-only
snapshots deliberately had no task skip deductions, so their rules require an
explicit compatibility distinction. Cairo's six actual font weights and the
shared ARB localization delegate were already present. GPL-3.0-only, the
upstream license and “Based on Streak by InlitX” attribution remain intact.

The implementation sequence was: preserve schema/snapshots; add skip rules;
implement server validation/auth and split Mongo collections; add the Flutter
HTTP/session/queue layer; integrate account-aware native storage and Profile;
then verify local migration, API security, recovery, localization and Android.

## Flutter behavior

Profile → Account & sync offers registration, sign-in, status, retry,
sign-out, explicit cloud restore and a user-initiated draft export. Passwords
are sent only to the API and are never persisted by Flutter. Access and refresh
tokens are stored as one encrypted secure-storage value. Private local account
archives also use secure storage, outside Hive, ordinary exports and the native
planner projection. Android OS auto-backup is disabled to avoid restoring an
encrypted cache without its device keystore; account recovery uses the API.

Login fetches the remote state before it activates a cache or sends any local
write. A nonempty account restores its cloud planner; the previous local guest
draft is archived privately and remains exportable to that same account.
An empty account queues the existing local planner for a verified first import.
The UI reports synchronization success only after the server acknowledges it.

Every account-bound foreground planner save adds an immutable checkpoint under
the same native lease as the domain write. A checkpoint contains its stable
mutation ID, expected revision, proposed planner state, locale and IANA time
zone. Checkpoints preserve order, including create → assign → edit. Pure clock
high-water changes do not fill the queue. Background deadline outcomes are
captured from the authoritative native state before any pull or acknowledgement.

Network requests run outside the lease. Before applying their result, the cache
re-reads current state under the lease. An acknowledgement removes only the
matching queue head. Later edits remain visible and queued; a response cannot
overwrite a change made while HTTP was in flight. Lost-response retries reuse
the same mutation ID. JSON map ordering does not change request identity.

Conflicts and rejected late offline actions retain the queue and local draft.
The user can export that draft, retry transient network errors or explicitly
restore cloud data after confirmation. Explicit restore keeps an encrypted
copy of the replaced draft. Automatic conflict merging is not claimed.

Signing out archives the current account's pending state and all private
device tool caches, then installs sanitized guest caches and clears reminders.
Another account cannot access the former account's planner, habits, focus
history, notes, to-dos, profile or pending queue. Signing back in restores the
same owner's retained tool cache and pending queue. A two-phase native swap
marker completes an interrupted account switch on startup before providers or
folder imports run. A missing/mismatched secure session isolates the old cache.
Existing readable auto-backup/shared-folder synchronization is disabled for
account data, preventing cross-account automatic imports or folder exports.
Explicit user exports remain available. Retained Streak habit/focus tools are
device-local and do not claim cloud synchronization in this first version.

The queue has an explicit 256-checkpoint limit and a 1.5 MB state limit. A new
write that exceeds these limits fails visibly before either local authority is
changed; it never truncates pending history. The API accepts at most 2 MiB JSON.

## Packages, nested completion and schema 4

The guided builder now shows three compact outcomes: Completion, Failure and
Skip task. New package tasks have no individual XP fields. Flexible tasks need
no time; scheduled tasks use start/end pickers and derived duration. Categories
retain stable IDs. Groups remain actual parent-child relationships with sibling
order, required descendant progress and no fake group-completion action.

A new `ChallengeTemplate.skipPenalty` is captured in the instance snapshot.
Skipping a leaf deducts the configured package cost once, with the existing
zero-balance floor. Even a zero actual deduction creates an audit event.
Confirmation shows the actual deduction and the required/optional consequence.
Skipping does not cancel the package and is not successful completion. A
required skipped leaf continues to prevent the package completion reward;
deadline failure follows the established rule and remains independently
idempotent.

Schema 4 reads schemas 1–3 without a database reset. Reusable templates migrate
to an explicit package skip penalty of zero until edited. Existing package-only
snapshots retain `skipPenalty:null`, preserving their original no-task-skip-XP
behavior and historical validation. Existing legacy-per-task snapshots retain
their original individual reward and skip rules. Task IDs, records, assignments,
captured trees and prior ledger events are preserved. The earlier schema-3
conversion of future template rewards remains documented in the
[package report](LEVEL_UP_PACKAGES.md).

## Backend and database

The [backend guide](../backend/README.md) contains the complete API contract,
Atlas setup, environment variables, collections, indexes, deployment instructions
and security limits. Source responsibilities are split into configuration,
authentication, validation, domain rules, Mongo persistence and Express routes.

The collections are `users`, `sessions`, `accountSettings`, `routines`,
`routineOverrides`, `routineExclusions`, `categories`, `packageTemplates`,
`challengeInstances`, `completionRecords`, `occurrenceReminders`,
`dailyAssignments`, `xpLedger`, `achievements`, `syncMutations` and
`schemaMigrations`. Task definitions are typed embedded trees within templates
and immutable instance snapshots. Stable parent/task IDs survive template edits.
Application data is reconstructed from structured owner-scoped collections;
it is not stored as a single unstructured application-state document.

Unique owner/event and owner/mutation indexes prevent duplicate XP and request
processing. Multi-collection updates and revision changes run in MongoDB
transactions with snapshot reads and majority writes. Additive initialization
creates validators/indexes without dropping or clearing existing collections.

Email/password auth uses bcrypt cost 12, 15-minute signed JWT access tokens
and rotating opaque refresh tokens. Only refresh-token hashes reach MongoDB.
The server verifies signature, issuer, audience, expiry and revocable session
identity on every private request. Ownership comes from that verified identity;
body user IDs are rejected. Validation, rate limits, body limits, safe errors,
timeouts, strict browser origin lists and HTTPS production checks are included.

Uploaded state is a requested transition. The server independently checks
definitions, hierarchy, prerequisites, immutable snapshots, task availability,
daily assignments and receipt-time deadlines. It derives XP from the verified
action and captured rule, ignoring uploaded XP deltas as authority. The first
import into an empty account replays provable legacy ledger entries against
their records/rules, preserving compatible history; unprovable imports are
rejected while the local draft stays intact. This checks internal consistency
of self-reported legacy history, not whether an offline activity physically
happened.

## Running and configuration

From the repository root:

```powershell
Set-Location backend
npm ci
Copy-Item .env.example .env
# Configure the server-only Atlas URI and a generated JWT_SECRET in .env.
npm run db:init
npm run dev
```

After following the Atlas database-user/network/TLS steps in the backend guide,
configure Flutter with the HTTPS API origin. No database credential belongs in
this command or in Flutter:

```powershell
flutter pub get
flutter run --dart-define=LEVEL_UP_API_BASE_URL=https://api.example.com
flutter build apk --release --dart-define=LEVEL_UP_API_BASE_URL=https://api.example.com
```

For local Android emulator development only:

```powershell
flutter run --dart-define=LEVEL_UP_API_BASE_URL=http://10.0.2.2:3000 --dart-define=LEVEL_UP_ALLOW_INSECURE_API=true
```

`10.0.2.2` reaches the host from the Android emulator. A physical device needs
the host's reachable LAN address and a scoped firewall/listener configuration,
or an HTTPS development endpoint. Plain HTTP is permitted only by the explicit
debug flag and debug Android manifest. Release rejects insecure API URLs.
Without an API define, the app continues in local mode and shows that cloud
sync is unconfigured; it does not invent a working server connection.

Server-side variables are `MONGODB_URI`, `MONGODB_DATABASE`, `JWT_SECRET`,
`JWT_ISSUER`, `JWT_AUDIENCE`, `ACCESS_TOKEN_SECONDS`, `REFRESH_TOKEN_DAYS`,
`HOST`, `PORT`, `NODE_ENV`, `CORS_ORIGINS` and `TRUST_PROXY_HOPS`.
Their meanings/defaults are listed in the backend guide and `.env.example`.

## Verification and remaining setup

Verification on 29–30 October 2026:

| Check | Actual result |
| --- | --- |
| `flutter test --no-pub --reporter expanded` | **722 passed, 3 skipped**, 1m 50s; `test-cloud-full.log` |
| `flutter analyze --no-pub --no-fatal-infos` | **0 errors, 0 warnings**, 8 existing deprecation infos outside the changed cloud/planner work; 9.5s; `analysis-cloud-final.log` |
| Cloud service/controller/session/account UI tests | **27 passed**, including real loopback HTTP contract tests and Arabic 320px / 2× layout |
| Native cache/queue regression file | **11 passed**, including queue limit rollback, worker writes, retry IDs, account isolation, archive retention and numeric normalization |
| Opt-in Flutter → Express → MongoDB recovery test | **1 passed** against real local MongoDB 8.0.17 replica-set transactions |
| Backend `npm test` | **34 passed** using a real temporary MongoDB replica set, including authentication, authorization, validation, migration privileges, transactions, XP retries, routine overrides/prerequisites, import proofs and DST wall-clock deadlines |
| Backend `npm run check` / `npm audit --omit=dev` | **Passed / 0 vulnerabilities** |
| Android `gradlew :app:testDebugUnitTest --no-daemon` | **15 passed**, 0 failures/errors; `native-cloud-final.log` |
| `flutter build apk --release --no-pub` | **Succeeded**, 143.8s; `build-cloud-verified.log` |
| APK identity | **3.0.0+22**, `com.streak.app`, Level Up, minimum SDK 28, target SDK 36 |
| APK size/signature | **100,078,352 bytes** (95.4 MiB); APK v2 signature verified; Android Debug test certificate |

The normal Flutter run skips the opt-in MongoDB test plus the two existing
optional screenshot-seed/host-DST cases. The MongoDB test was executed separately,
not counted as an untested skip. Injected-clock DST/deadline tests run normally.

The end-to-end test uses the actual `CloudHttpApi`, `CloudSyncController`,
`NativeCloudPlannerCache`, `PlannerRepository` and temporary Hive storage, with
a mocked native lease transport and a real Express/Mongo server. It verified:
guest registration and verified first import; 15 XP acknowledged once; two
ordered offline checkpoints surviving a Hive cold restart; network-error
retention and successful retry; sign-out clearing private planner/tool caches;
and a simulated fresh installation with empty local storage and empty archive
vault restoring the same account's routines, renamed category, nested template,
immutable active/completed instances, completion records, Arabic setting and
one 15-XP ledger event. Existing emulator/user data was not cleared for this test.

To reproduce the isolated recovery check, use two terminals:

```powershell
# Terminal 1, backend/ (real temporary MongoDB; first run downloads its binary)
npm run test:serve

# Terminal 2, repository root
$env:LEVEL_UP_TEST_API_URL='http://127.0.0.1:4317'
flutter test --no-pub test/cloud_mongo_integration_test.dart --reporter expanded
```

`npm test`, `npm run check` and `npm audit --omit=dev` run the backend checks.
The local fixture is loopback-only and uses a temporary generated signing key;
it is not a production API. Stop it after testing. On this Windows workspace,
the process-only `FLUTTER_WINDOWS=false` and `FLUTTER_LINUX=false` workaround
avoids unrelated desktop symlink generation during Android plugin setup; no
global developer-mode setting was changed. In PowerShell, set both variables
before `flutter pub get` on this machine. A successful pub-get is required after
dependency changes so Android's generated registrant includes secure storage;
building with `--no-pub` after a failed pub-get can leave that registrant stale.

The Android build preserves Java 17 for the secure-storage plugin, whose source
requires it, while retaining the existing Java 11 targets for legacy modules.
Artifact: [app-release.apk](../build/app/outputs/flutter-apk/app-release.apk).
SHA-256:
`15E2E7A497E6505EA36959B521CBBD2F8D1843198F1F4657A539C0F4663885FD`.
It is test-signed; production distribution requires the owner's release key.
This APK has no API-origin define, so cloud setup is explicitly unconfigured
and local use remains available. The production HTTPS origin must be supplied
when rebuilding for deployment. Final Android verification caught a stale
generated plugin registrant; a successful pub-get with both process flags
regenerated secure-storage registration. The artifact above was rebuilt with
that corrected registration and installed over the retained data.

### Existing-data Android inspection

The final APK cold-started successfully on the Android emulator. Its schema-4
migration preserved every pre-existing saved value, five routines, five
templates, two active instances, three ledger entries and 15 XP. All editable
templates gained skip penalty zero; both captured legacy snapshots retained
their original nullable/captured skip behavior. The date advanced during the
verification window, so ordinary reconciliation added the pending 31 October
selection without a deduction or a duplicate assignment. No data reset was used.

Device inspection verified Schedule with three destinations, Add Activity and
the redundant header icon removed. The existing nested package and category
reopened intact. The builder showed Completion 80, Failure 5 and Task skip 7
with a live −7 XP preview; that temporary edit was discarded, and persisted
values remained 80/5/0. The cloud page accurately showed unconfigured status
with local-use/export actions in English and Arabic. Cairo/RTL and action access
were inspected at 320dp with system font scale 2.0. Only standard AppBar title
ellipsis occurred; no layout overflow or Flutter/AndroidRuntime errors appeared
in the inspected logs. English, Schedule, native display size/density, portrait
and font scale 1.0 were restored.

Evidence:

- [Final preservation comparison](../build/verification/cloud-final-comparison-verified.json)
- [Schedule after upgrade](../build/verification/cloud-upgrade-schedule-verified.png)
- [Three outcomes and live skip preview](../build/verification/cloud-three-outcomes-preview-7-verified.png)
- [English cloud setup status](../build/verification/cloud-unconfigured-en-verified.png)
- [Arabic 320dp / 2× cloud page](../build/verification/cloud-unconfigured-ar-320-font2-verified.png)

`git diff --check` passed, with existing line-ending notices only. The temporary
loopback MongoDB/API fixture was stopped after testing. Physical-device testing
and an actual Atlas deployment are still manual verification steps.

## Changed files

| Area | Files |
| --- | --- |
| Backend | `backend/src/{config,errors,schema,domain,store,auth,app,server}.js`, `backend/scripts/{init-db,local-test-server}.js`, backend tests, package/lock files, `.env.example`, `.gitignore`, README |
| Cloud transport and auth | `lib/services/cloud_{api,models,session_store,sync_controller}.dart`, `lib/features/planner/pages/cloud_account_page.dart` |
| Durable cache and wiring | `lib/services/native_cloud_planner_cache.dart`, `planner_cloud_queue.dart`, `planner_repository.dart`, `lib/main.dart`, `lib/core/database/local_store.dart`, `folder_sync.dart`, `backup_service.dart`, planner shell |
| Package skip rules and visuals | Planner models/controller, package editor/challenge/task pages, shared planner widgets, timeline header |
| Localization and packaging | English/Arabic ARBs and generated delegates, planner localization helper, `pubspec.yaml`/lock, main/debug manifests, Android Gradle compatibility setting |
| Tests and reports | Six new cloud/cache test files, existing planner regression files, README and this report |

Earlier work remains in the shared checkout; it was not reset or replaced.

Manual production steps remain: create/configure the Atlas cluster and dedicated
database user; permit only the backend network; configure server secrets;
initialize the database; deploy the API behind HTTPS; set its real origin in
the Flutter build; and verify `/health`, sign-in and acknowledged writes against
that Atlas deployment. No real credentials were supplied, no paid service was
created and no production deployment is claimed.

This first cloud version has explicit revision conflicts, ordered full-state
checkpoints and bounded payloads. Offline deadline-sensitive actions arriving
late may be rejected by server time and require explicit reconciliation. Server
deadlines catch up on authenticated reads/writes; exact midnight execution is
not promised. Email verification, password reset, account deletion, shared
rate-limit storage for multiple API replicas and a server cron worker are not
implemented. Legacy habit/focus tools remain isolated device-local features.
Only successfully acknowledged cloud data can be restored after local storage
is cleared; unsynced local drafts do not survive uninstall/device data deletion.
