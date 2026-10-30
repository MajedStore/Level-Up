import 'package:streak/features/planner/data/planner_models.dart';

/// A concrete notification, independent of widgets and the platform plugin.
class PlannerReminderRequest {
  const PlannerReminderRequest({
    required this.occurrenceId,
    required this.title,
    required this.body,
    required this.fireAt,
    this.sound = 'default',
    this.vibrate = true,
  });

  final String occurrenceId;
  final String title;
  final String body;
  final DateTime fireAt;
  final String sound;
  final bool vibrate;

  Map<String, Object?> toMap() => {
    'occurrenceId': occurrenceId,
    'title': title,
    'body': body,
    'fireAt': fireAt.toUtc().toIso8601String(),
    'sound': sound,
    'vibrate': vibrate,
  };

  factory PlannerReminderRequest.fromMap(Map map) => PlannerReminderRequest(
    occurrenceId: map['occurrenceId'] as String,
    title: map['title'] as String,
    body: map['body'] as String? ?? '',
    fireAt: DateTime.parse(map['fireAt'] as String).toLocal(),
    sound: map['sound'] as String? ?? 'default',
    vibrate: map['vibrate'] as bool? ?? true,
  );
}

class PlannerReminderSchedule {
  const PlannerReminderSchedule._();

  static const horizonDays = 28;
  static const idBase = 1200000000;
  static const idRange = 800000000;

  /// Stable across Dart processes; String.hashCode is not a storage identifier.
  static int digest(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }

  static List<PlannerReminderRequest> build(
    Iterable<PlannerOccurrence> occurrences, {
    required DateTime now,
    Map<String, DateTime> snoozes = const {},
    String challengeLabel = 'Challenge task',
  }) {
    final unique = <String, PlannerReminderRequest>{};
    for (final occurrence in occurrences) {
      final reminder = occurrence.item.reminder;
      final validUntil = occurrence.validUntil;
      if (!reminder.enabled ||
          occurrence.record.status != CompletionStatus.pending ||
          (validUntil != null && !now.isBefore(validUntil))) {
        continue;
      }
      final start = occurrence.start;
      final DateTime at;
      if (snoozes[occurrence.id] case final snoozed?) {
        at = snoozed;
      } else if (reminder.minute case final minute?) {
        final day = occurrence.day;
        at = DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
      } else if (start != null) {
        at = start.subtract(Duration(minutes: reminder.offsetMinutes));
      } else {
        continue;
      }
      if (!at.isAfter(now)) continue;
      if (validUntil != null && !at.isBefore(validUntil)) continue;
      unique[occurrence.id] = PlannerReminderRequest(
        occurrenceId: occurrence.id,
        title: occurrence.title,
        body: occurrence.isChallenge
            ? '$challengeLabel · ${occurrence.item.description}'
            : occurrence.item.description,
        fireAt: at,
        sound: reminder.sound,
        vibrate: reminder.vibrate,
      );
    }
    return unique.values.toList()..sort((a, b) {
      final time = a.fireAt.compareTo(b.fireAt);
      return time == 0 ? a.occurrenceId.compareTo(b.occurrenceId) : time;
    });
  }

  static Map<String, int> allocateIds(
    Iterable<String> keys, {
    Map<String, int> previous = const {},
  }) {
    final sorted = keys.toSet().toList()..sort();
    final result = <String, int>{};
    final used = <int>{};
    for (final key in sorted) {
      final old = previous[key];
      if (old != null &&
          old >= idBase &&
          old < idBase + idRange &&
          used.add(old)) {
        result[key] = old;
      }
    }
    for (final key in sorted) {
      if (result.containsKey(key)) continue;
      var candidate = idBase + digest(key) % idRange;
      while (!used.add(candidate)) {
        candidate = idBase + (candidate - idBase + 1) % idRange;
      }
      result[key] = candidate;
    }
    return result;
  }
}

class PlannerReminderSyncResult {
  const PlannerReminderSyncResult({
    required this.ids,
    required this.scheduled,
    required this.permissionGranted,
    required this.exact,
    this.errors = const [],
  });

  final Map<String, int> ids;
  final int scheduled;
  final bool permissionGranted;
  final bool exact;
  final List<String> errors;

  String get message {
    if (!permissionGranted) {
      return 'Notifications are disabled. Allow notifications in Android settings '
          'to receive reminders.';
    }
    if (errors.isNotEmpty) {
      return 'Some reminders could not be scheduled: ${errors.first}';
    }
    return exact
        ? '$scheduled reminders scheduled. Android battery settings may affect delivery.'
        : '$scheduled reminders scheduled with approximate timing. Android may '
              'delay reminders because exact-alarm access is unavailable.';
  }
}

/// Reconciliation is injectable so denial, edits and deletion can be verified
/// without pretending that a desktop test proves Android notification delivery.
class PlannerReminderSync {
  const PlannerReminderSync._();

  static Future<PlannerReminderSyncResult> apply({
    required Iterable<PlannerReminderRequest> requests,
    required Map<String, int> previousIds,
    required bool permissionGranted,
    required bool exact,
    required Future<void> Function(int id) cancel,
    required Future<void> Function(
      int id,
      PlannerReminderRequest request,
      bool exact,
    )
    schedule,
    Set<int> pendingIds = const {},
  }) async {
    final byKey = {
      for (final request in requests) request.occurrenceId: request,
    };
    final ids = permissionGranted
        ? PlannerReminderSchedule.allocateIds(byKey.keys, previous: previousIds)
        : <String, int>{};
    final errors = <String>[];
    final stale = {...previousIds.values, ...pendingIds}..removeAll(ids.values);
    for (final id in stale) {
      try {
        await cancel(id);
      } catch (error) {
        errors.add('Cancellation failed: $error');
      }
    }
    var scheduled = 0;
    for (final entry in ids.entries) {
      try {
        await schedule(entry.value, byKey[entry.key]!, exact);
        scheduled++;
      } catch (error) {
        errors.add('Scheduling failed: $error');
      }
    }
    return PlannerReminderSyncResult(
      ids: ids,
      scheduled: scheduled,
      permissionGranted: permissionGranted,
      exact: exact,
      errors: errors,
    );
  }
}
