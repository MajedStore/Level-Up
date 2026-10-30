# Level Up development record

**Historical 2.6.x record.** Version 2.7.0 changes task accounting, package
management, localization and Android planner authority. See the
[current refactoring report](LEVEL_UP_REFACTOR.md) for those changes and verification.

The resubmitted brief was identical, so follow-up work continued from the existing
implementation. Version **2.6.1+18** adds a twelve-hour Android reminder refresh
worker using a disposable notification projection, serializes foreground/background
platform scheduling with a native mutex, and rejects reminders or snoozes beyond
challenge end boundaries. The foreground Hive aggregate remains the only authority
for task and XP history. The follow-up verification section records current results;
the original 2.6.0 baseline results are retained separately below.

Based on Streak by InlitX. Upstream revision: `23b32102a394228d528403c9f6d48dccc9eb0316`.
The GPL-3.0-only license and additional attribution terms remain in the repository.

## Repository audit and implementation plan

The original app uses Provider controllers, Hive CE boxes containing serialized maps,
Material themes with `AppTokens`, generated ARB localization, and a central notification
service. Existing habits support recurrence, amounts, checklists, focus, widgets, and
historical statistics. Existing to-dos support recurring deadlines and steps. `DayPlan`
combines habits and timed to-dos but has no challenge lifecycle, immutable per-occurrence
records, overnight planner recurrence, or auditable XP ledger.

Reuse the existing app bootstrap, themes/fonts, Provider, Hive, date formatting,
settings, backup archive, time controls, Android notification plugin and sound picker.
Keep the original habit/focus tools available from Profile. Extend the app with:

1. An additive versioned planner aggregate in the existing Hive settings box. Store
   schedule definitions, occurrence exceptions, task records, challenge snapshots,
   ledger, and achievements together so a single Hive write commits a domain action.
2. Deterministic recurrence and challenge schedule projections, explicit lifecycle
   rules, ordered steps/dependencies, amounts, idempotent XP events, and clock-driven
   deadline evaluation. Base commitments remain independent from challenges.
3. Four main destinations: Today, Schedule, Challenges, and Profile; real editable
   persistent data with empty/error states and confirmations for penalties/deletion.
4. Existing Android notifications extended with planner reminders, stable IDs,
   sound/vibration controls and exact-alarm permission fallback.
5. Unit, persistence, widget and reminder tests, static analysis and Android APK build.

Planner occurrence records require a separate domain model from legacy habits/to-dos:
their immutable challenge snapshots, ledger events and per-occurrence outcomes cannot
be represented safely by the original mutable `Todo.done` and next-date advancement.
They share the existing persistence engine rather than introducing another database.

## Environment inspected

- Flutter 3.47.7 stable / Dart 3.13.5; project SDK constraint ^3.9.2.
- Android SDK/build tools 36, configured JDK 17, accepted Android licenses.
- Existing Android min SDK 28, compile/target SDK 36, AGP 8.9.1, Kotlin 2.1.0.
- Existing dependencies retained. Flutter SDK resolution updates its pinned transitive
  packages; no new runtime dependency is required by the planner.
- Windows Developer Mode is disabled. For Android-only commands use the process-local
  `FLUTTER_WINDOWS=false` override to avoid irrelevant Windows plugin symlink creation.
- No connected Android device was present at audit time. Device notification delivery
  and OEM battery restrictions require Android runtime verification.

Verification outcomes and remaining limitations are recorded after implementation.

## Implemented data and product decisions

- Schema 1 is an additive `levelUpState` value in the existing Hive `settings` box.
  Existing habits, to-dos, focus sessions, notes and preferences are not migrated
  destructively. Original tools remain accessible from Profile.
- Commands operate on detached copies and serialize writes. A task outcome, XP event,
  achievement and package transition commit in one write. A failed write rolls back.
  Unknown schemas or inconsistent histories produce an error without resetting data.
- Recurrence uses local calendar dates, including selected weekdays and every N
  weeks. Overnight blocks appear on both intersected days with one occurrence ID.
  Overrides retain their original ID when moved; regeneration cannot duplicate them.
- Challenges project additional blocks from immutable activation snapshots. The base
  schedule stays intact. Mandatory tasks and all their required steps/amounts must
  be complete before the deadline. Skipped mandatory tasks prevent success; the
  package fails at its deadline. There is no cancellation or emergency bypass.
- XP is the sum of immutable ledger entries. Each event has one idempotency key.
  Penalties floor the balance at zero and record the actual deduction along with the
  configured rule. Initial package failure penalties are explicitly zero.
- Level thresholds use `100 * (level - 1) + 50 * (level - 1) * (level - 2) / 2`.
  Streaks mean days with a qualifying completed task, not perfect days.
- Three reusable packages are available; none is automatically active. Their rules,
  tasks, steps, dates, schedule conflicts and penalties are disclosed before starting.
- Manual ZIP backups and existing configured automatic backups include the planner
  aggregate. Restore with Replace restores the captured planner as a unit. A legacy
  backup without planner data leaves current planner data intact. Merging two
  nonempty planner histories is refused before any content changes, because an
  ordinary preference merge could corrupt ledger and challenge consistency.
- The Dart package name and Android application ID (`com.streak.app`) are retained
  for source compatibility and supported same-signature upgrades. Launcher labels
  and product UI are Level Up, version `2.6.1+18`. An official Streak installation
  cannot be updated with a differently signed local APK; export/import its backup.
- No new runtime packages, account, analytics, advertising or cloud service added.
  GPL and additional attribution notices are preserved, registered as bundled
  licenses and displayed in Profile/About.

## Android build compatibility changes

The installed Flutter enforces newer Android tooling than upstream's initial
configuration. Gradle was updated from 8.12 to 8.14.3 (with its published SHA-256),
AGP from 8.9.1 to 8.13.2, and Kotlin/Compose from 2.0/2.1 to 2.2.20. The existing
Android API range (28–36) is unchanged. Flutter added its compatibility flags
`android.builtInKotlin=false` and `android.newDsl=false`.

NDK 28.2.13676358 was missing and installed with:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe" sdk install 'ndk/28.2.13676358'
```

The installed Android CLI's deprecated `sdkmanager` wrapper split the old
semicolon package syntax incorrectly; using the native CLI installed the required
NDK successfully. The upstream Cupertino transition import was updated for Flutter's
library reorganization. Flutter's SDK pins updated five transitive lockfile entries.

The first release attempt exposed AGP 8.11.1's lint parser failing on installed
fractional API metadata (`For input string: "36.1"`). AGP 8.13.2 supports API 36.1
metadata, so the build plugin was updated; release lint was not disabled.
See the [official AGP compatibility notes](https://developer.android.com/build/releases/agp-8-13-0-release-notes).

The next release attempt revealed `home_widget`'s dynamic `glance-appwidget:1.+`
selecting an API-37/AGP-9.1 alpha in its library variant, while the app already pinned
Glance 1.1.1. The same stable Glance choice now applies across all modules, together
with the existing WorkManager 2.9.1 choice. This prevents dynamic plugin versions
from bypassing the app's compatibility pins. No Pub cache files were modified.

## Reminders and permissions

Enable a reminder to request Android notification access. Precise alarm access is
optional, requested only through Profile's Precise reminders action. Without it,
notifications use the supported inexact scheduling mode and expose that status.
The unconditional `USE_EXACT_ALARM` permission was removed. Existing boot receivers
restore pending schedules after reboot/package replacement.

Notification IDs are deterministic and collision-safe; edits, completion, deletion
and package endings reconcile pending reminders. Per-occurrence or per-series
reminder settings are independent of captured challenge reward rules. Notification
actions open the app for completion/prerequisite checks or snooze for 10 minutes.

Two original CC0 chimes and Android notification tones are selectable with preview.
Sound/vibration preferences have separate notification channels; Android users may
override channel behavior. Missing tones fall back to the system default. Arbitrary
local audio-file selection is not implemented.

The reminder projection is a rolling 28-day window refreshed on launch, resume,
data changes and Android WorkManager's periodic twelve-hour job. Boot, clock and
timezone changes also enqueue a refresh. The worker reuses the Dart recurrence
engine from a detached native snapshot and writes notification metadata only; it
never opens Hive or changes task outcomes, package states or XP. A shared native
lease covers scheduling and publication so stale background work cannot overwrite
a newer foreground refresh. Explicit data wipe clears the mirror and cancels work.
Jobs are disabled when no live reminder definitions remain.

This removes the previous requirement to reopen the app within 28 days. Android
can still defer background jobs, revoke permissions or suppress work after an
explicit force-stop, app hibernation or manufacturer battery restrictions. The
28-day buffer tolerates normal job delays; no Android scheduling API guarantees
indefinite delivery when the system or user blocks the application.

The preserved habit/focus/backup features retain their existing optional permissions
(steps, running focus service and external backup storage). No release internet
permission was added.

## Local commands

From the project root in PowerShell:

```powershell
$env:FLUTTER_WINDOWS = 'false' # Android-only workaround; does not change global Flutter settings
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub --reporter expanded
flutter build apk --release --no-pub
flutter devices
flutter run -d <android-device-id>
```

Use Profile → Settings & data management for theme, week start, export and restore.
Create base commitments in Schedule, create standalone tasks from the add menu,
and inspect a package in Challenges before confirming activation.

No production signing key is stored in this repository. The inherited release
configuration falls back to the local debug signing key when `android/key.properties`
is absent; configure your own keystore for distribution and consistent upgrades.

## Important implementation files

| Area | Files |
| --- | --- |
| Models, recurrence, schema, levels | `lib/features/planner/data/planner_models.dart` |
| Reusable inactive package definitions | `lib/features/planner/data/challenge_catalog.dart` |
| Serialized domain commands and persistence | `lib/features/planner/state/planner_controller.dart` |
| Main navigation, Today, Schedule, Profile | `lib/features/planner/pages/level_up_shell.dart` |
| Forms, task inspection and package lifecycle UI | `lib/features/planner/pages/planner_editor_page.dart`, `planner_task_page.dart`, `planner_challenges_page.dart` |
| Shared UI and independent task reminders | `lib/features/planner/widgets/` |
| Reminder projection, reconciliation, snooze and native delivery | `lib/services/planner_reminder_schedule.dart`, `planner_sync.dart`, `notification_service.dart` |
| Backup compatibility and reload integration | `lib/services/backup_service.dart`, `backup_archive.dart`, `lib/features/habits/state/habits_controller.dart`, `lib/features/settings/settings_actions.dart` |
| Bootstrap, product defaults, attribution | `lib/main.dart`, `lib/app/streak_app.dart`, `lib/features/settings/state/settings_controller.dart`, `lib/features/settings/pages/about_page.dart` |
| Android labels, permissions and sounds | `android/app/src/main/AndroidManifest.xml`, `kotlin/com/streak/app/SoundBridge.kt`, `res/raw/`, `res/values/strings.xml` |
| New tests | `test/planner_domain_test.dart`, `planner_persistence_test.dart`, `planner_reminder_test.dart`, `planner_ui_test.dart`, `planner_editor_test.dart`, `widget_sync_lifecycle_test.dart` |

Existing generated localization and desktop plugin registrants are generated files,
not a second implementation of the planner. The new planner strings are English;
the existing localization system and translations remain available to legacy tools.

## Baseline verification: 2.6.0 (29 October 2026)

| Command/check | Actual result |
| --- | --- |
| `flutter pub get` with process-local `FLUTTER_WINDOWS=false` | Exit 0; dependencies resolved |
| `dart format` on all changed Dart files | 30 files checked, 0 changes on final formatting run |
| `flutter analyze --no-pub --no-fatal-infos` | Exit 0; no errors/warnings, 8 existing legacy deprecation infos |
| `dart analyze lib/main.dart lib/services/planner_sync.dart` | Exit 0; no issues |
| Targeted planner/domain/reminder/UI/editor analyses | Exit 0; no issues |
| `flutter test --no-pub --reporter expanded` | Exit 0; **590 passed, 2 skipped**, 1m 53s |
| Domain + persistence targeted run | 42 passed (36 domain, 6 actual-Hive/backup tests) |
| Reminder targeted run | 14 passed, covering generation, stable IDs, duplicates, cancellation, edits, denial, fallback and UTC snooze persistence |
| UI/editor targeted runs | 6 main UI + 2 recurring-editor tests passed, including large text |
| Focus/timer lifecycle regression | 20 passed; pending widget timers are cancelled before test-store shutdown |
| `flutter build apk --debug --no-pub` | Exit 0; APK built and installed on Android emulator |
| `flutter build apk --release --no-pub` | Exit 0; **92.1 MB** release APK, 203.9s after toolchain fixes; release lint enabled |
| `apksigner verify --verbose --print-certs` | Exit 0; APK signature verified (local Android Debug certificate) |
| `aapt dump badging` | Exit 0; Level Up 2.6.0+17, min API 28, target/compile API 36; no INTERNET or USE_EXACT_ALARM permission |
| `adb install -r .../app-release.apk` and `am start -W` | Exit 0; exact release artifact installed over debug and launched successfully |

The two upstream skips are the opt-in screenshot demo seed (no `DEMO_OUT`) and
a host-timezone DST check that does not apply to this host. No planner tests skipped.
The final full run followed the reminder-edit and asynchronous fixture fixes.

Baseline APK retained before rebuilding 2.6.1:

```text
C:\Users\promj\Desktop\LEVEL UP\build\verification\level-up-2.6.0-baseline.apk
```

SHA-256:
`D545755987C4D94B03A3E881BBCCF45DCC98C8A7C725B32593ABF838B1A7407B`.

The artifact uses local test signing because no production keystore was supplied.

The Android emulator verified an empty real Today screen, ordinary task creation,
completion awarding 10 XP, removal of the completion action, and retention after
force-stop/relaunch. A recurring University block was created for Monday, Tuesday
and Thursday; Thursday's positioned block and Friday's empty schedule were inspected.
Emulator test entries are user actions in the test device, not seeded production data.

The emulator also verified all four destinations, full package rule disclosure,
explicit activation, a scheduling conflict without losing University, rejection of
completion with 0/3 required steps, an explicit 5-XP skip confirmation, exactly one
−5 ledger entry and balance **10 → 5**, and retained skipped history after another
force-stop/relaunch. Flutter/Android error logs were empty during those flows.
Screenshots are in `build/verification/`; the portable accessibility-driven helper
is `scripts/android_smoke_test.ps1`.

The **exact final release APK** was then installed over that debug build. The 5-XP
balance, University base activity, active package and skipped record all survived.
The new Profile notification action produced the real Android permission prompt;
Allow granted `POST_NOTIFICATIONS`. Android alarm records confirmed actual future
scheduled receiver alarms using inexact fallback while exact access was absent.

Profile's optional Precise reminders action opened native Alarms & reminders
settings. Granting access rescheduled the pending reminder with a zero-width exact
alarm window. At **15:20 on 29 October 2026**, the University notification actually
delivered, with **Complete / review** and **Snooze 10 min** actions. The observed
delivery used exact access; approximate delivery timing was not independently timed.
The balance stayed 5 XP and runtime error logs stayed empty. At that baseline,
notification-action execution and reboot delivery had not yet been checked. Sound
audibility and physical-device battery restrictions remain hardware QA requirements.

Evidence includes `build/verification/release-permission-prompt.png`,
`release-permissions.png`, `release-exact-permissions.png`, `reminder-delivered.png`,
`release-alarm-evidence.txt` and `release-notification-evidence.txt`.

Unit/widget tests do not establish physical-device notification sound, Doze behavior,
reboot delivery or compatibility with every Android manufacturer. Those remain device
QA requirements. Existing unsigned/debug-signed builds do not establish a supported
upgrade over an official differently signed Streak APK.

## Follow-up verification: 2.6.1+18 (29 October 2026)

The planner Hive schema remains version 1. `validUntil` is derived occurrence
metadata, not a persisted schema change. The new native
`files/levelup_reminder_projection.json` is a disposable scheduling mirror; only
foreground code publishes planner snapshots, and workers can update its notification
bookkeeping only. Existing backups restore the same canonical Hive aggregate and
rebuild the mirror on refresh. No new Flutter dependency or Android permission was
added; the worker uses the existing WorkManager 2.9.1 dependency.

New important files:

- `lib/services/planner_background.dart`: pure shared reminder projection and
  headless entrypoint body, without Hive initialization.
- `lib/services/planner_refresh_bridge.dart`: auxiliary-only storage and serialized
  foreground scheduling leases.
- `android/app/src/main/kotlin/com/streak/app/PlannerReminderWorker.kt`: periodic
  refresh plus boot/clock/timezone receiver.
- `PlannerReminderBridge.kt`, `PlannerRefreshGate.kt`, `PlannerProjection.kt` in
  that same native directory: atomic mirror, shared scheduling lock and owner checks.
- `test/planner_background_test.dart` and native `PlannerRefreshTest.kt`:
  background safety, regeneration, concurrency, cancellation and lease regressions.

`notification_service.dart`, `planner_sync.dart`, `main.dart`, settings data wipe,
the occurrence model/controller and reminder builder were extended to integrate
these services. Snooze and reminder times now respect package deadlines and early
completion, including old delivered notifications.

| Command/check | Actual result |
| --- | --- |
| `flutter test --no-pub --reporter expanded` | Exit 0; **611 passed, 2 existing skips**, 1m 48s |
| `dart format --output=none --set-exit-if-changed` on changed Dart files | Exit 0; 33 files, 0 changes |
| `flutter analyze --no-pub --no-fatal-infos` | Exit 0; the same 8 legacy deprecation infos, no errors/warnings |
| `dart analyze lib/services/planner_sync.dart lib/services/notification_service.dart lib/main.dart` | Exit 0; no issues |
| Background-only tests, with no Hive initialized | 17 passed |
| Expiry domain/reminder targeted tests | 54 passed (38 domain, 16 reminders) |
| `.\android\gradlew.bat -p android :app:testDebugUnitTest --console=plain` | Exit 0; **14 passed**, including 7 new native tests, 24s final run |
| `flutter build apk --release --no-pub` | Exit 0; **92.1 MB**, 141.6s, release lint enabled |
| `apksigner verify --verbose` | Exit 0; v2 signature verified, same local test signing |
| `aapt dump badging` | Exit 0; Level Up 2.6.1+18, API 28–36; no new permission or INTERNET permission |
| `adb install -r` and `am start -W` | Exit 0; existing data retained on upgrade |

The first full native unit run exposed two stale upstream widget tests expecting
seven aligned dates. Current Dart payloads export a future buffer, and native
calendar-week selection intentionally retains thirteen dates. Only those tests
were corrected to verify the actual history/future boundaries and aligned habit
arrays; production widget behavior was unchanged. All fourteen native tests then
passed. Concurrency review also added a regression for equal channel strings with
different object identities, ensuring mutex releases use the original native owner.

The upgraded release created its mirror and registered a periodic job with a
twelve-hour initial delay. With the UI closed and its process killed without
force-stop, an explicit timezone-change receiver test (without changing the device
clock) started a new background process. WorkManager reported **SUCCESS at 16:58:13**.
The mirror's `lastRefreshAt` advanced; all seven Hive file SHA-256 checksums and the
canonical mirrored planner state remained identical. Evidence is in
`build/verification/followup-worker-evidence.txt` and the corresponding before/after
hash/projection files. Tests separately regenerated reminders beyond the original
28-day window; a month-long elapsed-time device run was not performed.

Current release APK:

```text
C:\Users\promj\Desktop\LEVEL UP\build\app\outputs\flutter-apk\app-release.apk
```

SHA-256:
`F4F765E51227D40AAB61271A4BA3C1597AF9B875B521970707D21FFE3BD5A289`.

Runtime action and reboot checks on that exact release also passed:

- The warm **Snooze 10 min** action at 17:05:16 created an exact 17:15:16 alarm;
  XP stayed 5.
- A University notification delivered at 17:08 while the UI process was absent.
  After killing the native receiver process too, **Complete / review** cold-launched
  the app and awarded 10 XP once. Today showed 15 XP and the ledger contained exactly
  one University completion event.
- A full emulator reboot restored the pending snooze alarm and all twelve planner
  receiver alarms, without duplication (12 before, 12 after). The boot worker
  reported SUCCESS at 17:11:08, before a manual UI launch.
- All seven Hive checksums were unchanged across reboot/background recovery.
  Reopening normally still showed 15 XP, with no repeated completion reward.
- The snoozed notification was observed posted again after reboot at its scheduled
  time. The UI had been reopened for data-retention inspection before it was due;
  boot-worker execution and restored alarms were verified before that UI launch.
- No Flutter or Android runtime errors were observed during these flows.

Evidence is in `build/verification/followup-actions-reboot-evidence.txt`,
`followup-snooze-warm.png`, `followup-cold-completed.png`, `followup-after-reboot.png`
and the before/after alarm, projection and Hive checksum files.

Remaining limits are OS force-stop/hibernation/battery policies, physical-device
audio and manufacturer QA, and optional local audio-file selection. Built-in CC0
chimes and system tones remain available. A month-long real-time unattended run was
not performed; deterministic window-extension tests and actual headless worker
execution were verified. Production signing still requires the user's keystore.
