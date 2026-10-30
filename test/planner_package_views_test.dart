import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/pages/planner_challenges_page.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/l10n/app_localizations.dart';

final _day = DateTime(2026, 10, 29, 12);
PlannerController _controller() => PlannerController(
  initial: {},
  clock: () => _day,
  persist: (_) async {},
  catalog: [],
);

ChallengeTemplate _tree() => const ChallengeTemplate(
  id: 'workout',
  name: 'Workout ABC',
  categoryName: 'My fitness',
  difficulty: ChallengeDifficulty.hard,
  rewardMode: ChallengeRewardMode.packageOnly,
  completionXp: 80,
  failurePenalty: 12,
  tasks: [
    ChallengeTaskDefinition(
      id: 'group',
      title: 'Workout',
      type: ChallengeTaskType.group,
    ),
    ChallengeTaskDefinition(
      id: 'warmup',
      title: 'Warm-up',
      type: ChallengeTaskType.group,
      parentId: 'group',
    ),
    ChallengeTaskDefinition(
      id: 'prepare',
      title: 'Prepare',
      parentId: 'warmup',
    ),
    ChallengeTaskDefinition(id: 'move', title: 'Move', parentId: 'warmup'),
    ChallengeTaskDefinition(id: 'stretch', title: 'Stretch', parentId: 'group'),
    ChallengeTaskDefinition(
      id: 'optional',
      title: 'Optional',
      parentId: 'group',
      mandatory: false,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  PlannerController controller,
  Widget page, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.dark(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final theme = AppTypography.forLocale(
            Theme.of(context),
            Localizations.localeOf(context),
          );
          return Theme(
            data: theme,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: child!,
              ),
            ),
          );
        },
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    'nested groups derive progress and leaves open original records',
    (tester) async {
      final c = _controller();
      final instance = await c.startChallenge(_tree());
      final id = '${instance.id}/prepare@2026-10-29';
      await _pump(tester, c, ChallengeInstancePage(instanceId: instance.id));
      expect(find.text('0/3 required tasks complete'), findsOneWidget);
      expect(find.text('Warm-up'), findsNothing);
      await _tap(tester, find.text('Workout'));
      expect(find.text('0/2 required tasks complete'), findsOneWidget);
      expect(find.text('Mark complete'), findsNothing);
      final before = c.exportState['records'];
      await _tap(tester, find.text('Warm-up'));
      expect(c.exportState['records'], before);
      await _tap(tester, find.text('Prepare'));
      expect(
        tester
            .widget<PlannerTaskPage>(find.byType(PlannerTaskPage))
            .occurrence
            .id,
        id,
      );
      expect(find.textContaining('Completion: +'), findsNothing);
      await _tap(tester, find.text('Mark complete'));
      expect(c.occurrenceById(id)!.record.status, CompletionStatus.completed);
      expect(c.ledger, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1/3 required tasks complete'), findsOneWidget);
      expect(find.text('1/2 required tasks complete'), findsOneWidget);
      await c.complete('${instance.id}/move@2026-10-29');
      await c.complete('${instance.id}/stretch@2026-10-29');
      await tester.pumpAndSettle();
      expect(find.text('3/3 required tasks complete'), findsOneWidget);
      expect(c.taskNodeStatus(instance, 'group'), CompletionStatus.completed);
      expect(c.instances.single.status, ChallengeStatus.completed);
      expect(c.balance, 80);
      expect(c.ledger, hasLength(1));
      expect(
        (c.exportState['records'] as Map).keys.where(
          (key) => '$key'.contains('/group@') || '$key'.contains('/warmup@'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('preview shows category and one package reward without task XP', (
    tester,
  ) async {
    final c = _controller();
    final tree = _tree();
    final overnight = tree.copyWith(
      durationDays: 2,
      tasks: tree.tasks
          .map(
            (task) => task.id == 'stretch'
                ? task.copyWith(
                    type: ChallengeTaskType.scheduled,
                    startMinute: 1380,
                    durationMinutes: 120,
                  )
                : task,
          )
          .toList(),
    );
    await _pump(tester, c, ChallengePreviewPage(template: overnight));
    expect(find.text('My fitness'), findsOneWidget);
    expect(find.text('Hard'), findsNothing);
    expect(find.text('4 tasks'), findsOneWidget);
    await _tap(tester, find.text('Workout'));
    await _tap(tester, find.text('Warm-up'));
    await _tap(tester, find.text('Prepare'));
    expect(find.textContaining('Task reward'), findsNothing);
    expect(find.textContaining('Skip −'), findsNothing);
    final reward = find.text('Completion +80 XP');
    await tester.ensureVisible(reward);
    expect(reward, findsOneWidget);
    expect(find.text('Failure −12 XP'), findsOneWidget);
    expect(find.textContaining('Deadline: Nov 1, 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('legacy task detail keeps captured reward and skip rules', (
    tester,
  ) async {
    final c = _controller();
    final instance = await c.startChallenge(
      const ChallengeTemplate(
        id: 'legacy',
        name: 'Legacy',
        completionXp: 20,
        tasks: [
          ChallengeTaskDefinition(
            id: 'task',
            title: 'Original task',
            rewardXp: 7,
            skipPenalty: 3,
          ),
        ],
      ),
    );
    final occurrence = c
        .occurrences(_day)
        .where((o) => o.challengeId == instance.id)
        .single;
    await _pump(tester, c, PlannerTaskPage(occurrence: occurrence));
    expect(find.text('Completion: +7 XP'), findsOneWidget);
    expect(find.text('Skip with penalty'), findsOneWidget);
    await _tap(tester, find.text('Mark complete'));
    expect(c.balance, 27);
    expect(c.ledger, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('skip confirmation shows the actual deduction in $locale', (
      tester,
    ) async {
      final c = _controller();
      final state = c.exportState;
      state['ledger'] = [
        XpTransaction(
          id: 'old',
          reason: 'Preserved XP',
          change: 3,
          type: 'legacy_balance',
          at: _day,
          idempotencyKey: 'old',
        ).toMap(),
      ];
      c.dispose();
      final funded = PlannerController(
        initial: state,
        clock: () => _day,
        persist: (_) async {},
      );
      final instance = await funded.startChallenge(
        _tree().copyWith(skipPenalty: 7),
      );
      final id = '${instance.id}/prepare@2026-10-29';
      await _pump(
        tester,
        funded,
        PlannerTaskPage(occurrence: funded.occurrenceById(id)!),
        locale: Locale(locale),
        scale: 2,
      );
      final skip = find.text(plannerTextForLocale(locale, 'skipWithPenalty'));
      await tester.scrollUntilVisible(
        skip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, skip);
      final expected = plannerTextForLocale(locale, 'skipDeduction', {
        'xp': locale == 'ar' ? '٣' : '3',
      });
      expect(find.textContaining(expected), findsOneWidget);
      expect(
        find.textContaining(
          plannerTextForLocale(locale, 'skipPackageTaskInfo'),
        ),
        findsOneWidget,
      );
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      );
      await _tap(tester, confirm);
      expect(funded.balance, 0);
      expect(
        funded.ledger.where((e) => e.type == 'task_skip').single.change,
        -3,
      );
      expect(funded.instances.single.status, ChallengeStatus.active);
      expect(
        find.text(plannerTextForLocale(locale, 'skipWithPenalty')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      funded.dispose();
    });
  }

  testWidgets(
    'public group node filters the day and pending leaves without writing records',
    (tester) async {
      final c = _controller();
      final instance = await c.startChallenge(
        const ChallengeTemplate(
          id: 'dated-tree',
          name: 'Dated package',
          durationDays: 2,
          rewardMode: ChallengeRewardMode.packageOnly,
          completionXp: 40,
          tasks: [
            ChallengeTaskDefinition(
              id: 'today',
              title: 'Today group',
              type: ChallengeTaskType.group,
            ),
            ChallengeTaskDefinition(
              id: 'done',
              title: 'Finished today',
              parentId: 'today',
            ),
            ChallengeTaskDefinition(
              id: 'pending',
              title: 'Pending today',
              parentId: 'today',
            ),
            ChallengeTaskDefinition(
              id: 'future',
              title: 'Later task',
              parentId: 'today',
              dayOffsets: [1],
            ),
            ChallengeTaskDefinition(
              id: 'tomorrow',
              title: 'Tomorrow group',
              type: ChallengeTaskType.group,
            ),
            ChallengeTaskDefinition(
              id: 'next',
              title: 'Tomorrow child',
              parentId: 'tomorrow',
              dayOffsets: [1],
            ),
          ],
        ),
      );
      await c.complete('${instance.id}/done@2026-10-29');
      final occurrences = [
        ...c.occurrences(_day),
        ...c.occurrences(plannerAddDays(_day, 1)),
      ];
      final before = c.exportState;
      await _pump(
        tester,
        c,
        Scaffold(
          body: ListView(
            children: [
              for (final task in instance.snapshot.rootTasks)
                ChallengeTaskNode(
                  instance: instance,
                  task: task,
                  occurrences: occurrences,
                  day: _day,
                  pendingOnly: true,
                ),
            ],
          ),
        ),
      );
      expect(find.text('1/2 required tasks complete'), findsOneWidget);
      expect(find.text('Tomorrow group'), findsNothing);
      expect(find.text('Pending today'), findsNothing);
      await _tap(tester, find.text('Today group'));
      expect(find.text('Pending today'), findsOneWidget);
      expect(find.text('Finished today'), findsNothing);
      expect(find.text('Later task'), findsNothing);
      expect(find.text('Tomorrow child'), findsNothing);
      expect(c.exportState, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Arabic nested tree is RTL and readable at narrow width with 2x text',
    (tester) async {
      final c = _controller();
      final template = _tree().copyWith(
        name: 'تمرين ABC ١٢',
        categoryName: 'اللياقة الشخصية',
      );
      final instance = await c.startChallenge(template);
      await c.complete('${instance.id}/prepare@2026-10-29');
      await _pump(
        tester,
        c,
        ChallengeInstancePage(instanceId: instance.id),
        locale: const Locale('ar'),
        scale: 2,
      );
      final pageContext = tester.element(find.byType(ChallengeInstancePage));
      expect(Directionality.of(pageContext), TextDirection.rtl);
      expect(Theme.of(pageContext).textTheme.bodyMedium!.fontFamily, 'Cairo');
      final progress = find.text(
        pageContext.plannerText('groupProgress', {'done': '١', 'total': '٣'}),
      );
      await tester.ensureVisible(progress);
      expect(progress, findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Workout'));
      await _tap(tester, find.text('Warm-up'));
      final childProgress = find.text(
        pageContext.plannerText('groupProgress', {'done': '١', 'total': '٢'}),
      );
      await tester.ensureVisible(childProgress);
      expect(childProgress, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
