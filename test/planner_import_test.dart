import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/planner_import.dart';

Map<String, dynamic> _state() => PlannerState(
  items: [
    PlannerItem(id: 'read', title: 'Read notes', date: DateTime(2026, 10, 29)),
  ],
).toMap();

void main() {
  test('accepts the app export and returns its current planner state', () {
    final export = jsonEncode({
      'app': 'Level Up',
      'format': 'private-local-draft',
      'version': 1,
      'current': {'version': 1, 'state': _state(), 'settings': {}},
    });
    final state = plannerStateFromImport(export);
    expect(PlannerState.fromMap(state).items.single.title, 'Read notes');
  });

  test('accepts a bare planner state', () {
    final state = plannerStateFromImport(jsonEncode(_state()));
    expect(PlannerState.fromMap(state).items.single.id, 'read');
  });

  test('rejects anything that is not planner data, including empty JSON', () {
    for (final source in [
      'not json',
      '[]',
      '{}',
      jsonEncode({'format': 'private-local-draft', 'current': {}}),
      jsonEncode({'habits': {}}),
      jsonEncode({'schemaVersion': 999, 'items': []}),
      jsonEncode({'schemaVersion': plannerSchemaVersionForTest, 'items': 1}),
    ]) {
      expect(
        () => plannerStateFromImport(source),
        throwsFormatException,
        reason: source,
      );
    }
  });
}

/// The current schema version, read from a freshly serialised state.
final plannerSchemaVersionForTest = PlannerState().toMap()['schemaVersion'];
