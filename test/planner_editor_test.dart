import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/pages/planner_editor_page.dart';
import 'support/app_harness.dart';

final _monday = DateTime(2026, 10, 26);
final _thursday = DateTime(2026, 10, 29);

Widget _editorLauncher(
  PlannerItem item,
  DateTime actualDay,
  DateTime anchorDay,
) => Scaffold(
  body: Builder(
    builder: (context) => TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlannerEditorPage(
            item: item,
            date: actualDay,
            occurrenceDay: anchorDay,
          ),
        ),
      ),
      child: const Text('Open editor'),
    ),
  ),
);

Future<void> _save(WidgetTester tester) async {
  final button = find.text('Save activity');
  ScaffoldMessenger.of(tester.element(button)).clearSnackBars();
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  useEmptyStore();

  testWidgets(
    'editing one occurrence preserves series anchor and moved override identity',
    (tester) async {
      final c = PlannerController(
        initial: {},
        persist: (_) async {},
        clock: () => _thursday,
      );
      final base = PlannerItem(
        id: 'university',
        title: 'University',
        date: _monday,
        startMinute: 8 * 60,
        endMinute: 14 * 60,
        recurrence: PlannerRecurrence.weekly,
        weekdays: [1, 2, 4],
      );
      await c.saveItem(base);
      final original = c.occurrences(_thursday).single;
      await pumpScreen(
        tester,
        _editorLauncher(original.item, original.day, _thursday),
        planner: c,
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'University lab',
      );
      await _save(tester);
      expect(c.items.single.title, 'University');
      expect(c.items.single.date, _monday);
      expect(c.occurrences(_thursday).single.title, 'University lab');
      expect(c.occurrences(DateTime(2026, 11, 2)).single.title, 'University');

      final movedDay = DateTime(2026, 10, 31);
      await c.saveItem(
        c.occurrenceById(original.id)!.item.copyWith(date: movedDay),
        occurrenceDay: _thursday,
      );
      final moved = c.occurrenceById(original.id)!;
      await pumpScreen(
        tester,
        _editorLauncher(moved.item, moved.day, _thursday),
        planner: c,
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Moved lab, edited again',
      );
      await _save(tester);
      expect(c.occurrences(movedDay).length, 1);
      expect(c.occurrences(movedDay).single.id, original.id);
      expect(c.occurrences(movedDay).single.title, 'Moved lab, edited again');
      expect(c.occurrences(_thursday), isEmpty);
      expect(c.items.single.date, _monday);
      expect(c.balance, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('choosing entire series retains the original start date', (
    tester,
  ) async {
    final c = PlannerController(
      initial: {},
      persist: (_) async {},
      clock: () => _thursday,
    );
    final base = PlannerItem(
      id: 'university',
      title: 'University',
      date: _monday,
      startMinute: 8 * 60,
      endMinute: 14 * 60,
      recurrence: PlannerRecurrence.weekly,
      weekdays: [1, 2, 4],
    );
    await c.saveItem(base);
    final o = c.occurrences(_thursday).single;
    await pumpScreen(
      tester,
      _editorLauncher(o.item, o.day, _thursday),
      planner: c,
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    final scope = find.byType(DropdownButtonFormField<bool>);
    await tester.ensureVisible(scope);
    await tester.tap(scope);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entire recurring series').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Updated university',
    );
    await _save(tester);
    expect(c.items.single.date, _monday);
    expect(c.items.single.recurrence, PlannerRecurrence.weekly);
    expect(c.occurrences(_monday).single.title, 'Updated university');
    expect(c.occurrences(_thursday).single.title, 'Updated university');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
