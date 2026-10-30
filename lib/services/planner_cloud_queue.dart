// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/cloud_models.dart';

const plannerCloudCacheKey = 'levelUpCloudCache';
const plannerCloudProjectionKey = 'cloudSync';

Object? _ordered(Object? value) {
  // JSON numbers have one representation in Node, whereas Dart models retain
  // doubles for quantities. 0 and 0.0 must not manufacture a new mutation.
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) return value.map(_ordered).toList();
  return value;
}

/// Clock high-water updates do not constitute a user mutation. All other
/// records, including worker-produced deadline events, are synchronization data.
String cloudFingerprint(
  Map<String, dynamic> state,
  Map<String, dynamic> settings,
) {
  final meaningful = PlannerState.fromMap(state).toMap()
    ..remove('lastObservedAt');
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(
            _ordered({
              'state': meaningful,
              'settings': settings,
            }),
          ),
        ),
      )
      .toString();
}

CloudCache queueCloudTransition(
  CloudCache cache,
  Map<String, dynamic> state,
  Map<String, dynamic> settings,
) {
  if (cache.ownerId == null) return cache;
  final fingerprint = cloudFingerprint(state, settings);
  if (cache.lastQueuedFingerprint == fingerprint) return cache;
  // Fail the new write visibly before touching either authority. Retain every
  // earlier checkpoint; never truncate or coalesce history to make room.
  if (cache.pending.length >= 256 ||
      utf8.encode(jsonEncode(state)).length > 1500000) {
    throw StateError('cloud_queue_full');
  }
  return CloudCache.fromMap({
    ...cache.toMap(),
    'lastQueuedFingerprint': fingerprint,
    'pending': [
      ...cache.pending.map((m) => m.toMap()),
      CloudMutation(
        mutationId: const Uuid().v4(),
        baseRevision: cache.revision + cache.pending.length,
        state: state,
        settings: settings,
        timeZone: cache.timeZone ?? 'UTC',
      ).toMap(),
    ],
  });
}
