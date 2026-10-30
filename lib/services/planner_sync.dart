import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/planner_background.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_repository.dart';

/// Reconcile only planner notifications; legacy habit and to-do reminders stay intact.
Future<void> reschedulePlannerReminders(
  PlannerController controller,
) => PlannerRefreshBridge().withLease((lease) async {
  // The worker may have extended the window since the last foreground run.
  // Merge its auxiliary identifiers without importing any planner/XP data.
  final storage = MapPlannerReminderStorage(_reminderValues(lease));
  final latest = PlannerRepository.stateIn(lease.previousProjection);
  final effective = latest == null
      ? controller
      : PlannerController(
          initial: latest,
          clock: () => controller.now,
          persist: (_) async {},
        );
  try {
    final now = effective.now;
    // Publish the committed rules before touching Android alarms. If the app
    // exits during platform reconciliation, the worker can recover from the
    // current task state instead of reviving an older notification projection.
    await _publish(effective, lease, storage.exportValues);
    await NotificationService().reschedulePlanner(
      projectPlannerOccurrences(
        effective,
        now: now,
        values: storage.exportValues,
      ),
      now: now,
      storage: storage,
    );
    await _writeReminderValues(storage.exportValues);
    await _publish(effective, lease, storage.exportValues);
  } finally {
    if (!identical(effective, controller)) effective.dispose();
  }
});

Map<String, dynamic> _reminderValues(PlannerRefreshLease lease) {
  final raw = lease.previousProjection?['values'];
  final previous = raw is Map
      ? Map<String, dynamic>.from(raw)
      : const <String, dynamic>{};
  return {
    for (final key in plannerReminderValueKeys)
      if (key == 'plannerReminderStatus')
        key: LocalStore.setting(key, '')
      else
        key: {
          if (previous[key] is Map)
            ...Map<String, dynamic>.from(previous[key] as Map),
          ...LocalStore.settingMap(key),
        },
  };
}

Future<void> _writeReminderValues(Map<String, dynamic> values) async {
  for (final entry in values.entries) {
    if (plannerReminderValueKeys.contains(entry.key)) {
      await LocalStore.writeSetting(entry.key, entry.value as Object);
    }
  }
}

Future<void> _publish(
  PlannerController controller,
  PlannerRefreshLease lease,
  Map<String, dynamic> values,
) async {
  await lease.publish({
    ...?lease.previousProjection,
    'schemaVersion': 1,
    'plannerState': controller.exportState,
    'values': values,
    'settings': {'locale': LocalStore.setting('locale', 'en')},
  });
  await PlannerRefreshBridge().configure(
    // Daily commitments require reconciliation even without task reminders.
    enabled: true,
    deadline: controller.nextSelectionDeadline,
  );
}

Future<void> refreshPlanner(PlannerController controller) async {
  await controller.evaluate();
  await reschedulePlannerReminders(controller);
}

/// Notification actions use the same native lease as scheduled refreshes. Resolve
/// again after waiting so completed/ended tasks cannot acquire a stale snooze.
Future<bool> snoozePlannerReminder(
  PlannerController controller,
  String occurrenceId,
) => PlannerRefreshBridge().withLease((lease) async {
  await _writeReminderValues(_reminderValues(lease));
  final latest = PlannerRepository.stateIn(lease.previousProjection);
  final effective = latest == null
      ? controller
      : PlannerController(
          initial: latest,
          clock: () => controller.now,
          persist: (_) async {},
        );
  try {
    final occurrence = effective.occurrenceById(occurrenceId);
    if (occurrence == null) return false;
    final snoozed = await NotificationService().snoozePlanner(
      occurrenceId,
      occurrence: occurrence,
    );
    await _publish(effective, lease, _reminderValues(lease));
    return snoozed;
  } finally {
    if (!identical(effective, controller)) effective.dispose();
  }
});

/// Used only by the explicit, confirmed data wipe flow.
Future<void> clearPlannerReminderProjection() =>
    PlannerRefreshBridge().withLease((lease) => lease.clear());
