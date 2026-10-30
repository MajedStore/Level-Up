// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'package:flutter/widgets.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_reminder_schedule.dart';
import 'package:streak/services/planner_repository.dart';

/// Read-only schedule projection. Canonical reconciliation is performed by the
/// same controller separately, while the native transaction gate is held.
class PlannerReminderProjection {
  PlannerReminderProjection.fromMap(Map<String, dynamic> raw) {
    if (raw['schemaVersion'] != 1 || raw['plannerState'] is! Map) {
      throw const FormatException('Unsupported background planner projection.');
    }
    final original = detachedPlannerMap(raw['plannerState'] as Map);
    // Validate the mirror without normalizing or modifying its canonical data.
    PlannerState.fromMap(original);
    _plannerState = original;
    _values = MapPlannerReminderStorage(
      raw['values'] as Map? ?? {},
    ).exportValues;
    _settings = detachedPlannerMap(raw['settings'] as Map? ?? {});
  }

  late final Map<String, dynamic> _plannerState;
  late final Map<String, dynamic> _values;
  late final Map<String, dynamic> _settings;
  Map<String, dynamic> get plannerState => detachedPlannerMap(_plannerState);
  Map<String, dynamic> get values => detachedPlannerMap(_values);
  String get locale => _settings['locale'] as String? ?? 'en';
  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'plannerState': plannerState,
    'values': values,
    'settings': detachedPlannerMap(_settings),
  };

  List<PlannerOccurrence> occurrences(DateTime now) {
    final controller = PlannerController(
      initial: plannerState,
      clock: () => now,
      persist: (_) =>
          throw StateError('A reminder projection cannot save planner data.'),
    );
    try {
      return projectPlannerOccurrences(controller, now: now, values: values);
    } finally {
      controller.dispose();
    }
  }
}

/// Shared foreground/background projection. Calendar recurrence and overrides
/// remain in the existing domain engine; no second recurrence implementation.
List<PlannerOccurrence> projectPlannerOccurrences(
  PlannerController controller, {
  DateTime? now,
  Map<String, dynamic> values = const {},
  int horizonDays = PlannerReminderSchedule.horizonDays,
}) {
  if (horizonDays < 1 || horizonDays > 366) {
    throw ArgumentError.value(horizonDays, 'horizonDays');
  }
  final at = now ?? controller.now;
  final today = plannerDay(at);
  final until = plannerAddDays(today, horizonDays);
  final active = {
    for (final instance in controller.instances)
      if (instance.status == ChallengeStatus.active &&
          at.isBefore(instance.deadline))
        instance.id,
  };
  final found = <String, PlannerOccurrence>{};
  void add(PlannerOccurrence occurrence) {
    if (!occurrence.isChallenge || active.contains(occurrence.challengeId)) {
      found[occurrence.id] = occurrence;
    }
  }

  // The model permits a seven-day lead time. Include those origin dates, then
  // constrain actual reminder instants to the desired window below.
  for (var offset = -1; offset < horizonDays + 7; offset++) {
    for (final occurrence in controller.occurrences(
      plannerAddDays(today, offset),
    )) {
      add(occurrence);
    }
  }
  final rawSnoozes = values['plannerSnoozes'];
  final snoozes = <String, DateTime>{};
  if (rawSnoozes is Map) {
    for (final entry in rawSnoozes.entries) {
      final when = entry.value is String
          ? DateTime.tryParse(entry.value as String)
          : null;
      if (entry.key is! String || when == null || !when.isAfter(at)) {
        continue;
      }
      final id = entry.key as String;
      snoozes[id] = when.toLocal();
      final occurrence = controller.occurrenceById(id);
      if (occurrence != null) add(occurrence);
    }
  }
  final requests = PlannerReminderSchedule.build(
    found.values,
    now: at,
    snoozes: snoozes,
  );
  return [
    for (final request in requests)
      if (request.fireAt.isBefore(until)) found[request.occurrenceId]!,
  ];
}

/// Determines whether Android needs a periodic refresh at all, including future
/// one-off reminders and explicitly overridden challenge task preferences.
bool hasPlannerReminderDefinitions(PlannerController controller) {
  final state = PlannerState.fromMap(controller.exportState);
  final now = controller.now;
  final candidates = <String>{...state.overrides.keys};
  for (final item in state.items) {
    final reminder = state.reminders[item.id] ?? item.reminder;
    if (item.recurrence != PlannerRecurrence.once && reminder.enabled) {
      // Recurring definitions can begin beyond the currently projected window.
      return true;
    }
    if (item.recurrence == PlannerRecurrence.once) {
      candidates.add('${item.id}@${plannerDateKey(item.date)}');
    }
  }
  candidates.addAll(state.reminders.keys.where((key) => key.contains('@')));
  for (final instance in state.instances) {
    if (instance.status != ChallengeStatus.active ||
        !now.isBefore(instance.deadline)) {
      continue;
    }
    for (final task in instance.snapshot.leafTasks) {
      for (final offset in task.dayOffsets.toSet()) {
        final day = plannerAddDays(instance.startDate, offset);
        candidates.add('${instance.id}/${task.id}@${plannerDateKey(day)}');
      }
    }
  }
  for (final id in candidates) {
    final occurrence = controller.occurrenceById(id);
    if (occurrence != null &&
        PlannerReminderSchedule.build([occurrence], now: now).isNotEmpty) {
      return true;
    }
  }
  return false;
}

typedef PlannerBackgroundScheduler =
    Future<PlannerReminderSyncResult> Function(
      List<PlannerOccurrence> occurrences, {
      required DateTime now,
      required PlannerReminderStorage storage,
    });

/// Called by the Android WorkManager entrypoint with its native mutex held.
/// This function performs no LocalStore initialization or Hive writes. Migrated
/// Android documents are canonical, so deadline outcomes and ledger changes are
/// returned for one AtomicFile commit under the worker's existing native gate.
Future<bool> runPlannerBackgroundRefresh({
  PlannerRefreshBridge? bridge,
  DateTime Function()? clock,
  PlannerBackgroundScheduler? scheduler,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = bridge ?? PlannerRefreshBridge();
  MapPlannerReminderStorage? storage;
  Map<String, dynamic>? canonicalState;
  DateTime? nextDeadline;
  try {
    final raw = await platform.readBackground();
    if (raw == null) {
      throw StateError('No background planner projection is available.');
    }
    final now = (clock ?? DateTime.now)();
    var current = raw;
    if (PlannerRepository.isCanonical(raw)) {
      final controller = PlannerController(
        initial: PlannerRepository.stateIn(raw)!,
        clock: () => now,
        persist: (state) async {
          canonicalState = state;
        },
      );
      try {
        await controller.evaluate();
        canonicalState = controller.exportState;
        nextDeadline = controller.nextSelectionDeadline;
        current = {...raw, 'plannerState': canonicalState};
      } finally {
        controller.dispose();
      }
    }
    final projection = PlannerReminderProjection.fromMap(current);
    storage = MapPlannerReminderStorage(projection.values);
    if (canonicalState != null) {
      await platform.checkpointBackground(
        plannerState: canonicalState!,
        values: storage.exportValues,
      );
    }
    final occurrences = projection.occurrences(now);
    final result = scheduler != null
        ? await scheduler(occurrences, now: now, storage: storage)
        : await _scheduleBackground(
            occurrences,
            now: now,
            storage: storage,
            locale: projection.locale,
          );
    final success = result.errors.isEmpty;
    await platform.completeBackground(
      values: storage.exportValues,
      success: success,
      plannerState: canonicalState,
      nextDeadline: nextDeadline,
      error: success ? null : result.errors.join('; '),
    );
    return success;
  } catch (error) {
    debugPrint('Background planner reminder refresh failed: $error');
    try {
      await platform.completeBackground(
        values: storage?.exportValues ?? {},
        success: false,
        plannerState: canonicalState,
        nextDeadline: nextDeadline,
        error: '$error',
      );
    } catch (completionError) {
      debugPrint(
        'Could not report background reminder failure: $completionError',
      );
    }
    return false;
  }
}

Future<PlannerReminderSyncResult> _scheduleBackground(
  List<PlannerOccurrence> occurrences, {
  required DateTime now,
  required PlannerReminderStorage storage,
  String locale = 'en',
}) => NotificationService().reschedulePlanner(
  occurrences,
  now: now,
  storage: storage,
  backgroundInitialization: true,
  locale: locale,
);
