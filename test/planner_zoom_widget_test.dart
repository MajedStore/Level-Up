import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/pages/level_up_shell.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'package:streak/services/schedule_widget_service.dart';
import 'support/app_harness.dart';

final _now = DateTime(2026, 10, 29, 8);

PlannerController _controller() => PlannerController(
  initial: {},
  clock: () => _now,
  persist: (_) async {},
  catalog: [],
);

void main() {
  useEmptyStore();

  test('zoom spreads the day without changing event order', () {
    final plain = PlannerDayLayout(_now, const []);
    final zoomed = PlannerDayLayout(_now, const [], zoom: 2);
    expect(plain.height, closeTo(1440 * .6, .01));
    expect(zoomed.height, closeTo(plain.height * 2, .01));
    expect(zoomed.yForMinute(570), closeTo(plain.yForMinute(570) * 2, .01));
  });

  /// A timeline whose zoom lives in the test, like the shell's.
  Future<double Function()> pumpZoomable(
    WidgetTester tester,
    PlannerController c,
  ) async {
    var zoom = 1.0;
    await pumpScreen(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PlannerTimeline(
            controller: c,
            onOpen: (_) {},
            onAdd: (_) {},
            zoom: zoom,
            onZoom: (value) => setState(() => zoom = value),
          ),
        ),
      ),
      planner: c,
    );
    return () => zoom;
  }

  Future<void> tapZoom(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('zoom buttons cover 0.5x to 8x with finer time labels', (
    tester,
  ) async {
    final c = _controller();
    final zoom = await pumpZoomable(tester, c);
    // Overview: hours only.
    expect(find.text('09:00'), findsWidgets);
    expect(find.text('09:30'), findsNothing);

    await tapZoom(tester, 'timeline-zoom-out');
    expect(zoom(), .75);
    await tapZoom(tester, 'timeline-zoom-out');
    expect(zoom(), .5);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('timeline-zoom-out')))
          .onPressed,
      isNull,
    );

    for (final (level, label) in [
      (.75, null),
      (1.0, null),
      (1.5, '09:30'),
      (2.0, '09:30'),
      (3.0, '09:15'),
      (4.0, '09:10'),
      (6.0, '09:10'),
      (8.0, '09:05'),
    ]) {
      await tapZoom(tester, 'timeline-zoom-in');
      expect(zoom(), level);
      if (label != null) expect(find.text(label), findsWidgets, reason: label);
    }
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('timeline-zoom-in')))
          .onPressed,
      isNull,
    );
    // Zooming keeps today in view; the list must not misplace days.
    expect(
      find.byKey(const ValueKey('timeline-day-2026-10-29')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('timeline-day-2026-11-04')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a pinch zooms around the fingers and keeps that time still', (
    tester,
  ) async {
    final c = _controller();
    await c.saveItem(
      PlannerItem(
        id: 'lecture',
        title: 'Lecture',
        date: _now,
        startMinute: 9 * 60,
        endMinute: 10 * 60,
      ),
    );
    final zoom = await pumpZoomable(tester, c);
    final block = find.byKey(
      const ValueKey('timeline-event-lecture@2026-10-29-2026-10-29'),
    );
    // Bring the block toward the middle so both fingers land on the timeline.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(block);
    final focus = before.dy;
    final x = before.dx + 40;
    final first = await tester.startGesture(Offset(x, focus - 50));
    final second = await tester.startGesture(Offset(x, focus + 50));
    await tester.pump();
    for (var step = 1; step <= 10; step++) {
      await first.moveTo(Offset(x, focus - 50 - step * 5));
      await second.moveTo(Offset(x, focus + 50 + step * 5));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    // Fingers went from 100 to 200 px apart: twice the zoom.
    expect(zoom(), closeTo(2, .02));
    // 9:00 sat under the midpoint, so the block's top did not move.
    expect(tester.getTopLeft(block).dy, closeTo(focus, 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('the schedule remembers its zoom on this device', (
    tester,
  ) async {
    final c = _controller();
    await pumpScreen(
      tester,
      LevelUpShell(refresh: (c) => c.evaluate()),
      planner: c,
    );
    await tester.tap(find.byKey(const ValueKey('timeline-zoom-in')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(LocalStore.setting<num>('timelineZoom', 1), 1.5);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('widget payload lists a week with today in time order', (
    tester,
  ) async {
    final c = _controller();
    await c.saveItem(
      PlannerItem(
        id: 'gym',
        title: 'Gym',
        date: _now,
        startMinute: 14 * 60,
        endMinute: 15 * 60,
        category: 'Fitness',
      ),
    );
    await c.saveItem(
      PlannerItem(
        id: 'uni',
        title: 'University',
        date: _now,
        startMinute: 9 * 60,
        endMinute: 13 * 60,
        category: 'Study',
      ),
    );
    await c.saveItem(PlannerItem(id: 'read', title: 'Read', date: _now));
    await pumpScreen(tester, const Scaffold(body: SizedBox()), planner: c);
    final payload = ScheduleWidgetService.payload(
      tester.element(find.byType(Scaffold)),
      c,
    );
    final days = payload['days'] as List;
    expect(days, hasLength(ScheduleWidgetService.days));
    final today = days.first as Map;
    expect(today['key'], '2026-10-29');
    final items = today['items'] as List;
    expect(items.map((i) => (i as Map)['title']), ['University', 'Gym']);
    expect((items.first as Map)['start'], 540);
    expect((items.first as Map)['end'], 780);
    expect((items.first as Map)['time'], contains('9:00'));
    expect((items.first as Map)['category'], 'Study');
    expect((today['anytime'] as List).single['title'], 'Read');
    expect((days[1] as Map)['key'], '2026-10-30');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('widget payload carries today\'s challenge with its progress', (
    tester,
  ) async {
    final c = _controller();
    await c.startChallenge(
      const ChallengeTemplate(
        id: 'workout',
        name: 'Hard Workout',
        description: '',
        difficulty: ChallengeDifficulty.hard,
        durationDays: 1,
        completionXp: 30,
        tasks: [
          ChallengeTaskDefinition(
            id: 'warm',
            title: 'Warm-up',
            dayOffsets: [0],
          ),
          ChallengeTaskDefinition(
            id: 'run',
            title: 'Running',
            dayOffsets: [0],
            startMinute: 17 * 60,
            durationMinutes: 60,
          ),
        ],
      ),
    );
    final warmup = c
        .occurrences(_now)
        .firstWhere((o) => o.item.title == 'Warm-up');
    await c.complete(warmup.id);
    await pumpScreen(tester, const Scaffold(body: SizedBox()), planner: c);
    final payload = ScheduleWidgetService.payload(
      tester.element(find.byType(Scaffold)),
      c,
    );
    expect(payload['challengeTitle'], "Today's challenge");
    expect(payload['tomorrowFor'], '2026-10-29');
    expect(payload['tomorrowLabel'], "Choose tomorrow's package");
    final today = (payload['days'] as List).first as Map;
    final pack = (today['challenges'] as List).single as Map;
    expect(pack['name'], 'Hard Workout');
    expect(pack['done'], 1);
    expect(pack['total'], 2);
    final tasks = pack['tasks'] as List;
    // Timed tasks first, then anytime ones.
    expect(tasks.map((t) => (t as Map)['title']), ['Running', 'Warm-up']);
    expect((tasks.first as Map)['time'], contains('5:00'));
    expect((tasks.last as Map)['done'], isTrue);
    // Tomorrow has no package tasks.
    expect(((payload['days'] as List)[1] as Map)['challenges'], isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
