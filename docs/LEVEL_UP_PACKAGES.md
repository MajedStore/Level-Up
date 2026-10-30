# Level Up 2.9.0+21 — navigation and challenge packages

The main app now opens on Schedule with three destinations: Schedule,
Challenges and Profile. Challenge creation uses a guided builder with custom
categories, flexible or scheduled tasks, real nested groups, and one package
completion reward and failure penalty.

This report supersedes the Today/Schedule duplication described in the
[2.8 timeline report](LEVEL_UP_TIMELINE.md). The established routine, daily
assignment, deadline and Android persistence architecture remains documented in
the [core refactoring report](LEVEL_UP_REFACTOR.md).

## Screens and navigation

Schedule contains the existing continuous timeline, compact XP summary and
today's challenge section. There is no separate Today destination. Challenges
contains reusable templates, tomorrow's assignment and immutable instance
history. Profile retains settings, XP history and the existing secondary tools.

Selecting Schedule from another tab restores its existing browsed position.
Tapping Schedule while it is already selected smoothly returns that same
timeline to today's current-time position. The shell uses
`PlannerTimelineNavigation` to call the existing timeline state; it retains the
same scroll controller and performs no planner refresh or completion command.
Repeated taps during the movement share the in-progress return operation, and a
tap at the current position does not start another scroll. The date/time anchor,
continuous-day range, overlap rendering and routine edit routes remain intact.

The challenge section on Schedule uses the same `ChallengeTaskNode` tree as the
instance page, filtered to today's pending leaves. Groups show date-specific
required progress and reveal their children when opened. Every leaf opens its
original task occurrence rather than creating a second completion record.

Sources: [shell](../lib/features/planner/pages/level_up_shell.dart),
[timeline](../lib/features/planner/widgets/planner_timeline.dart),
[challenge views](../lib/features/planner/pages/planner_challenges_page.dart).

## Guided builder

The package editor has three stages: identity/category, task tree, and
reward/review. Category chips select a saved category; focused dialogs and a
management sheet support creation, renaming and deletion. Package categories
are user data with stable IDs. Easy, Medium and Hard are no longer required
choices or displayed as package categories.

Add task and Add group are separate labeled actions. A group opens its own
children with a breadcrumb and parent action. Children can be edited, deleted
or moved among their siblings. A subtle leading line marks the group context.
Empty groups are brought back into focus for correction before the builder
can proceed. The review stage shows the task hierarchy and package-level XP
fields with distinct reward and penalty icons. A persistent primary action
advances the builder or saves the package.

Ordinary task creation asks for a name and one of two icon tiles:

| Task type | Relevant controls |
| --- | --- |
| Flexible | Name and optional reminder; no required time or duration |
| Scheduled | Name, start and end time pickers, compact time preview, optional reminder; duration is derived |

Equal start/end times are rejected. An end time earlier than the start crosses
midnight, with a visible next-day cue. Overlapping scheduled tasks require an
explicit save confirmation. Individual task reward/penalty, duration in days,
day lists, multiline sequential-step entry, description, target/unit and
required-completion controls are absent from normal task creation. New package
duration starts at one day and expands internally when an overnight task needs
the following day. Existing saved conditions remain
captured and visible in a read-only disclosure when editing an older task.

Reminders reuse the existing optional bell flow, permission request and denied
permission message. No notification permission is required merely to create a
task or package.

Source: [package editor](../lib/features/planner/pages/planner_package_editor_page.dart).

## Domain model and completion

The model stores tasks as an ordered flat list with explicit task IDs,
`ChallengeTaskType` (`flexible`, `scheduled`, `group`) and nullable `parentId`.
`childrenOf(parentId)` derives each ordered sibling list. This is a persisted
parent-child tree; existing sequential steps remain separate legacy task
conditions.

| Concept | Ownership and behavior |
| --- | --- |
| Reusable template | Editable identity, category, ordered task tree, package reward and failure penalty |
| Instance | Detached snapshot captured at assignment, lifecycle dates and status |
| Leaf occurrence | Existing instance/task/date ID and completion record |
| Group | Derived required-descendant status and progress; no independent completion record or reminder |
| Routine activity | Existing independent routine identity and recurrence; no challenge XP |

A group completes only when all its required child nodes are complete, including
required children in deeper groups. Package progress counts the corresponding
required descendant leaf occurrences. Optional branches do not block package
completion. Groups expose no action that completes their children. Their
collapsed headers show progress such as 1/2, and expanding them displays the
actual saved leaves.

Validation rejects duplicate IDs, missing parents, a leaf used as a parent,
parent cycles, empty groups, groups without a required child, invalid leaf time
rules, and packages without required leaves. Existing prerequisite validation
continues to reject missing/cyclic dependencies. Deleting a branch from a
template removes its descendants and cleans remaining references to that
branch; assigned instances retain their independent original snapshots.

The preview displays the actual derived deadline date and local midnight time
beside its reward and failure penalty before the assignment confirmation. This
makes an overnight package's completion window visible without exposing a
duration-in-days control.

The controller still serializes mutations, evaluates deadlines before accepting
late completion and uses stable ledger idempotency keys. A skipped required
leaf prevents completion; failure is processed under the existing package
deadline rule. There is no new immediate package-failure action or punishment.

Sources: [models](../lib/features/planner/data/planner_models.dart),
[controller](../lib/features/planner/state/planner_controller.dart),
[task detail](../lib/features/planner/pages/planner_task_page.dart).

## Schema 3 migration and XP compatibility

Planner schema 3 adds categories, explicit task type/parent fields, optional
difficulty metadata and a captured reward mode. Schema 1 and 2 remain readable;
unsupported or inconsistent state fails visibly without silently replacing
saved data. No database reset is used.

Legacy tasks receive a flexible/scheduled type from their saved time data when
the old type field is absent. Their IDs, order, steps, targets, units,
descriptions, dates, prerequisites, reminder configuration and other captured
conditions are retained. New category collections begin empty; old difficulty
values are retained as optional metadata rather than invented user categories.
An unchanged legacy overnight interval can still be saved during an unrelated
task edit, with an explicit next-day cue. Converting a scheduled task with an
implicit start-based reminder to Flexible captures its existing reminder wall
time, so removing the schedule does not leave an enabled reminder without a
time.

Legacy reusable templates are normalized for future commitments to
`packageOnly` rewards. The new completion reward equals their former total
possible reward: old completion XP plus each old leaf reward for each scheduled
occurrence. For example, a 50 XP package with a 12 XP task on two days becomes
one 74 XP package reward. Existing failure penalties remain unchanged. Legacy
task reward/skip fields may remain as compatibility metadata but are ignored
for these new package-only commitments. Built-in templates use the same
normalization when initially seeded.

Existing active and historical snapshots retain `legacyPerTask` mode and their
original completion reward, per-task rewards and per-task skip penalties. Their
records and ledger are not rewritten or re-awarded. The instance commitment
disclosure identifies these original rules, and task detail continues to show
its captured reward and skip behavior.

New package-only tasks update completion records without individual XP ledger
events or individual skip deductions. Completing all required tasks awards the
package reward once. A failed package applies its saved failure penalty at the
deadline, clamped by the existing nonnegative-balance rule. Daily selection
deadlines, missed-selection penalties and their idempotency remain unchanged.
This intentionally changes future reusable-template economics without changing
an already assigned commitment.

Category rename keeps its stable ID and updates reusable template display names.
An instance keeps its captured category name. Deletion detaches reusable
category references while retaining the saved name; existing instances remain
readable even after that category is removed.

The existing Android authoritative AtomicFile state, foreground transaction
lease, Hive compatibility mirror, backups and headless reconciliation remain in
use. Group rows never produce standalone occurrence/reminder work. Android
background scheduling can still be delayed by the OS, and an offline app cannot
verify an external clock; these pre-existing limits are unchanged.

## Localization and small screens

All new builder, category, group, reward and validation labels are in English
and Arabic ARB resources and the shared generated delegate. Arabic uses Flutter
RTL and the previously bundled Cairo weights above the Navigator, including
dialogs and time pickers. English remains LTR. User-entered names and stable
stored enum/ID values are not translated. XP fields accept Western, Arabic and
Persian digits. Task counts use ICU plural forms, including Arabic's six plural
categories and localized numeric display. The final visual review caught and
corrected a singular-count label in the nested preview.

Builder tests exercise Arabic at 320 logical pixels with 2× text, nested
navigation and Cairo. View tests exercise the active tree at 360 logical pixels
with 2× text and verify RTL, Cairo and localized progress. The existing
localization test checks Arabic coverage against every English message key.

## Acceptance evidence

The following maps the request's numbered acceptance scenarios to implemented
test coverage. These are automated checks; final device inspection is recorded
separately below.

| Request | Automated evidence |
| --- | --- |
| 1. Three destinations, no redundant Today | `planner_navigation_test.dart`: persistent Schedule and exact destination labels |
| 2–3. Smooth return, no reload/jump | Navigation tests inspect intermediate scroll offsets, controller/element identity, coalesced taps, current-time position, no refresh/state mutation and resting no-op |
| 4. Create/reuse custom categories | Builder category creation/rename/reuse test; tree domain category rename/delete/snapshot test |
| 5. Difficulty not required | Builder excludes difficulty controls and saves null difficulty; category-based preview test |
| 6. Essential package fields only | Guided-builder save test checks category/tree/reward/penalty; overnight test derives two internal days without a duration control; preview test discloses the actual deadline |
| 7. No individual task XP fields | Builder verifies single name field and zero task reward/skip defaults; preview/detail views omit task XP in package-only mode |
| 8. Flexible needs no time | Flexible builder helper and domain type validation |
| 9. Scheduled relevant controls | Builder range validation/time-picker test and derived duration assertion |
| 10. Optional reminders | Builder verifies disabled default and optional reminder dialog; reminder regression tests cover existing scheduling rules |
| 11. Nested children/deeper groups | Guided builder creates nested groups; domain restart test retains parent IDs and sibling order |
| 12–14. Required children/group/package completion | Domain nested progress, invalid group-completion command, optional branch, deadline and unfinished-task tests; view test opens original leaf IDs and checks derived progress |
| 15. Package XP only once | Domain replay/idempotency and restart tests; view test observes no per-task ledger events and exactly one final package event |
| 16. Stable active snapshots | Domain edits templates after assignment and compares original instance tree; migration preserves legacy reward mode |
| 17. Arabic/English/Cairo | Builder/view RTL+Cairo small-screen tests, navigation RTL test, localization coverage and integrated locale-switch regression |
| 18. Routines/history intact | Migration byte-equivalent records/ledger checks, routine domain tests, repository/background/persistence regression and integrated routine UI test |
| 19. Small Android layouts/nested navigation | 320px/2× Arabic builder workflow, 360px/2× Arabic tree, integrated main-screen large-text checks |

Test files:
[navigation](../test/planner_navigation_test.dart),
[builder](../test/planner_package_builder_test.dart),
[tree/migration](../test/planner_package_tree_test.dart),
[views](../test/planner_package_views_test.dart),
[domain](../test/planner_domain_test.dart),
[daily selection](../test/planner_daily_selection_test.dart),
[persistence](../test/planner_persistence_test.dart),
[repository](../test/planner_repository_test.dart),
[localization](../test/planner_localization_test.dart),
[integrated UI](../test/planner_ui_test.dart).

## Verification record

Confirmed focused batches before final integration:

| Batch | Result |
| --- | --- |
| Domain/lifecycle/persistence batch | 69 passed |
| Package builder, including two legacy edit regressions and overnight creation | 9 passed |
| Package views | 5 passed |
| Navigation | 4 passed |
| Repository | 5 passed |
| Integrated UI regression batch | 20 passed |
| Scoped builder/view/navigation analysis | Clean |
| Final plural/localization, package views and builder regression batch | 19 passed; scoped localization analysis clean |
| Habit-copy regression after asynchronous test helper correction | 6 passed |

Focused runs can overlap; these numbers are not an aggregate suite total.
English/Arabic generation completed. Other previously incomplete locales retain
their generated English fallbacks; the pre-existing Ukrainian ICU warning was
not introduced by this change.

Final verification on 29 October 2026:

| Check | Actual result |
| --- | --- |
| `flutter test --no-pub --reporter expanded` | **678 passed, 2 existing skips**, 1m 44s; `test-packages-verified.log` |
| `flutter analyze --no-pub --no-fatal-infos` | **0 errors, 0 warnings**, 8 existing deprecation infos outside the planner; 63.6s; `analysis-packages-final.log` |
| `flutter build apk --release --no-pub` | **Succeeded**, 126.7s; `build-packages-final.log` |
| APK identity | `com.streak.app`, **2.9.0+21**, Level Up, minimum SDK 28, target SDK 36 |
| APK size and signature | **98,668,520 bytes** (94.1 MiB); APK v2 signature verified; Android Debug test certificate |

The two skipped cases are the existing optional screenshot seed and host DST
case. Injected-clock deadline and DST domain tests run in the suite. Native
Kotlin code was unchanged by this redesign; its tests were not re-run as part
of this verification.

An intermediate full run alongside the build exposed an existing habit-copy
test race: its helper treated the Hive write as the end of saving, while
reminder initialization and the final route close were still pending. The
test helper now waits for the form to close with a bounded wait and explicit
assertion. All six habit-copy tests and the final full suite passed; application
save behavior was unchanged. Scoped analysis of that test was clean.
`git diff --check` also passed, with only existing line-ending notices.

Artifact: [`build/app/outputs/flutter-apk/app-release.apk`](../build/app/outputs/flutter-apk/app-release.apk).

SHA-256:
`6D19212E3242364E422A0A5A07D6AD4716C2C3F2CC1293A88310E58509C5B840`.

### Existing-data Android inspection

The APK was installed over version 2.8.0 on the existing Android emulator using
`adb install -r`, without clearing application storage. Canonical state was
captured immediately before and after the upgrade. The saved planner moved from
schema 2 to schema 3. All five routine definitions, completion records, three
ledger entries (15 XP), reminders, exclusions, overrides, achievements and the
existing 30 October assignment were unchanged. A recursive comparison found no
changed pre-existing values in either active challenge instance; the migration
only added the explicit compatibility fields.

Device inspection confirmed the three destinations, retention of the browsed
future-day viewport after visiting Profile, and return to the current-day
region when the selected Schedule destination was tapped again. Animation
timing and repeated-tap behavior are covered by the widget tests above.

A new **Morning Routine** template was created on-device with a custom category,
a flexible Wake up task, Exercise → Push-ups and Strength → Pull-ups groups,
and a scheduled Study task from 16:00 to 18:00 with reminders disabled. Native
storage confirmed four leaves, two groups, depth-two parent IDs, a 120-minute
derived study duration, package-only reward mode, 80 XP reward and 5 XP failure
penalty. After force-stop and relaunch, the package and tree reopened intact.
Renaming Morning goals to Morning Wellness retained the category ID and updated
the reusable template display. The existing tomorrow assignment was retained;
the inspection did not activate or complete an extra commitment.

Arabic RTL/Cairo navigation, identity, task tiles, time controls and nested
builder rows were inspected on-device. At 320dp and system font scale 2.0,
controls remained readable and reachable by scrolling, with the primary action
accessible. English, font scale 1.0, native display size/density and portrait
orientation were restored, and the app was left on Schedule. No Flutter or
AndroidRuntime errors appeared in the inspected device logs.

Evidence files are under `build/verification/packages-*`, including:

- [Final state comparison](../build/verification/packages-qa-comparison.json)
- [Builder tree](../build/verification/packages-task-tree-keyboard-hidden.png)
- [Package reward preview](../build/verification/packages-final-preview.png)
- [Expanded nested preview](../build/verification/packages-deeper-preview.png)
- [Arabic task editor](../build/verification/packages-arabic-scheduled.png)
- [Arabic 320dp / 2× time and reminder controls](../build/verification/packages-arabic-scheduled-320-font2-lower.png)
- [Restored English Schedule](../build/verification/packages-restored-english-schedule.png)

The final rebuilt APK was installed again over the same data, and the installed
APK hash matched the artifact above. English **1 task**, Arabic **مهمة واحدة**
and Arabic dual **مهمتان** were verified visually. A final native-state
comparison found zero changed fields beyond normal `lastObservedAt` clock
metadata: the five routines, three ledger entries, two original instances,
assignment and 15 XP were retained, alongside the new template/category. See
the [final comparison](../build/verification/packages-release-final-comparison.json)
and [English](../build/verification/packages-release-final-plural-en.png) /
[Arabic](../build/verification/packages-release-final-plural-ar.png) screenshots.
English, Schedule and the original display settings were restored again.

The release APK remains test-signed; distribution requires the owner's release
signing key. Emulator and automated layout checks do not replace testing on
physical devices. Existing legacy task conditions are preserved and disclosed
read-only rather than exposed as new-task configuration.

Commands use the existing Windows Flutter 3.47.7 / Dart 3.13.5 toolchain. The
process-only `FLUTTER_WINDOWS=false` workaround remains necessary in this
workspace for Flutter plugin setup; it does not change the app's runtime code or
system settings. No cloud service, runtime package dependency or Android
permission was added for this redesign.
