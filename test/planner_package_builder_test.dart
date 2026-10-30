import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/pages/planner_package_editor_page.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/l10n/app_localizations.dart';

PlannerController _controller() => PlannerController(
  initial: {},
  catalog: [],
  persist: (_) async {},
  clock: () => DateTime(2026, 10, 29, 12),
);

Future<void> _open(
  WidgetTester tester,
  PlannerController controller, {
  ChallengeTemplate? template,
  String locale = 'en',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.dark(),
        builder: (context, child) => Theme(
          data: AppTypography.forLocale(
            Theme.of(context),
            Localizations.localeOf(context),
          ),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PlannerPackageEditorPage(template: template),
                ),
              ),
              child: const Text('Open builder'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open builder'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('package-primary-action')));

Future<void> _dialogName(WidgetTester tester, String name) async {
  final dialog = find.byType(AlertDialog);
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextFormField)),
    name,
  );
  await _tap(
    tester,
    find.descendant(of: dialog, matching: find.byType(FilledButton)),
  );
}

Future<void> _flexibleTask(
  WidgetTester tester,
  String name, {
  String locale = 'en',
}) async {
  await _tap(tester, find.text(plannerTextForLocale(locale, 'addTask')));
  await tester.enterText(
    find.byKey(const ValueKey('package-task-name')),
    name,
  );
  expect(find.byKey(const ValueKey('task-start-time')), findsNothing);
  expect(find.byKey(const ValueKey('task-end-time')), findsNothing);
  expect(find.byType(TextFormField), findsOneWidget);
  await _tap(tester, find.byKey(const ValueKey('save-package-task')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('fonts/Cairo/Cairo-$weight.ttf'));
    }
    await loader.load();
  });

  testWidgets(
    'guided builder creates categories, nested groups and one reward',
    (
      tester,
    ) async {
      final controller = _controller();
      await _open(tester, controller);
      await tester.enterText(
        find.byKey(const ValueKey('package-name')),
        'Morning',
      );
      expect(find.text('Difficulty'), findsNothing);
      expect(find.text('Duration in days'), findsNothing);
      await _tap(tester, find.text('New category'));
      await _dialogName(tester, 'Wellbeing');
      final categoryId = controller.categories.single.id;
      await _next(tester);
      await _flexibleTask(tester, 'Wake up');
      await _tap(tester, find.text('Add group'));
      await _dialogName(tester, 'Exercise');
      await _flexibleTask(tester, 'Push-ups');
      await _flexibleTask(tester, 'Pull-ups');
      await _tap(tester, find.text('Add group'));
      await _dialogName(tester, 'Stretch');
      await _flexibleTask(tester, 'Shoulders');
      await _tap(tester, find.text('Back to parent'));
      expect(find.text('Push-ups'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget);
      await _tap(tester, find.text('Package'));
      await _next(tester);
      expect(find.text('Your package'), findsOneWidget);
      expect(find.text('Shoulders'), findsOneWidget);
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '٨٠');
      await tester.enterText(fields.at(1), '٧');
      await tester.enterText(fields.at(2), '٣');
      await _next(tester);
      expect(find.text('Open builder'), findsOneWidget);
      final package = controller.templates.single;
      expect(package.name, 'Morning');
      expect(package.categoryId, categoryId);
      expect(package.categoryName, 'Wellbeing');
      expect(package.difficulty, isNull);
      expect(package.durationDays, 1);
      expect(package.completionXp, 80);
      expect(package.failurePenalty, 7);
      expect(package.skipPenalty, 3);
      expect(package.rewardMode, ChallengeRewardMode.packageOnly);
      expect(package.totalPossibleXp, 80);
      expect(package.tasks.where((task) => !task.isGroup).length, 4);
      expect(
        package.tasks.every(
          (task) => task.rewardXp == 0 && task.skipPenalty == 0,
        ),
        isTrue,
      );
      final exercise = package.tasks.firstWhere(
        (task) => task.title == 'Exercise',
      );
      final stretch = package.tasks.firstWhere(
        (task) => task.title == 'Stretch',
      );
      expect(stretch.parentId, exercise.id);
      expect(
        package.tasks.firstWhere((task) => task.title == 'Shoulders').parentId,
        stretch.id,
      );
      expect(package.validate, returnsNormally);
      expect(controller.ledger, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('scheduled controls derive duration; reminders remain optional', (
    tester,
  ) async {
    final controller = _controller();
    await _open(tester, controller);
    await tester.enterText(find.byKey(const ValueKey('package-name')), 'Study');
    await _next(tester);
    await _tap(tester, find.text('Add task'));
    await tester.enterText(
      find.byKey(const ValueKey('package-task-name')),
      'Read',
    );
    await _tap(tester, find.text('Scheduled'));
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byKey(const ValueKey('task-start-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-end-time')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('save-package-task')));
    expect(
      find.text(plannerTextForLocale('en', 'invalidTaskInterval')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('task-start-time')));
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await _tap(tester, find.text('OK'));
    await _tap(tester, find.byKey(const ValueKey('task-end-time')));
    await _tap(tester, find.text('OK'));
    await _tap(tester, find.text('Optional reminder'));
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('Apply to every occurrence'), findsNothing);
    await _tap(tester, find.text('Go back'));
    await _tap(tester, find.byKey(const ValueKey('save-package-task')));
    await _next(tester);
    await _next(tester);
    final task = controller.templates.single.tasks.single;
    expect(task.type, ChallengeTaskType.scheduled);
    expect(task.startMinute, 540);
    expect(task.durationMinutes, 30);
    expect(task.reminder.enabled, isFalse);
    expect(task.rewardXp, 0);
    expect(task.skipPenalty, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'new overnight task derives two internal days without duration UI',
    (tester) async {
      tester.binding.platformDispatcher.alwaysUse24HourFormatTestValue = true;
      addTearDown(
        tester.binding.platformDispatcher.clearAlwaysUse24HourTestValue,
      );
      final controller = _controller();
      await _open(tester, controller);
      await tester.enterText(
        find.byKey(const ValueKey('package-name')),
        'Night study',
      );
      await _next(tester);
      await _tap(tester, find.text('Add task'));
      await tester.enterText(
        find.byKey(const ValueKey('package-task-name')),
        'Study late',
      );
      await _tap(tester, find.text('Scheduled'));
      Future<void> chooseTime(String key, String hour) async {
        await _tap(tester, find.byKey(ValueKey(key)));
        await _tap(tester, find.byIcon(Icons.keyboard_outlined));
        final fields = find.descendant(
          of: find.byType(TimePickerDialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.at(0), hour);
        await tester.enterText(fields.at(1), '00');
        await _tap(tester, find.text('OK'));
      }

      await chooseTime('task-start-time', '23');
      await chooseTime('task-end-time', '23');
      await _tap(tester, find.byKey(const ValueKey('save-package-task')));
      expect(
        find.text(plannerTextForLocale('en', 'invalidTaskInterval')),
        findsOneWidget,
      );
      await chooseTime('task-end-time', '01');
      expect(find.textContaining('(+1 day)'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('save-package-task')));
      await _next(tester);
      expect(
        find.text(plannerTextForLocale('en', 'durationDays')),
        findsNothing,
      );
      expect(find.byType(TextFormField), findsNWidgets(3));
      await _next(tester);
      final package = controller.templates.single;
      expect(package.durationDays, 2);
      expect(package.tasks.single.startMinute, 1380);
      expect(package.tasks.single.durationMinutes, 120);
      expect(package.validate, returnsNormally);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('empty groups are focused for correction and siblings reorder', (
    tester,
  ) async {
    final controller = _controller();
    await _open(tester, controller);
    await tester.enterText(find.byKey(const ValueKey('package-name')), 'Tasks');
    await _next(tester);
    await _tap(tester, find.text('Add group'));
    await _dialogName(tester, 'Empty');
    await _next(tester);
    expect(find.text('Shape your tasks'), findsOneWidget);
    await _flexibleTask(tester, 'First');
    await _flexibleTask(tester, 'Second');
    final firstRow = find.ancestor(
      of: find.text('First'),
      matching: find.byType(ListTile),
    );
    await _tap(
      tester,
      find.descendant(
        of: firstRow,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await _tap(tester, find.text('Move down'));
    final firstY = tester.getTopLeft(find.text('First')).dy;
    final secondY = tester.getTopLeft(find.text('Second')).dy;
    expect(secondY, lessThan(firstY));
    await _next(tester);
    await _next(tester);
    final package = controller.templates.single;
    final group = package.tasks.firstWhere((task) => task.isGroup);
    expect(package.childrenOf(group.id).map((task) => task.title), [
      'Second',
      'First',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('editing preserves legacy conditions and migrates total reward', (
    tester,
  ) async {
    final controller = _controller();
    final legacy = ChallengeTemplate(
      id: 'legacy',
      name: 'Existing',
      description: 'A saved description',
      difficulty: ChallengeDifficulty.hard,
      durationDays: 3,
      completionXp: 40,
      failurePenalty: 9,
      tasks: const [
        ChallengeTaskDefinition(
          id: 'old-task',
          title: 'Old task',
          description: 'Saved detail',
          dayOffsets: [0, 2],
          steps: ['First step', 'Second step'],
          target: 4,
          unit: 'pages',
          rewardXp: 6,
          skipPenalty: 3,
        ),
      ],
    );
    await _open(tester, controller, template: legacy);
    await _next(tester);
    await _tap(tester, find.text('Old task'));
    expect(find.text('Saved task conditions'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    await _tap(tester, find.text('Saved task conditions'));
    expect(find.text('First step'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('package-task-name')),
      'Renamed',
    );
    await _tap(tester, find.byKey(const ValueKey('save-package-task')));
    await _next(tester);
    await _next(tester);
    final saved = controller.templates.single;
    expect(saved.durationDays, 3);
    expect(saved.description, legacy.description);
    expect(saved.difficulty, legacy.difficulty);
    expect(saved.completionXp, 52);
    expect(saved.rewardMode, ChallengeRewardMode.packageOnly);
    final oldMap = legacy.tasks.single.toMap()..['title'] = 'Renamed';
    expect(saved.tasks.single.toMap(), oldMap);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final convertToFlexible in [false, true]) {
    testWidgets(
      convertToFlexible
          ? 'scheduled reminder becomes explicit when task changes to flexible'
          : 'title-only editing preserves an existing overnight task interval',
      (tester) async {
        final controller = _controller();
        final task = ChallengeTaskDefinition(
          id: 'existing-time',
          title: 'Existing scheduled task',
          type: ChallengeTaskType.scheduled,
          startMinute: convertToFlexible ? 600 : 1380,
          durationMinutes: convertToFlexible ? 30 : 120,
          reminder: convertToFlexible
              ? const PlannerReminder(enabled: true, offsetMinutes: 15)
              : const PlannerReminder(),
        );
        final template = ChallengeTemplate(
          id: 'existing-package',
          name: 'Existing package',
          description: '',
          durationDays: 1,
          completionXp: 30,
          tasks: [task],
        );
        await _open(tester, controller, template: template);
        await _next(tester);
        await _tap(tester, find.text('Existing scheduled task'));
        if (convertToFlexible) {
          await _tap(tester, find.text('Flexible'));
          expect(find.byKey(const ValueKey('task-start-time')), findsNothing);
        } else {
          expect(find.textContaining('(+1 day)'), findsOneWidget);
        }
        await tester.enterText(
          find.byKey(const ValueKey('package-task-name')),
          'Edited name',
        );
        await _tap(tester, find.byKey(const ValueKey('save-package-task')));
        await _next(tester);
        await _next(tester);
        final saved = controller.templates.single.tasks.single;
        expect(saved.title, 'Edited name');
        if (convertToFlexible) {
          expect(saved.type, ChallengeTaskType.flexible);
          expect(saved.startMinute, isNull);
          expect(saved.reminder.enabled, isTrue);
          expect(saved.reminder.minute, 585);
          expect(saved.reminder.offsetMinutes, 15);
        } else {
          expect(saved.startMinute, 1380);
          expect(saved.durationMinutes, 120);
          expect(saved.type, ChallengeTaskType.scheduled);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets('categories can be renamed and reused through their stable ID', (
    tester,
  ) async {
    final controller = _controller();
    final category = await controller.saveCategory(name: 'Personal');
    await _open(tester, controller);
    await tester.enterText(find.byKey(const ValueKey('package-name')), 'Reuse');
    await _tap(tester, find.text('Personal'));
    await _tap(tester, find.text('Manage categories'));
    await _tap(tester, find.text('Personal').last);
    await _dialogName(tester, 'Wellness');
    expect(controller.categories.single.id, category.id);
    expect(controller.categories.single.name, 'Wellness');
    Navigator.pop(tester.element(find.text('Manage categories').last));
    await tester.pumpAndSettle();
    expect(find.text('Wellness'), findsOneWidget);
    await _next(tester);
    await _flexibleTask(tester, 'Walk');
    await _next(tester);
    await _next(tester);
    expect(controller.templates.single.categoryId, category.id);
    expect(controller.templates.single.categoryName, 'Wellness');
    await _tap(tester, find.text('Open builder'));
    expect(find.text('Wellness'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'Arabic builder fits 320px at 2x with nested navigation and Cairo',
    (
      tester,
    ) async {
      const locale = 'ar';
      String label(String key) => plannerTextForLocale(locale, key);
      final controller = _controller();
      await _open(tester, controller, locale: locale, width: 320, scale: 2);
      final context = tester.element(
        find.byKey(const ValueKey('package-name')),
      );
      expect(Directionality.of(context), TextDirection.rtl);
      expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'Cairo');
      await tester.enterText(
        find.byKey(const ValueKey('package-name')),
        'روتين الصباح',
      );
      await _tap(tester, find.text(label('newCategory')));
      await _dialogName(tester, 'العناية بالنفس');
      await _next(tester);
      await _tap(tester, find.text(label('addTaskGroup')));
      await _dialogName(tester, 'تمارين الصباح');
      await _flexibleTask(tester, 'تمارين الضغط', locale: locale);
      await _flexibleTask(tester, 'تمارين التمدد', locale: locale);
      await _tap(tester, find.text(label('returnToParent')));
      await _next(tester);
      expect(find.text(label('savePackage')), findsOneWidget);
      await _next(tester);
      expect(controller.templates.single.tasks.length, 3);
      expect(controller.templates.single.categoryName, 'العناية بالنفس');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
