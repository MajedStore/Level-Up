// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';

import 'package:streak/features/planner/data/planner_models.dart';

/// Largest import accepted; real planner exports are far smaller.
const plannerImportMaxBytes = 10 * 1024 * 1024;

/// The `format` tag written by Settings > Data > Export.
const plannerBackupFormat = 'level-up-backup';

/// A planner-only backup file: schedule, challenges and XP, nothing else.
String encodePlannerBackup(Map<String, dynamic> state, DateTime exportedAt) =>
    const JsonEncoder.withIndent('  ').convert({
      'app': 'Level Up',
      'format': plannerBackupFormat,
      'version': 1,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'state': state,
    });

/// Extracts the planner state from an imported JSON file.
///
/// Accepts a Settings backup ([plannerBackupFormat]), the older account
/// export ("private-local-draft", whose `current.state` is the planner) or a
/// bare planner state. The result is validated by
/// [PlannerState.fromMap]; anything else throws a [FormatException], so a
/// wrong file never replaces data. An empty object is rejected rather than
/// treated as "no data".
Map<String, dynamic> plannerStateFromImport(String source) {
  if (source.length > plannerImportMaxBytes) {
    throw const FormatException('too_large');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('not_json');
  }
  if (decoded is! Map) throw const FormatException('not_an_object');
  Object? state = decoded;
  if (decoded['format'] == plannerBackupFormat) {
    state = decoded['state'];
  } else if (decoded['format'] == 'private-local-draft') {
    final current = decoded['current'];
    state = current is Map ? current['state'] : null;
  }
  if (state is! Map || state['schemaVersion'] == null) {
    throw const FormatException('not_planner_state');
  }
  final map = plannerMap(state);
  try {
    PlannerState.fromMap(map);
  } catch (_) {
    throw const FormatException('invalid_planner_state');
  }
  return map;
}
