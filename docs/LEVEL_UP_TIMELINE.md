# Level Up 2.8.0+20 — continuous timeline and Cairo typography

Version 2.9.0 merges Today into Schedule and adds the visual package/category/tree
builder. See [the current package report](LEVEL_UP_PACKAGES.md). The timeline and
Cairo implementation described here remain in use; artifact results below are the
historical 2.8.0 baseline.

This redesign extends the existing offline planner. Routine/challenge identity,
daily assignments, immutable challenge rules, XP accounting, reminders, backups
and the schema-2 data store continue to use the existing domain implementation.
See [the core refactoring report](LEVEL_UP_REFACTOR.md) for those rules.

## Inspection and design decisions

The previous Today page displayed scheduled activities as ordinary list rows,
while Schedule required a week strip and day-button changes. Time and duration
were text beside each row, so neither gaps nor overlaps were visible. Both
screens repeated add controls. The routine editor also repeated its Save action.
Arabic used system fallback fonts rather than an explicitly bundled Arabic face.

The redesign replaces the routine rows/week switcher with one vertical schedule
across consecutive days. It keeps existing task-detail and edit routes and derives
all timeline events from the controller's existing occurrence IDs. Scheduled
challenge events retain a trophy marker and remain linked to their instance;
scrolling never activates or completes a challenge. Secondary details remain in
their existing destinations instead of competing with the schedule.

## Implementation

`PlannerTimeline` uses one lazy `CustomScrollView` for consecutive local dates.
Today and Schedule reuse it; the old week/day switcher and repeated add controls
are removed. A compact pinned date bar contains the single Add Activity action
and a return-to-today control. Today adds a compact XP row and its challenge
section after today's timeline, before tomorrow naturally enters the same scroll.

Each day retains a full civil-time rail, localized hour marks, subtle day surface,
and a date header. Events are positioned by their actual local start/end times.
The shared piecewise time mapping expands short occupied intervals to preserve
accessible touch targets; hour marks, gaps, event endpoints and current-time
position all use that same mapping. Adjacent short activities therefore do not
paint over one another. Overnight activities are clipped at midnight and reuse
their original occurrence ID on both days. Unscheduled tasks remain separate rows
after the timed portion.

Overlaps use independent lanes. Dense overlaps on narrow screens use a compact
overlap group with access to every original task, rather than painting unreadable
columns or inventing duplicate records. Routine category icons and challenge
trophies distinguish their actual domain types. Checks/skip icons and text
decoration convey status without relying on color alone.

Only content near the actual viewport edges is softly faded, with a 74% opacity
floor; the middle remains fully opaque. This effect follows the viewport and is
independent of whether a date is in the past or future. Day construction is lazy;
scrolling toward the end extends the available future range. Returning today and
language/orientation/data rebuilds retain a local-date/time scroll anchor.
Reaching the earlier edge prepends another thirty days while retaining that
anchor, so history access is not limited to the initial buffer.

The existing controller still owns recurrence, editing, task outcomes, challenge
assignments and XP. Timeline navigation only reads occurrences. Completion opens
the existing task page, and editing opens the existing occurrence/series-aware
editor. The visible app's minute refresh rebuilds the current-time marker even
when domain evaluation is a no-op.

The routine editor keeps name, date, time range, repeat choices, reminders and a
small duration preview prominent. Advanced conditions remain available; one save
action replaces the repeated top/bottom actions. Existing per-occurrence and
whole-series behavior is retained.

Cairo is bundled offline in actual regular (400), medium (500), semibold (600),
bold (700), extra-bold (800) and black (900) font files. `AppTypography` applies
it above the Navigator for Arabic, including
dialogs, menus, buttons and form controls; English keeps the existing Latin
family with Cairo as its Arabic fallback. Original theme identity is preserved
separately so choosing Arabic does not switch legacy classic/express behavior.
The font's SIL Open Font License is included with the assets.
Asset provenance and generation details are in `fonts/Cairo/README.md`;
`fonts/Cairo/OFL.txt` preserves the font license.

Main components changed:

- New timeline display and geometry files under `lib/features/planner/widgets/`
- Existing `level_up_shell.dart` and `planner_editor_page.dart`
- New `lib/app/theme/app_typography.dart`, existing app theme and app bootstrap
- Existing Express text styles and standalone donut-chart text painting gain
  Cairo fallback; theme-style identity remains independent of language
- Bundled Cairo assets, font declarations and localized timeline control labels
- Timeline geometry/rendering tests, existing UI/editor tests and typography tests

No cloud service, runtime package dependency, Android permission, domain schema
or planner persistence migration is needed for this redesign.

## Verification

Commands run from the existing Windows workspace (using the configured Flutter
3.47.7 / Dart 3.13.5 toolchain):

```powershell
$env:FLUTTER_WINDOWS='false'
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' test --no-pub --reporter expanded
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos
& 'C:\Users\promj\develop\flutter\bin\flutter.bat' build apk --release --no-pub
```

The process-local `FLUTTER_WINDOWS` setting is the existing Android build workaround
for this machine; it does not change global Flutter settings. No mockup or static
screenshot is used as the application UI.

- Final full Flutter suite: **647 passed, 2 existing skips**, 1m56s
  (`test-timeline-final-all.log`). The skips remain the optional screenshot demo seed
  and host-specific DST condition; injected deadline/DST tests still run.
- Full analyzer: **no errors or warnings**, 8 pre-existing deprecation infos,
  27.3s (`analysis-timeline-full.log`).
- After the final current-time paint-centering correction, **17 timeline and UI
  tests passed** in 10s (`test-timeline-currentline.log`), including physical line
  alignment, past-buffer expansion and original-record identity.
- The **10 Cairo/editor/localization tests passed** in 3s
  (`build/cairo-tests-final.log`). These load real font files and validate weight
  classes/shaping tables, locale-aware controls and the live editor preview.
- Final targeted analyzer covering changed planner/theme/bootstrap files reports
  **no issues** (`analysis-timeline-last.log`).
- Final release build: **success**, **61.8s**, Flutter reports **93.9 MB**
  (`build-levelup-timeline-final.log`).

The final artifact is `build/app/outputs/flutter-apk/app-release.apk`,
**98,503,440 bytes**, SHA-256:
`84949CEF97B5ED132F604DA46AACC4D7751616FF35480BE12F7EDFE318FA22C5`.
`apksigner verify --verbose --print-certs` verifies the v2 signature with the
existing local **Android Debug** signing certificate. `aapt dump badging` confirms
Level Up / `com.streak.app`, 2.8.0 / versionCode 20, min SDK 28 and compile/target SDK
36. APK archive inspection confirms all six Cairo TTFs and `fonts/Cairo/OFL.txt`
are actually bundled; the font license is registered in the existing license UI.

Earlier intermediate builds/results remain in their logs. The first integrated
build was successful in 189.2s; the final result above includes the automatic
history-buffer extension and current-time line correction.

Final integrated UI verification: **10 tests passed** in 15 seconds
(`build/timeline-ui-final.log`). These include continuous scrolling four
days forward/returning today, preserving a November 2 anchor through Arabic/English,
landscape, tab switching and routine edits, advancing the current-time marker with
an injected clock without altering records/XP, and existing package, routine,
sequence, deadline-notice and double-text-size regressions.

## Android emulator verification

The previous APK was updated with `adb install -r` on the existing read-only
`emulator-5554` test AVD. The installed final `base.apk` SHA-256 is
`84949CEF97B5ED132F604DA46AACC4D7751616FF35480BE12F7EDFE318FA22C5`;
Android reports version 2.8.0 and versionCode 20.

- The existing **15 XP**, all three historical ledger entries, original routine
  definitions, two challenge instances and October 30 assignment were retained.
- Scrolled naturally from October 29 through October 30, October 31 and the empty
  November 1 day. Adjacent day portions remain visible while crossing boundaries;
  viewport-edge fading stays subtle and text readable. Return to today restored
  October 29 without a separate daily page.
- Created two actual one-time QA activities through the editor: a five-minute
  20:15–20:20 activity and a ninety-minute 20:00–21:30 activity. The live preview
  displayed their correct times/duration. After acknowledging the overlap, both
  appeared in readable, distinct lanes, with the long event occupying more height.
- Edited the short activity's title without changing its ID/times, then completed
  it through the existing task page. XP remained 15 and the ledger unchanged.
- Arabic Cairo/RTL was visually verified on Today, Schedule, Challenges, Profile,
  Settings, the routine editor/preview, package editor and time picker. User-entered
  English titles remained intact alongside Arabic UI. Returning to English restored
  LTR. The entire domain state compared exactly before and after that language and
  cancelled-form round trip.
- Landscape and system font scale 2 were inspected. The date and controls remained
  usable; dense overlaps used the accessible group instead of narrow unreadable
  columns. Device rotation/font scale were restored afterward.
- On the final APK, scrolled backward beyond the original buffer to **October 11**,
  then returned to October 29. The complete domain state remained exactly equal
  after the final update and history browsing. The current-time line was visually
  checked at the five-minute event boundary after its centering correction.

No device clock, timezone or selection deadline was changed. The AVD is left on
English Today at the original font scale and portrait orientation. The two QA
activities exist only in this emulator's data; no demo records are seeded in code.

Screenshots and canonical snapshots are under ignored
`build/verification/timeline-*.png` / `timeline-*.json`. Summaries:
`timeline-ui-evidence.json` and `timeline-final-evidence.json`.

The layout was exercised on an emulator and in narrow/large-text widget tests.
Physical-device performance and accessibility-service interaction across every
Android vendor remain unmeasured.
