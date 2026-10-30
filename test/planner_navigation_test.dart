import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/pages/level_up_shell.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'support/app_harness.dart';

final _day = DateTime(2026, 10, 29);
final _clock = DateTime(2026, 10, 29, 12, 34);
PlannerController _planner() => PlannerController(
  initial: {},
  clock: () => _clock,
  persist: (_) async {},
  catalog: [],
);
ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find.byKey(const PageStorageKey('timeline-scroll')),
    )
    .controller!;
Future<void> _future(WidgetTester tester) async {
  final target = find.byKey(const ValueKey('timeline-day-2026-11-02'));
  await tester.scrollUntilVisible(
    target,
    500,
    maxScrolls: 45,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.drag(
    find.byKey(const PageStorageKey('timeline-scroll')),
    const Offset(0, -180),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('timeline-focus-2026-11-02')),
    findsOneWidget,
  );
}

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

  testWidgets(
    'three primary destinations land on a single persistent Schedule',
    (tester) async {
      final c = _planner();
      await pumpScreen(
        tester,
        LevelUpShell(refresh: (c) => c.evaluate()),
        planner: c,
      );
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((w) => w.label),
        ['Schedule', 'Challenges', 'Profile'],
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.byType(PlannerTimeline), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'selected Schedule animates to now, reuses state and coalesces repeated taps',
    (tester) async {
      final c = _planner();
      await c.saveItem(
        PlannerItem(
          id: 'morning',
          title: 'University',
          date: _day,
          startMinute: 8 * 60,
          endMinute: 9 * 60,
          recurrence: PlannerRecurrence.daily,
        ),
      );
      var refreshes = 0;
      var starts = 0;
      await pumpScreen(
        tester,
        NotificationListener<ScrollStartNotification>(
          onNotification: (_) {
            starts++;
            return false;
          },
          child: LevelUpShell(
            refresh: (c) async {
              refreshes++;
              await c.evaluate();
            },
          ),
        ),
        planner: c,
      );
      await _future(tester);
      final state = c.exportState;
      final element = tester.element(find.byType(PlannerTimeline));
      final controller = _scroll(tester);
      final origin = controller.offset;
      final refreshCount = refreshes;
      final nav = find.byIcon(Icons.calendar_view_week_outlined);
      await tester.tap(nav);
      await tester.pump();
      expect(controller.offset, closeTo(origin, .1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(controller.offset, lessThan(origin));
      final intermediate = controller.offset;
      await tester.tap(nav);
      await tester.tap(nav);
      await tester.pump(const Duration(milliseconds: 70));
      expect(controller.offset, lessThan(intermediate));
      await tester.pumpAndSettle();
      expect(
        identical(tester.element(find.byType(PlannerTimeline)), element),
        true,
      );
      expect(identical(_scroll(tester), controller), true);
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-10-29')),
        findsOneWidget,
      );
      final viewport = tester.getRect(
        find.byKey(const PageStorageKey('timeline-scroll')),
      );
      final now = tester
          .getCenter(find.byKey(const ValueKey('timeline-now-line')))
          .dy;
      expect(now, inInclusiveRange(viewport.top, viewport.top + 150));
      expect(c.exportState, state);
      expect(refreshes, refreshCount);
      final resting = controller.offset;
      final startCount = starts;
      await tester.tap(nav);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(resting, .1));
      expect(starts, startCount);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'returning from another tab retains the browsed date until explicit reselect',
    (tester) async {
      final c = _planner();
      await pumpScreen(
        tester,
        LevelUpShell(refresh: (c) => c.evaluate()),
        planner: c,
      );
      await _future(tester);
      final controller = _scroll(tester);
      final before = controller.offset;
      final state = c.exportState;
      await tester.tap(find.byIcon(Icons.bolt_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_view_week_outlined));
      await tester.pumpAndSettle();
      expect(identical(_scroll(tester), controller), true);
      expect(controller.offset, closeTo(before, .1));
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-11-02')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.calendar_view_week_outlined));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('timeline-focus-2026-10-29')),
        findsOneWidget,
      );
      expect(c.exportState, state);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Arabic navigation mirrors three destinations while keeping the same timeline',
    (tester) async {
      final c = _planner();
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('ar'),
            child: LevelUpShell(refresh: (c) => c.evaluate()),
          ),
        ),
        planner: c,
        textScale: 2,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      final schedule = tester
          .getCenter(find.byIcon(Icons.calendar_view_week_outlined))
          .dx;
      final challenges = tester.getCenter(find.byIcon(Icons.bolt_outlined)).dx;
      final profile = tester
          .getCenter(find.byIcon(Icons.person_outline_rounded))
          .dx;
      expect(schedule, greaterThan(challenges));
      expect(challenges, greaterThan(profile));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
