// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/planner_cloud_queue.dart';

/// Android's AtomicFile owns planner state. Hive retains the compatible backup
/// representation; only the foreground opens it. A native lease covers every
/// read/modify/write, including headless deadline reconciliation.
class PlannerRepository {
  PlannerRepository({PlannerRefreshBridge? bridge})
    : _bridge = bridge ?? PlannerRefreshBridge();

  final PlannerRefreshBridge _bridge;
  PlannerRefreshLease? _lease;

  static bool isCanonical(Map<String, dynamic>? value) =>
      value?['canonicalPlanner'] == true;

  static Map<String, dynamic>? stateIn(Map<String, dynamic>? value) {
    if (!isCanonical(value)) return null;
    final state = value!['plannerState'];
    if (state is! Map) {
      throw const FormatException('Missing authoritative planner state.');
    }
    final copy = detachedPlannerMap(state);
    PlannerState.fromMap(copy);
    return copy;
  }

  /// One-time, lossless migration. An older notification mirror never wins
  /// over the existing Hive data. Subsequent starts recover from AtomicFile.
  Future<void> initialize() => transaction(() async {
    final existing = stateIn(_lease?.previousProjection);
    final raw = existing ?? LocalStore.settingMap('levelUpState');
    final state = PlannerState.fromMap(raw).toMap();
    if (existing == null || !_sameStoredValue(raw, state)) {
      // Persist additive model migrations while holding the same transaction
      // gate as the headless worker, even when evaluation itself is a no-op.
      await save(state);
    }
    await LocalStore.writeSetting('levelUpState', state);
    final cache = _lease?.previousProjection?[plannerCloudProjectionKey];
    if (cache is Map) {
      await LocalStore.writeSetting(plannerCloudCacheKey, cloudMap(cache));
    }
  });

  Future<void> transaction(Future<void> Function() action) =>
      _bridge.withLease((lease) async {
        if (_lease != null) throw StateError('Nested planner transaction.');
        _lease = lease;
        try {
          await action();
        } finally {
          _lease = null;
        }
      });

  Future<Map<String, dynamic>?> loadLatest() async {
    if (!_bridge.enabled) return LocalStore.settingMap('levelUpState');
    final lease = _lease;
    if (lease == null) throw StateError('Planner read requires a lease.');
    final state = stateIn(lease.previousProjection);
    if (state != null &&
        !_sameStoredValue(state, LocalStore.settingMap('levelUpState'))) {
      await LocalStore.writeSetting('levelUpState', state);
    }
    // Explicit data wipe removes both representations. Never resurrect the
    // controller's pre-wipe cache when the authoritative file is absent.
    return state ?? LocalStore.settingMap('levelUpState');
  }

  Future<void> save(Map<String, dynamic> state) async {
    final normalized = PlannerState.fromMap(state).toMap();
    final lease = _lease;
    if (lease == null) throw StateError('Planner write requires a lease.');
    final rawCache = lease.previousProjection?[plannerCloudProjectionKey];
    final cache = CloudCache.fromMap(
      rawCache is Map
          ? cloudMap(rawCache)
          : LocalStore.settingMap(plannerCloudCacheKey),
    );
    final settings = {'locale': LocalStore.setting('locale', 'en')};
    final queued = queueCloudTransition(cache, normalized, settings);
    await lease.publish({
      ...?lease.previousProjection,
      'schemaVersion': 1,
      'canonicalPlanner': true,
      'plannerState': detachedPlannerMap(normalized),
      'values': lease.previousProjection?['values'] ?? <String, dynamic>{},
      'settings': settings,
      if (queued.ownerId != null) plannerCloudProjectionKey: queued.toMap(),
    });
    // If the process exits here, startup restores this mirror from AtomicFile.
    await LocalStore.writeSetting('levelUpState', normalized);
    if (queued.ownerId != null) {
      await LocalStore.writeSetting(plannerCloudCacheKey, queued.toMap());
    }
  }

  /// Use only after an explicit, validated backup restore, never on resume.
  Future<void> replaceFromHive() => transaction(() async {
    await save(LocalStore.settingMap('levelUpState'));
  });

  /// Include headless transactions in an export without opening Hive headlessly.
  Future<void> syncBackupMirror() => transaction(() async {
    final state = await loadLatest();
    if (state != null) await LocalStore.writeSetting('levelUpState', state);
  });

  /// The already-confirmed wipe holds the same gate until both authorities and
  /// reminder bookkeeping are cleared, so a worker cannot revive old data.
  Future<void> clear(Future<void> Function() wipe) => transaction(() async {
    await _lease!.clear();
    await wipe();
  });
}

// Native JSON maps may arrive in a different key order. A migration or mirror
// refresh is based on values, never on incidental serialization ordering.
bool _sameStoredValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) =>
              right.containsKey(key) && _sameStoredValue(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (i) => i,
        ).every((i) => _sameStoredValue(left[i], right[i]));
  }
  return left == right;
}
