// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Notification bookkeeping only. Implementations must not write planner data.
abstract interface class PlannerReminderStorage {
  Map<String, dynamic> readMap(String key);
  Future<void> writeValue(String key, Object value);
}

const plannerReminderValueKeys = {
  'plannerNotificationIds',
  'plannerReminderPayloads',
  'plannerSnoozes',
  'plannerReminderStatus',
};

Map<String, dynamic> detachedPlannerMap(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

/// The worker keeps a detached auxiliary document in memory. It never opens Hive.
class MapPlannerReminderStorage implements PlannerReminderStorage {
  MapPlannerReminderStorage([Map values = const {}])
    : _values = detachedPlannerMap(values) {
    if (_values.keys.any((key) => !plannerReminderValueKeys.contains(key))) {
      throw const FormatException(
        'Unexpected background reminder storage key.',
      );
    }
  }

  final Map<String, dynamic> _values;

  Map<String, dynamic> get exportValues => detachedPlannerMap(_values);

  @override
  Map<String, dynamic> readMap(String key) {
    final value = _values[key];
    return value is Map ? detachedPlannerMap(value) : {};
  }

  @override
  Future<void> writeValue(String key, Object value) async {
    if (!plannerReminderValueKeys.contains(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Only reminder metadata may be written.',
      );
    }
    _values[key] = jsonDecode(jsonEncode(value));
  }
}

/// Coordinates platform notification changes with the Android background worker.
/// The native mutex covers the whole lease, not only the snapshot read/write.
class PlannerRefreshBridge {
  PlannerRefreshBridge({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('streak/planner_refresh'),
      enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool enabled;
  static Future<void> _foregroundQueue = Future.value();

  Future<T> withLease<T>(
    Future<T> Function(PlannerRefreshLease lease) action,
  ) {
    final work = _foregroundQueue.then((_) => _withLease(action));
    // One rejected acquire or callback must not poison subsequent refreshes.
    _foregroundQueue = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  Future<T> _withLease<T>(
    Future<T> Function(PlannerRefreshLease lease) action,
  ) async {
    if (!enabled) {
      return action(PlannerRefreshLease._(this, null, null));
    }
    final response = await _channel.invokeMapMethod<String, dynamic>('acquire');
    final token = response?['lease'];
    if (token is! String || token.isEmpty) {
      throw StateError(
        'Android did not grant a planner reminder refresh lease.',
      );
    }
    final raw = response?['projection'];
    final lease = PlannerRefreshLease._(
      this,
      token,
      raw is Map ? detachedPlannerMap(raw) : null,
    );
    try {
      return await action(lease);
    } finally {
      await _channel.invokeMethod<void>('release', {'lease': token});
    }
  }

  Future<void> configure({bool enabled = true, DateTime? deadline}) async {
    if (this.enabled) {
      await _channel.invokeMethod<void>('configure', {
        'enabled': enabled,
        if (deadline != null) 'deadlineMillis': deadline.millisecondsSinceEpoch,
      });
    }
  }

  Future<void> requestRefresh() async {
    if (enabled) await _channel.invokeMethod<void>('refresh');
  }

  Future<Map<String, dynamic>?> readBackground() async {
    if (!enabled) return null;
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'readBackground',
    );
    return raw == null ? null : detachedPlannerMap(raw);
  }

  /// Commit accounting before potentially slow platform notification calls.
  /// Available only on the worker's channel while its native gate is held.
  Future<void> checkpointBackground({
    required Map<String, dynamic> plannerState,
    required Map<String, dynamic> values,
  }) async {
    if (!enabled) return;
    await _channel.invokeMethod<void>('checkpointBackground', {
      'plannerState': detachedPlannerMap(plannerState),
      'values': detachedPlannerMap(values),
    });
  }

  Future<void> completeBackground({
    required Map<String, dynamic> values,
    required bool success,
    Map<String, dynamic>? plannerState,
    DateTime? nextDeadline,
    String? error,
  }) async {
    if (!enabled) return;
    await _channel.invokeMethod<void>('completeBackground', {
      'values': detachedPlannerMap(values),
      'success': success,
      if (plannerState != null)
        'plannerState': detachedPlannerMap(plannerState),
      if (nextDeadline != null)
        'nextDeadlineMillis': nextDeadline.millisecondsSinceEpoch,
      if (error != null) 'error': error,
    });
  }
}

class PlannerRefreshLease {
  PlannerRefreshLease._(this._bridge, this._token, this._projection);
  final PlannerRefreshBridge _bridge;
  final String? _token;
  Map<String, dynamic>? _projection;
  Map<String, dynamic>? get previousProjection =>
      _projection == null ? null : detachedPlannerMap(_projection!);

  Future<void> publish(Map<String, dynamic> projection) async {
    if (!_bridge.enabled) return;
    await _bridge._channel.invokeMethod<void>('publish', {
      'lease': _token,
      'projection': detachedPlannerMap(projection),
    });
    _projection = detachedPlannerMap(projection);
  }

  Future<void> clear() async {
    if (!_bridge.enabled) return;
    await _bridge._channel.invokeMethod<void>('clear', {'lease': _token});
    _projection = null;
  }
}
