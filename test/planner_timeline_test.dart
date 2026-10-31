import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'support/app_harness.dart';

final day = DateTime(2026, 10, 29);
PlannerOccurrence event(
  String id,
  int start,
  int end, {
  DateTime? origin,
  bool overnight = false,
}) => PlannerOccurrence(
  id: '$id@${plannerDateKey(origin ?? day)}',
  day: origin ?? day,
  item: PlannerItem(
    id: id,
    title: id,
    date: origin ?? day,
    startMinute: start,
    endMinute: end,
    overnight: overnight,
  ),
);

void main() {
  useEmptyStore();
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final name in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      loader.addFont(rootBundle.load('fonts/Cairo/Cairo-$name.ttf'));
    }
    await loader.load();
  });
  test(
    'time mapping positions durations, hour marks and gaps continuously',
    () {
      final layout = PlannerDayLayout(day, [
        event('short', 480, 485),
        event('long', 600, 780),
      ]);
      final short = layout.yForMinute(485) - layout.yForMinute(480);
      final long = layout.yForMinute(780) - layout.yForMinute(600);
      expect(short, greaterThanOrEqualTo(50));
      expect(long, greaterThan(short));
      expect(layout.yForMinute(600), greaterThan(layout.yForMinute(485)));
      for (final minute in [0, 480, 485, 600, 780, 1440]) {
        expect(
          layout.minuteForY(layout.yForMinute(minute)),
          closeTo(minute, .001),
        );
      }
    },
  );
  test(
    'adjacent one-minute activities have independent 48px touch regions',
    () {
      final layout = PlannerDayLayout(day, [
        event('a', 480, 481),
        event('b', 481, 482),
      ]);
      for (final e in layout.events) {
        expect(
          layout.yForMinute(e.endMinute) - layout.yForMinute(e.startMinute) - 2,
          greaterThanOrEqualTo(48),
        );
        expect(e.laneCount, 1);
      }
      expect(layout.events[0].endMinute, layout.events[1].startMinute);
    },
  );
  test(
    'overnight segments clip to midnight while preserving original identity',
    () {
      final overnight = event(
        'sleep',
        23 * 60,
        7 * 60,
        origin: plannerAddDays(day, -1),
        overnight: true,
      );
      final layout = PlannerDayLayout(day, [overnight]);
      expect(layout.events.single.startMinute, 0);
      expect(layout.events.single.endMinute, 420);
      expect(layout.events.single.occurrence, same(overnight));
      final previous = PlannerDayLayout(plannerAddDays(day, -1), [overnight]);
      expect(previous.events.single.endMinute, 1440);
      expect(
        previous.events.single.occurrence.id,
        layout.events.single.occurrence.id,
      );
    },
  );
  test('overlap lanes are shared only for real intersections', () {
    final layout = PlannerDayLayout(day, [
      event('a', 480, 600),
      event('b', 540, 660),
      event('c', 660, 720),
    ]);
    expect(layout.events.take(2).map((e) => e.lane).toSet().length, 2);
    expect(layout.events.take(2).map((e) => e.laneCount), [2, 2]);
    expect(layout.events.last.laneCount, 1);
    final empty = PlannerDayLayout(day, []);
    expect(empty.height, greaterThan(800));
    expect(empty.yForMinute(1440), empty.height);
  });
  testWidgets(
    'dense overlaps remain accessible without changing stored tasks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = PlannerController(
        initial: {},
        clock: () => DateTime(2026, 10, 29, 8),
        persist: (_) async {},
        catalog: [],
      );
      for (var i = 0; i < 6; i++) {
        await c.saveItem(
          PlannerItem(
            id: 'event$i',
            title: 'Activity $i',
            date: day,
            startMinute: 480,
            endMinute: 481,
          ),
        );
      }
      await c.startChallenge(
        const ChallengeTemplate(
          id: 'challenge',
          name: 'Challenge',
          description: '',
          difficulty: ChallengeDifficulty.easy,
          durationDays: 1,
          completionXp: 1,
          tasks: [
            ChallengeTaskDefinition(
              id: 'one',
              title: 'Challenge task',
              dayOffsets: [0],
              startMinute: 480,
              durationMinutes: 1,
            ),
          ],
        ),
      );
      final before = c.exportState;
      final opened = <PlannerOccurrence>[];
      await pumpScreen(
        tester,
        Scaffold(
          body: PlannerTimeline(
            controller: c,
            onOpen: opened.add,
            onAdd: (_) {},
          ),
        ),
        planner: c,
      );
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-now')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('timeline-now-line'))).dy,
        closeTo(
          tester.getTopLeft(find.byKey(const ValueKey('timeline-now'))).dy,
          .01,
        ),
      );
      // Every overlapping block is laid out on its own lane; none collapse
      // into a summary. Lanes that do not fit scroll sideways.
      final lanes = find.byKey(const PageStorageKey('timeline-lanes-2026-10-29'));
      final blocks = find.descendant(
        of: lanes,
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('timeline-event-'),
        ),
      );
      expect(blocks, findsNWidgets(7));
      final first = find.byKey(
        const ValueKey('timeline-event-event0@2026-10-29-2026-10-29'),
      );
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      final last = find.byKey(
        const ValueKey('timeline-event-event5@2026-10-29-2026-10-29'),
      );
      // Lanes open at the start (they must not inherit the vertical list's
      // saved offset); later lanes are off-screen until scrolled to.
      expect(tester.getTopLeft(first).dx, lessThan(100));
      expect(tester.getTopLeft(last).dx, greaterThan(320));
      await tester.dragUntilVisible(last, lanes, const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(opened.single.id, 'event5@2026-10-29');
      expect(c.occurrenceById(opened.single.id), isNotNull);
      expect(c.exportState, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'long mixed Arabic names and short events remain usable at double text size',
    (tester) async {
      final c = PlannerController(
        initial: {},
        clock: () => DateTime(2026, 10, 29, 8),
        persist: (_) async {},
        catalog: [],
      );
      const title =
          'محاضرة الجامعة University ومراجعة ملاحظات الدراسة المهمة والطويلة';
      await c.saveItem(PlannerItem(id: 'long', title: title, date: day));
      await c.saveItem(
        PlannerItem(
          id: 'short',
          title: 'إحماء Workout',
          date: day,
          startMinute: 480,
          endMinute: 481,
        ),
      );
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Theme(
            data: AppTypography.forLocale(
              Theme.of(context),
              const Locale('ar'),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: PlannerTimeline(
                  controller: c,
                  onOpen: (_) {},
                  onAdd: (_) {},
                  header: const Text('المستوى ١ · ١٥ نقطة خبرة'),
                ),
              ),
            ),
          ),
        ),
        planner: c,
        textScale: 2,
      );
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(title), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'prepending past days preserves the visible date and permits older history',
    (tester) async {
      final c = PlannerController(
        initial: {},
        clock: () => DateTime(2026, 10, 29, 8),
        persist: (_) async {},
        catalog: [],
      );
      await c.saveItem(
        PlannerItem(
          id: 'daily',
          title: 'Routine',
          date: DateTime(2026, 9, 1),
          recurrence: PlannerRecurrence.daily,
          startMinute: 480,
          endMinute: 540,
        ),
      );
      final before = c.exportState;
      final navigation = PlannerTimelineNavigation();
      await pumpScreen(
        tester,
        Scaffold(
          body: PlannerTimeline(
            controller: c,
            navigation: navigation,
            onOpen: (_) {},
            onAdd: (_) {},
          ),
        ),
        planner: c,
      );
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(100);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-10-22')),
        findsOneWidget,
      );
      // The buffer was prepended, but the user's civil date did not jump backward.
      expect(scroll.offset, greaterThan(20000));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('timeline-day-2026-10-01')),
        -600,
        maxScrolls: 80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-10-01')),
        findsOneWidget,
      );
      final returning = navigation.returnToNow();
      await tester.pumpAndSettle();
      await returning;
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-10-29')),
        findsOneWidget,
      );
      expect(c.exportState, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
