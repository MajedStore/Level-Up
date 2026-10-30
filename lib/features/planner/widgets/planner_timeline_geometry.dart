import 'dart:math' as math;
import 'package:streak/features/planner/data/planner_models.dart';

class PlannerTimelineEvent {
  PlannerTimelineEvent(this.occurrence, this.startMinute, this.endMinute);
  final PlannerOccurrence occurrence;
  final int startMinute;
  final int endMinute;
  int lane = 0;
  int laneCount = 1;
  int overlapGroup = 0;
}

/// Civil-time geometry, shared by display and scroll anchoring. Short occupied
/// spans expand locally instead of drawing 48px blocks over their neighbours.
/// Hour labels use the same mapping, including gaps and midnight clipping.
class PlannerDayLayout {
  PlannerDayLayout(
    DateTime date,
    Iterable<PlannerOccurrence> occurrences, {
    double textScale = 1,
  }) : day = plannerDay(date) {
    final next = plannerAddDays(day, 1);
    for (final occurrence in occurrences) {
      if (!occurrence.isScheduled) {
        unscheduled.add(occurrence);
        continue;
      }
      final start = occurrence.start!;
      final end = occurrence.end!;
      if (!start.isBefore(next) || !end.isAfter(day)) continue;
      final from = start.isBefore(day) ? 0 : start.hour * 60 + start.minute;
      final to = !end.isBefore(next) ? 1440 : end.hour * 60 + end.minute;
      events.add(PlannerTimelineEvent(occurrence, from, to));
    }
    events.sort((a, b) {
      final start = a.startMinute.compareTo(b.startMinute);
      return start != 0 ? start : b.endMinute.compareTo(a.endMinute);
    });
    final boundaries = <int>{
      0,
      1440,
      for (var minute = 0; minute <= 1440; minute += 60) minute,
      for (final event in events) ...[event.startMinute, event.endMinute],
    }.toList()..sort();
    _minutes = boundaries;
    final lengths = [
      for (var i = 1; i < boundaries.length; i++)
        (boundaries[i] - boundaries[i - 1]) * .60,
    ];
    // Smallest intervals first keep neighbouring short activities distinct.
    final byDuration = [...events]
      ..sort(
        (a, b) => (a.endMinute - a.startMinute).compareTo(
          b.endMinute - b.startMinute,
        ),
      );
    for (final event in byDuration) {
      final from = boundaries.indexOf(event.startMinute);
      final to = boundaries.indexOf(event.endMinute);
      final current = lengths
          .sublist(from, to)
          .fold<double>(0, (a, b) => a + b);
      final required =
          50 * math.max(1, textScale) +
          (event.endMinute - event.startMinute) * .18;
      if (current < required) {
        final factor = required / current;
        for (var i = from; i < to; i++) {
          lengths[i] *= factor;
        }
      }
    }
    _pixels = [0];
    for (final length in lengths) {
      _pixels.add(_pixels.last + length);
    }
    var group = <PlannerTimelineEvent>[];
    var groupEnd = -1;
    var groupId = 0;
    void finishGroup() {
      final ends = <int>[];
      for (final event in group) {
        var lane = ends.indexWhere((end) => end <= event.startMinute);
        if (lane < 0) {
          lane = ends.length;
          ends.add(event.endMinute);
        } else {
          ends[lane] = event.endMinute;
        }
        event.lane = lane;
      }
      for (final event in group) {
        event.laneCount = ends.length;
        event.overlapGroup = groupId;
      }
      groupId++;
      group = [];
    }

    for (final event in events) {
      if (event.startMinute >= groupEnd && group.isNotEmpty) finishGroup();
      group.add(event);
      groupEnd = math.max(groupEnd, event.endMinute);
    }
    finishGroup();
  }
  final DateTime day;
  final List<PlannerTimelineEvent> events = [];
  final List<PlannerOccurrence> unscheduled = [];
  late final List<int> _minutes;
  late final List<double> _pixels;
  double get height => _pixels.last;
  double yForMinute(num minute) {
    final value = minute.clamp(0, 1440);
    final i = _minutes.indexWhere((m) => m >= value);
    if (i <= 0) return 0;
    return _pixels[i - 1] +
        (_pixels[i] - _pixels[i - 1]) *
            (value - _minutes[i - 1]) /
            (_minutes[i] - _minutes[i - 1]);
  }

  double minuteForY(double y) {
    final value = y.clamp(0, height);
    final i = _pixels.indexWhere((p) => p >= value);
    if (i <= 0) return 0;
    return _minutes[i - 1] +
        (_minutes[i] - _minutes[i - 1]) *
            (value - _pixels[i - 1]) /
            (_pixels[i] - _pixels[i - 1]);
  }
}
