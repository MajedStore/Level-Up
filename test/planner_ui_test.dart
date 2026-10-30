import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/pages/level_up_shell.dart';
import 'package:streak/features/planner/pages/planner_challenges_page.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'support/app_harness.dart';

final _now = DateTime(2026, 10, 29, 12);
PlannerController _controller() => PlannerController(
  initial: {},
  clock: () => _now,
  persist: (_) async {},
  catalog: [],
);
Future<void> _refresh(PlannerController c) => c.evaluate();
Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300, maxScrolls: 30);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ChallengeTemplate _package() => const ChallengeTemplate(
  id: 'hard-workout',
  name: 'Hard Workout',
  description: '',
  difficulty: ChallengeDifficulty.hard,
  durationDays: 1,
  completionXp: 30,
  tasks: [
    ChallengeTaskDefinition(
      id: 'warmup',
      title: 'Warm-up',
      dayOffsets: [0],
      rewardXp: 10,
      skipPenalty: 5,
      steps: ['Prepare', 'Move'],
    ),
    ChallengeTaskDefinition(
      id: 'run',
      title: 'Running',
      dayOffsets: [0],
      startMinute: 17 * 60,
      durationMinutes: 60,
      rewardXp: 20,
      skipPenalty: 7,
    ),
    ChallengeTaskDefinition(
      id: 'stretch',
      title: 'Stretching',
      dayOffsets: [0],
      rewardXp: 5,
      skipPenalty: 3,
    ),
  ],
);

void main() {
  useEmptyStore();
  testWidgets(
    'Schedule lands on one continuous timeline with three destinations',
    (tester) async {
      final c = _controller();
      await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
      expect(find.byType(PlannerTimeline), findsOneWidget);
      expect(
        find.byKey(const PageStorageKey('timeline-scroll')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-return-today')),
        findsNothing,
      );
      expect(find.text('Daily progress'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      final fourthDay = find.byKey(const ValueKey('timeline-day-2026-11-02'));
      await tester.scrollUntilVisible(fourthDay, 500, maxScrolls: 40);
      await tester.ensureVisible(fourthDay);
      await tester.pumpAndSettle();
      expect(fourthDay, findsOneWidget);
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      expect(
        find.byKey(const ValueKey('timeline-day-2026-10-29')),
        findsOneWidget,
      );
      await _tap(tester, find.byIcon(Icons.bolt_outlined));
      expect(find.text('Create package'), findsOneWidget);
      await _tap(tester, find.byIcon(Icons.person_outline_rounded));
      expect(find.text('XP history'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('routine completion updates its record without challenge XP', (
    tester,
  ) async {
    final c = _controller();
    await c.saveItem(
      PlannerItem(
        id: 'uni',
        title: 'University',
        date: _now,
        startMinute: 8 * 60,
        endMinute: 14 * 60,
        recurrence: PlannerRecurrence.weekdays,
        weekdays: [1, 2, 4],
      ),
    );
    await c.saveItem(
      PlannerItem(id: 'read', title: 'Read lecture notes', date: _now),
    );
    await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
    expect(find.text('University'), findsOneWidget);
    await _tap(tester, find.text('Read lecture notes'));
    await _tap(tester, find.text('Mark complete'));
    expect(c.balance, 0);
    expect(c.ledger, isEmpty);
    expect(
      c.occurrenceById('read@2026-10-29')!.record.status,
      CompletionStatus.completed,
    );
    expect(find.text('Mark complete'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PlannerTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('tomorrow selection commits once and preserves the routine', (
    tester,
  ) async {
    final c = _controller();
    await c.saveTemplate(_package());
    final tomorrow = plannerAddDays(_now, 1);
    await c.saveItem(
      PlannerItem(
        id: 'uni',
        title: 'University',
        date: tomorrow,
        startMinute: 8 * 60,
        endMinute: 14 * 60,
      ),
    );
    final routine = c.items.single.toMap();
    await pumpScreen(
      tester,
      ChallengePreviewPage(template: c.templates.single),
      planner: c,
    );
    expect(c.instances, isEmpty);
    expect(find.text('Failure −0 XP'), findsOneWidget);
    await _tap(tester, find.text('Confirm commitment'));
    expect(c.instances, isEmpty);
    await _tap(tester, find.text('Confirm commitment').last);
    expect(c.instances.length, 1);
    expect(c.tomorrowSelection!.instanceId, c.instances.single.id);
    expect(c.items.single.toMap(), routine);
    expect(c.occurrences(tomorrow).where((o) => o.isChallenge).length, 3);
    expect(
      c.occurrences(tomorrow).where((o) => !o.isChallenge).single.title,
      'University',
    );
    await c.evaluate();
    expect(c.instances.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('sequential challenge rewards only after all steps', (
    tester,
  ) async {
    final c = _controller();
    await c.startChallenge(_package());
    final occurrence = c
        .occurrences(_now)
        .firstWhere((o) => o.item.title == 'Warm-up');
    await pumpScreen(
      tester,
      PlannerTaskPage(occurrence: occurrence),
      planner: c,
    );
    await _tap(tester, find.text('Mark complete'));
    expect(find.text('Complete every required step first.'), findsOneWidget);
    expect(c.balance, 0);
    await _tap(tester, find.text('1. Prepare'));
    expect(c.balance, 0);
    await _tap(tester, find.text('2. Move'));
    expect(c.balance, 10);
    expect(c.ledger.length, 1);
    expect(find.text('Mark complete'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'overdue selection notice shows the actual charge and stays acknowledged',
    (tester) async {
      var now = _now;
      final c = PlannerController(
        initial: {},
        clock: () => now,
        persist: (_) async {},
        catalog: [],
      );
      await c.evaluate();
      now = DateTime(2026, 10, 30, 1);
      await c.evaluate();
      await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Penalty recorded: 0 XP'), findsOneWidget);
      expect(c.ledger.length, 1);
      await _tap(tester, find.text('OK'));
      expect(c.unacknowledgedMisses, isEmpty);
      final reopened = PlannerController(
        initial: c.exportState,
        clock: () => now,
        persist: (_) async {},
        catalog: [],
      );
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        LevelUpShell(refresh: _refresh),
        planner: reopened,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(reopened.ledger.length, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      reopened.dispose();
    },
  );

  testWidgets(
    'Arabic RTL and English LTR preserve identities and XP on all main screens',
    (tester) async {
      final c = _controller();
      await c.saveTemplate(_package());
      await c.saveItem(
        PlannerItem(
          id: 'uni',
          title: 'University الجامعة',
          date: _now,
          startMinute: 8 * 60,
          endMinute: 14 * 60,
        ),
      );
      final state = c.exportState;
      final locale = ValueNotifier(const Locale('en'));
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (context, value, _) => Localizations.override(
              context: context,
              locale: value,
              child: LevelUpShell(refresh: _refresh),
            ),
          ),
        ),
        planner: c,
      );
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.ltr,
      );
      locale.value = const Locale('ar');
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.rtl,
      );
      expect(find.text('University الجامعة'), findsOneWidget);
      for (final icon in [
        Icons.calendar_view_week_outlined,
        Icons.bolt_outlined,
        Icons.person_outline_rounded,
      ]) {
        await _tap(tester, find.byIcon(icon));
        expect(tester.takeException(), isNull);
      }
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.ltr,
      );
      expect(c.exportState, state);
      expect(find.text('XP history'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
      c.dispose();
    },
  );

  testWidgets('main screens remain usable at double system text size', (
    tester,
  ) async {
    final c = _controller();
    await pumpScreen(
      tester,
      LevelUpShell(refresh: _refresh),
      planner: c,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    for (final icon in [
      Icons.calendar_view_week_outlined,
      Icons.bolt_outlined,
      Icons.person_outline_rounded,
    ]) {
      await _tap(tester, find.byIcon(icon));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'scrolled date survives language orientation tabs and routine edits',
    (tester) async {
      final c = _controller();
      await c.saveItem(
        PlannerItem(
          id: 'daily',
          title: 'University الجامعة',
          date: plannerDay(_now),
          startMinute: 8 * 60,
          endMinute: 14 * 60,
          recurrence: PlannerRecurrence.daily,
        ),
      );
      final before = c.exportState;
      final locale = ValueNotifier(const Locale('en'));
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (context, value, _) => Localizations.override(
              context: context,
              locale: value,
              child: LevelUpShell(refresh: _refresh),
            ),
          ),
        ),
        planner: c,
      );
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      final target = find.byKey(const ValueKey('timeline-day-2026-11-02'));
      final scroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('timeline-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        target,
        500,
        maxScrolls: 40,
        scrollable: scroll,
      );
      await tester.ensureVisible(target);
      await tester.drag(
        find.byKey(const PageStorageKey('timeline-scroll')),
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      Finder focus() => find.byKey(const ValueKey('timeline-focus-2026-11-02'));
      expect(focus(), findsOneWidget);

      locale.value = const Locale('ar');
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(PlannerTimeline))),
        TextDirection.rtl,
      );
      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      await _tap(tester, find.byIcon(Icons.bolt_outlined));
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      expect(focus(), findsOneWidget);
      expect(c.exportState, before);

      await c.saveItem(
        c.items.single.copyWith(title: 'University lab الجامعة'),
      );
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(c.occurrenceById('daily@2026-11-02')!.item.id, 'daily');
      expect(c.balance, 0);
      expect(c.instances, isEmpty);
      expect(c.ledger, isEmpty);
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
      c.dispose();
    },
  );

  testWidgets('current-time marker advances without changing task records', (
    tester,
  ) async {
    var now = _now;
    final c = PlannerController(
      initial: {},
      persist: (_) async {},
      catalog: [],
      clock: () => now,
    );
    await c.evaluate();
    await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
    final marker = find.byKey(const ValueKey('timeline-now'));
    final before = tester.widget<PositionedDirectional>(marker).top!;
    final state = c.exportState;
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PositionedDirectional>(marker).top!,
      greaterThan(before),
    );
    expect(c.exportState, state);
    expect(c.ledger, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
