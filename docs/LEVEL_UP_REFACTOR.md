# Level Up 2.7.0 — simplification and daily commitments

Version 2.8.0 adds the [continuous timeline and Cairo typography](LEVEL_UP_TIMELINE.md).
The domain, persistence and deadline rules described here remain in use; the list
screens and APK verification below describe the historical 2.7.0 build.

This report supersedes the storage and UI descriptions for 2.6.x in
[the earlier development record](LEVEL_UP_DEVELOPMENT.md). This remains the same
Streak-derived offline app, Android package `com.streak.app`, with GPL attribution.

## What changed

The source of the classification problem was shared completion handling:
`PlannerItem` represented routines and the temporary view of a challenge task,
and the completion handler awarded its `xp` value for either. The home screen
also mixed both kinds into several dashboard lists. Challenge templates existed
only in a fixed source-code catalog.

Routine definitions now live only in `PlannerState.items`. Challenge definitions
live in reusable templates and in immutable instance snapshots. An occurrence
has an explicit `PlannerTaskKind`, determined by its `challengeId` relationship.
Both the schedule and challenge section derive the same occurrence ID and
completion record. Routine completion and skipping create no XP transactions;
historical rewards remain unchanged. Routine edit/delete commands reject
challenge definition IDs.

Today shows the date, a compact level/XP indicator, Routine, Today's challenge,
and tomorrow's assignment. Schedule retains chronological routine/challenge rows
with a challenge marker. Detailed history, achievements, old habit/focus tools,
and settings remain secondary. The existing dark theme and purple accent remain.

Templates can be created, edited, duplicated, deleted, and persisted. The editor
supports task order, required/optional tasks, sequential steps, targets and units,
dependencies, optional times/reminders, day offsets, duration, task XP/skip rules,
completion reward and failure penalty. Advanced fields expand on demand. Selecting
a template copies its rules into a new instance; later template changes cannot
edit that commitment. Deleting a template does not delete its instances.

## Daily selection and accounting

Each local target date has one `DailySelection`. Tomorrow is enrolled when the
feature first runs; migration does not charge pre-feature days. The default
selection deadline is 23:59 today and the initial missed-selection penalty is
5 XP. Both are editable in Settings and disclosed in selection/confirmation.
Closed records retain their frozen UTC deadline and configured penalty.

Only one package may be selected for tomorrow before its deadline. The assignment
references the immutable instance and preserves the routine. Active commitments
have no ordinary cancellation/deletion action. Individual tasks can be skipped
after a confirmation showing the configured penalty.

Reconciliation catches up every target date since enrollment. Each miss uses
`missed_selection:YYYY-MM-DD`; task completion, skips and package outcomes also
have stable idempotency keys. Outcomes and immutable ledger entries are saved
together. XP is derived from the ledger and is floored at zero; a zero deduction
still has an audit entry with the configured penalty. Misses remain unacknowledged
until the next-open notice is acknowledged. Their dates appear in XP history.

The controller freezes its clock per command and preserves an observed-time
high-water mark. Reopening, retries and moving the clock backward cannot reopen
a recorded deadline or repeat an outcome. Selection date keys prevent timezone
or daylight-saving changes from creating a second outcome for the same date.
An offline app cannot establish trustworthy external time if a user deliberately
changes the device clock before a deadline has ever been observed.

## Persistence and Android background work

Planner schema 2 reads schema 1 without rewriting historical identities, records,
XP or challenge snapshots. Templates, assignments, settings and deadline outcomes
are additional fields. Unsupported/corrupt schemas fail visibly.
Existing future commitments are adopted into the matching daily selection;
legacy overlapping instances remain intact. A deadline grace of one microsecond
beyond a legacy commitment's creation time avoids invalidating a commitment made
after the newly introduced deadline.

Android migrates the Hive planner aggregate once to the existing native AtomicFile
document, marked `canonicalPlanner: true`. Before migration an older notification
mirror cannot replace Hive. After migration the AtomicFile planner state is the
authority; Hive's `levelUpState` is a foreground backup/compatibility mirror.
The worker never opens Hive. Interrupted native writes use AtomicFile recovery.
An unreadable authoritative file is not silently reset.

The existing native mutex now covers every foreground read/modify/write and the
entire headless reconciliation. Controllers load the latest state after acquiring
it. Foreground saves commit native state before refreshing the Hive mirror;
startup recovers a stale mirror. Backup restore uses the same lease and exports
refresh their mirror. Reminder side effects run after the domain lease releases.

The existing WorkManager worker runs the same injectable-clock domain engine,
commits overdue deadlines/ledger/package outcomes atomically, then refreshes the
reminder horizon. Notification failures do not discard accounting. A delayed
one-time request targets the pending selection deadline, with the existing
twelve-hour periodic job and boot/timezone/package-update receivers as fallbacks.
Startup, resume and the visible app's minute timer reconcile too. Android can
delay work under battery restrictions; no exact 23:59 execution is promised.
See [Android's WorkManager timing documentation](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work).

## Arabic, English and reuse

Arabic and English use the existing generated ARB delegates and Flutter Material,
Widgets and Cupertino localization. Arabic is now an enabled shipped language;
all English ARB message keys have Arabic translations. Flutter supplies RTL/LTR
directionality to navigation, forms, menus, dialogs and date/time pickers.
Planner labels, validation, ledger descriptions, achievements and notification
actions are localized; dates/numbers use `intl`. Numeric forms accept Western,
Arabic and Persian digits. Stored enum values, IDs, dates and user-entered content
remain independent of the interface language. Settings switches the language
without rebuilding the planner state.

Reused components include Provider, Hive CE and existing backups, Streak theme
tokens/fonts, generated localization, native sound selection/preview, notification
scheduling/actions, recurrence/override logic, and the existing Android gate and
WorkManager bridge. No cloud service, account, Flutter runtime dependency or new
Android permission was added.

Main changed files:

- `lib/features/planner/data/planner_models.dart`,
  `lib/features/planner/state/planner_controller.dart`
- Planner shell, challenge/task/routine/reminder UI, new package editor and settings
- `lib/features/planner/l10n/planner_l10n.dart`, English/Arabic ARBs and generated files,
  `lib/core/i18n/app_locale.dart`
- New `lib/services/planner_repository.dart`; existing background/sync/bridge,
  reminder and notification services; `lib/main.dart`
- Existing backup restore/export integration and native planner projection/worker
- Planner domain, persistence, repository, localization and UI tests; native tests
- `pubspec.yaml` version 2.7.0+19 and documentation; no new package dependency

## Verification

Commands executed from the repository on Windows:

```powershell
$env:FLUTTER_WINDOWS='false'
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' gen-l10n
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' test --no-pub --reporter expanded
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos
$env:JAVA_HOME='C:\Users\promj\.jdks\jbr-17.0.14'
& '.\android\gradlew.bat' -p android :app:testDebugUnitTest --console=plain
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' build apk --release --no-pub
```

`FLUTTER_WINDOWS=false` is process-local, allowing Android plugin resolution on
this machine without enabling Windows Developer Mode. It does not change global
Flutter configuration.

- Full Flutter suite: **634 passed, 2 existing skips**, 1m46s
  (`test-refactor-verified.log`). The skips are the optional demo screenshot seed
  and the host-specific daylight-saving test; the new injected DST tests run.
- After the last localized conflict/prerequisite display and skip confirmation
  changes, **18 relevant UI/localization/editor/repository tests passed**
  (`test-refactor-ui-final.log`).
- The final package-order and persistent challenge-marker display changes passed
  **14 UI/localization/editor tests** (`test-levelup-final.log`); final targeted
  analysis of planner, repository, background, bridge, sync, notifications and main
  reports **no issues**.
- Full analysis: **no errors or warnings**, 8 existing legacy deprecation infos
  (`analysis-refactor-verified.log`).
- Android unit tests: **15 passed**, 0 failures/skips (8 planner gate/projection,
  7 existing widget payload tests; `native-refactor-final.log` and XML reports).
  The final serial repeat completed successfully in 29 seconds
  (`native-refactor-verified.log`, cached checks up to date).
- Localization generation succeeds; **0 missing Arabic keys** across all 1,453
  English messages. Other pre-existing partial languages and the upstream
  Ukrainian ICU warning remain outside the requested English/Arabic scope.

New clock-based tests verify deadline equality, multi-day catch-up, restart and
retry idempotency, zero-balance auditing, funded deductions, settings changes,
rollback, DST/timezone transitions and legacy future commitments. Repository tests
verify native migration/recovery, concurrent-controller edits, headless penalties
without Hive writes, accounting checkpoints before plugin work, and persisted
accounting despite notification failure. Existing recurrence, reminder, backup,
sequential-step and package lifecycle regressions also pass.

Earlier integration runs caught transient test/helper compilation errors while
parallel edits were finishing; those were corrected before the passing run. One
release rebuild hit a Windows `classes.dex` file lock during overlapping Gradle
work. The subsequent serial release build succeeded. Logs retain both outcomes.

Final release artifact:

- `build/app/outputs/flutter-apk/app-release.apk`, **2.7.0+19**, 97,695,230 bytes
  (Flutter reports 93.2 MB).
- SHA-256: `CF96EF519FD9D0C5AA4A5E4C61140EFD2EA05CE209B3A9EB4A4C953D54B9BF86`.
- Final `flutter build apk --release --no-pub`: success, **73.1 seconds**
  (`build-levelup-final.log`).
- `apksigner verify --verbose --print-certs`: v2 verification passes; local
  **Android Debug** signer. `aapt dump badging`: Level Up, `com.streak.app`,
  versionCode 19, min SDK 28, compile/target SDK 36.

Emulator verification uses the existing `emulator-5554` read-only test AVD, updating
the previous APK with `adb install -r`; no user database was reset. Details of the
completed UI and worker checks are recorded below.

- Upgrading from 2.6.1 retained **15 XP**, three historical ledger entries, routine
  IDs and the active Steady start instance. Completing the pending ordinary
  Snooze action QA activity through the UI kept XP and the ledger unchanged.
- Created **Hard Workout**, difficulty Hard, three tasks (Warm-up, Running,
  Stretching), two warm-up steps, completion reward 80, Running skip penalty 7
  and other skip penalties 5. Saved and reopened the app; definitions persisted.
- Confirmed that package for October 30. The assignment referenced its instance,
  displayed 0/3 tasks, and left the routine definitions exactly unchanged.
- Switched Arabic/English on the device. All four main destinations, settings,
  routine/package/task forms and the time picker displayed Arabic RTL and then
  English LTR. Comparing canonical state before and after language switching
  showed exact equality for routine definitions, overrides, records, instances,
  ledger, templates, selections and rules. User-entered Hard Workout stayed intact.
- Returned Home, killed the verified UI process without force-stop, and sent the
  existing TIMEZONE_CHANGED receiver an explicit test broadcast **without changing
  the clock or timezone**. Headless process 5957 returned WorkManager SUCCESS at
  **18:08:45**. `lastRefreshAt` advanced from 1793286201399 to 1793286525452;
  the complete domain core remained identical (SHA-256
  `9729DD71C38BFFEFAB6F1CACEB41BCF87A1BCC7F01F7FA57CFA12D5130B8EA07`), as did
  all seven Hive checksums. This verifies the real headless checkpoint path;
  overdue penalty amounts/idempotency were tested with injected clocks, rather
  than claiming a midnight execution test on Android.
- Installed the final APK again with `adb install -r`. The installed `base.apk`
  hash exactly matches the delivered hash above; Android reports 2.7.0 / code 19.
  Reopening retained 15 XP, all three ledger entries, the original routine
  definitions/Steady start instance, the custom template snapshot and one October
  30 assignment. The package displays Warm-up → Running → Stretching in saved
  order. The skipped challenge remains marked by a purple trophy in Schedule.
  The emulator was left on English Today.

Evidence is in ignored `build/verification/refactor-*.png`, corresponding JSON
snapshots, Hive checksum files and `refactor-worker-evidence.txt`. Stable screenshots
were inspected; initial screenshots caught mid-navigation were recaptured.
`refactor-ui-evidence.txt` records the final install, domain comparisons and order.

## Remaining limits

Background execution remains subject to Android force-stop, hibernation and battery
policy. Foreground reconciliation guarantees eventual correction when the app is
opened. Emulator checks do not establish audible playback or every manufacturer's
battery behavior on physical devices. Existing arbitrary local audio-file import
remains outside this refinement; bundled and Android system sounds are available.
The local APK uses a test signing key; a production keystore is still required
for a production-signed release.
