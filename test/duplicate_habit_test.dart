import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/data/reminder.dart';
import 'package:streak/features/habits/data/substep.dart';
import 'package:streak/features/habits/pages/habit_form_page.dart';
import 'package:streak/features/habits/pages/home_page.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/habits/widgets/habit_card.dart';

import 'support/app_harness.dart';

HabitsController _controller(WidgetTester tester) =>
    Provider.of<HabitsController>(
      tester.element(find.byType(HomePage)),
      listen: false,
    );

List<String> _names(WidgetTester tester) => [
  for (final habit in _controller(tester).habits) habit.name,
];

Future<void> _duplicateFirstHabit(WidgetTester tester) async {
  await tester.longPress(find.byType(HabitCard).first);
  await tester.pumpAndSettle();
  await _tapSheetAction(tester, 'Duplicate habit');
}

Future<void> _tapSheetAction(WidgetTester tester, String label) async {
  final tile = tester.widget<ListTile>(
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first,
  );
  await tester.runAsync(() async {
    tile.onTap!();
    await Future<void>.delayed(const Duration(milliseconds: 900));
  });
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final button = tester.widget<TextButton>(
    find
        .ancestor(of: find.text('Save'), matching: find.byType(TextButton))
        .first,
  );
  await tester.runAsync(() async {
    button.onPressed!();
  });
  await tester.pumpAndSettle();
  // The store write precedes reminder scheduling and the final route pop.
  // Wait for the entire save, including its asynchronous side effects.
  for (
    var wait = 0;
    wait < 100 && find.byType(HabitFormPage).evaluate().isNotEmpty;
    wait++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }
  expect(
    find.byType(HabitFormPage),
    findsNothing,
    reason: 'Saving must close the form before reading the home controller.',
  );
}

EditableText _nameField(WidgetTester tester, String name) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .firstWhere(
      (field) => field.controller.text == name,
    );

Habit _scheduled() =>
    testHabit(
      id: 'a',
      name: 'Run',
      order: 0,
      kind: HabitKind.quantitative,
      perDayTarget: 5,
      unitLabel: 'km',
      category: 'Fitness',
      startMinute: 7 * 60,
      durationMinutes: 30,
      done: lastDays(3),
    ).copyWith(
      icon: 'run',
      description: 'Before breakfast',
      interval: HabitInterval.weekdays,
      scheduleWeekdays: const [1, 3, 5],
      reminders: const [
        Reminder(id: 'r1', hour: 7, minute: 0, days: [1, 3, 5]),
      ],
      restDays: const [6, 7],
      difficulty: 2,
    );

void main() {
  useEmptyStore();

  testWidgets('duplicating opens the form ready to rename', (tester) async {
    await seedHabits(tester, [testHabit(id: 'a', name: 'Run')]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);

    expect(find.byType(HabitFormPage), findsOneWidget);
    final field = _nameField(tester, 'Run');
    expect(field.focusNode.hasFocus, isTrue);
    expect(
      field.controller.selection,
      const TextSelection.collapsed(offset: 3),
    );
  });

  testWidgets('saving the copy keeps its settings but not its history', (
    tester,
  ) async {
    await seedHabits(tester, [_scheduled()]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);
    await _save(tester);

    final habits = _controller(tester).habits;
    expect(habits.length, 2);
    final source = habits.first;
    final copy = habits.last;

    expect(copy.id, isNot(source.id));
    expect(copy.name, source.name);
    expect(copy.icon, source.icon);
    expect(copy.color, source.color);
    expect(copy.category, source.category);
    expect(copy.description, source.description);
    expect(copy.kind, source.kind);
    expect(copy.perDayTarget, source.perDayTarget);
    expect(copy.unitLabel, source.unitLabel);
    expect(copy.interval, source.interval);
    expect(copy.scheduleWeekdays, source.scheduleWeekdays);
    expect(copy.startMinute, source.startMinute);
    expect(copy.durationMinutes, source.durationMinutes);
    expect(copy.difficulty, source.difficulty);
    expect(copy.restDays, source.restDays);
    expect(copy.reminders.length, source.reminders.length);

    expect(copy.completions, isEmpty);
    expect(source.completions.length, 3);
  });

  testWidgets('the checklist comes along', (tester) async {
    await seedHabits(tester, [
      testHabit(
        id: 'a',
        name: 'Gym',
        substeps: const [
          Substep(id: 's1', title: 'Stretch'),
          Substep(id: 's2', title: 'Lift'),
        ],
      ),
    ]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);
    await _save(tester);

    final copy = _controller(tester).habits.last;
    expect([for (final step in copy.substeps) step.title], ['Stretch', 'Lift']);
  });

  testWidgets('the copy lands at the bottom of the list', (tester) async {
    await seedHabits(tester, [
      testHabit(id: 'a', name: 'Run', order: 0),
      testHabit(id: 'b', name: 'Water', order: 1),
    ]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);
    await _save(tester);

    expect(_names(tester), ['Run', 'Water', 'Run']);
  });

  testWidgets('closing the form without saving creates nothing', (
    tester,
  ) async {
    await seedHabits(tester, [testHabit(id: 'a', name: 'Run')]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    expect(_names(tester), ['Run']);
    expect(LocalStore.readHabits().length, 1);
  });

  testWidgets('the copy is written to the store, without the history', (
    tester,
  ) async {
    await seedHabits(tester, [_scheduled()]);
    await pumpScreen(tester, const HomePage());

    await _duplicateFirstHabit(tester);
    await _save(tester);

    final stored = LocalStore.readHabits().values
        .where((habit) => habit.id != 'a')
        .toList();
    expect(stored.length, 1);
    expect(stored.single.completions, isEmpty);
    expect(stored.single.scheduleWeekdays, const [1, 3, 5]);
    expect(stored.single.reminders.length, 1);
  });
}
