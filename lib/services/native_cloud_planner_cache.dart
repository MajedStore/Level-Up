// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/planner_cloud_queue.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_repository.dart';

/// Network-free account/cache adapter. The native planner lease serializes
/// foreground writes, cloud acknowledgements, account swaps and worker writes.
/// Archived account caches are encrypted by the injected secure archive store.
class NativeCloudPlannerCache implements CloudPlannerCache {
  NativeCloudPlannerCache({
    required CloudArchiveStore archives,
    PlannerRefreshBridge? bridge,
    Future<void> Function()? cancelNotifications,
    Future<void> Function()? beforeIsolation,
    Future<String> Function()? timeZone,
  }) : _archives = archives,
       _bridge = bridge ?? PlannerRefreshBridge(),
       _cancelNotifications = cancelNotifications,
       _beforeIsolation = beforeIsolation,
       _timeZone = timeZone;

  final CloudArchiveStore _archives;
  final PlannerRefreshBridge _bridge;
  final Future<void> Function()? _cancelNotifications;
  final Future<void> Function()? _beforeIsolation;
  final Future<String> Function()? _timeZone;

  Map<String, dynamic> _state(PlannerRefreshLease lease) =>
      PlannerState.fromMap(
        PlannerRepository.stateIn(lease.previousProjection) ??
            LocalStore.settingMap('levelUpState'),
      ).toMap();

  CloudCache _cache(PlannerRefreshLease lease) {
    final raw = lease.previousProjection?[plannerCloudProjectionKey];
    return CloudCache.fromMap(
      raw is Map ? cloudMap(raw) : LocalStore.settingMap(plannerCloudCacheKey),
    );
  }

  Map<String, dynamic> get _settings => {
    'locale': LocalStore.setting('locale', 'en'),
  };

  Future<void> _recoverSwitch(PlannerRefreshLease lease) async {
    final transition = lease.previousProjection?['cloudSwitch'];
    if (transition is! Map || transition['deviceData'] is! Map) return;
    await LocalStore.replacePrivateCache(
      cloudMap(transition['deviceData'] as Map),
    );
    await _mirror(lease);
    final next = lease.previousProjection!..remove('cloudSwitch');
    await lease.publish(next);
  }

  Future<void> _mirror(PlannerRefreshLease lease) async {
    final projection = lease.previousProjection;
    if (projection == null) return;
    final state = PlannerRepository.stateIn(projection);
    if (state != null) await LocalStore.writeSetting('levelUpState', state);
    final cache = projection[plannerCloudProjectionKey];
    if (cache is Map) {
      await LocalStore.writeSetting(plannerCloudCacheKey, cloudMap(cache));
    }
    final settings = projection['settings'];
    if (settings is Map && settings['locale'] is String) {
      await LocalStore.writeSetting('locale', settings['locale'] as String);
    }
  }

  Future<CloudCache> _capture(PlannerRefreshLease lease) async {
    await _recoverSwitch(lease);
    var cache = _cache(lease);
    if (cache.ownerId == null) return cache;
    final zone = await _timeZone?.call();
    if (zone != null && zone != cache.timeZone) {
      cache = CloudCache.fromMap({...cache.toMap(), 'timeZone': zone});
    }
    final next = queueCloudTransition(cache, _state(lease), _settings);
    await _write(lease, next);
    return next;
  }

  Future<void> _write(
    PlannerRefreshLease lease,
    CloudCache cache, {
    Map<String, dynamic>? state,
    Map<String, dynamic>? settings,
  }) async {
    final normalized = state == null
        ? _state(lease)
        : PlannerState.fromMap(state).toMap();
    final chosenSettings = settings ?? _settings;
    await lease.publish({
      ...?lease.previousProjection,
      'schemaVersion': 1,
      'canonicalPlanner': true,
      'plannerState': normalized,
      'values': lease.previousProjection?['values'] ?? <String, dynamic>{},
      'settings': chosenSettings,
      plannerCloudProjectionKey: cache.toMap(),
    });
    await LocalStore.writeSetting('levelUpState', normalized);
    await LocalStore.writeSetting(plannerCloudCacheKey, cache.toMap());
    if (chosenSettings['locale'] is String) {
      await LocalStore.writeSetting(
        'locale',
        chosenSettings['locale'] as String,
      );
    }
  }

  Map<String, dynamic> _archive(PlannerRefreshLease lease) => {
    'version': 1,
    'state': _state(lease),
    'cache': _cache(lease).toMap(),
    'settings': _settings,
    'deviceData': LocalStore.privateCacheSnapshot(),
  };

  Future<void> _saveArchive(PlannerRefreshLease lease, String owner) =>
      _archives.write(owner, jsonEncode(_archive(lease)));

  Future<void> _retainGuest(PlannerRefreshLease lease, String ownerId) async {
    final key = 'guest:$ownerId';
    final previous = await _archives.read(key);
    if (previous == null) return _saveArchive(lease, key);
    final saved = cloudMap(jsonDecode(previous) as Map);
    final draft = _archive(lease);
    final versions = [
      saved,
      ...((saved['additionalDrafts'] as List?) ?? []).whereType<Map>(),
    ];
    String identity(Map version) {
      final device = cloudMap(version['deviceData'] as Map? ?? {});
      final preferences = cloudMap(device['settings'] as Map? ?? {});
      preferences.remove('levelUpState');
      preferences.remove(plannerCloudCacheKey);
      for (final key in plannerReminderValueKeys) {
        preferences.remove(key);
      }
      device['settings'] = preferences;
      return cloudFingerprint(cloudMap(version['state'] as Map), {
        'deviceData': device,
        'settings': version['settings'],
      });
    }

    if (versions.any((version) => identity(version) == identity(draft))) return;
    // Keep the first pre-account draft and every later distinct guest draft.
    // Re-signing-in after sign-out must never overwrite the original archive.
    await _archives.write(
      key,
      jsonEncode({
        ...saved,
        'additionalDrafts': [
          ...((saved['additionalDrafts'] as List?) ?? []),
          draft,
        ],
      }),
    );
  }

  Map<String, dynamic> _blankDevice(Map<String, dynamic> settings) => {
    'settings': {
      // Display choices are device preferences. Private names, paths, backup
      // folders, images, tool caches and account-specific settings do not carry.
      'locale': settings['locale'] ?? 'en',
      'onboardingDone': true,
      'themeMode': 2,
      'autoBackup': 0,
      'autoSync': false,
      'autoBackupFolder': '',
    },
  };

  Future<void> _swap(
    PlannerRefreshLease lease,
    CloudCache cache,
    Map<String, dynamic> state,
    Map<String, dynamic> settings,
    Map<String, dynamic> device,
  ) async {
    final normalized = PlannerState.fromMap(state).toMap();
    final local = cloudMap(device);
    final localSettings = cloudMap(local['settings'] as Map? ?? {});
    localSettings['levelUpState'] = normalized;
    localSettings[plannerCloudCacheKey] = cache.toMap();
    localSettings['locale'] = settings['locale'] ?? 'en';
    // Global readable auto-backups/folder sync are device-scoped. Keep them
    // disabled for accounts; explicit user exports remain available.
    localSettings['autoBackup'] = 0;
    localSettings['autoSync'] = false;
    localSettings['autoBackupFolder'] = '';
    for (final key in plannerReminderValueKeys) {
      localSettings[key] = key == 'plannerReminderStatus'
          ? ''
          : <String, dynamic>{};
    }
    local['settings'] = localSettings;
    // Cancel notifications before exposing another owner's data. A failure
    // aborts the switch; the previous account remains intact.
    await _cancelNotifications?.call();
    await lease.publish({
      'schemaVersion': 1,
      'canonicalPlanner': true,
      'plannerState': normalized,
      'settings': settings,
      'values': <String, dynamic>{},
      plannerCloudProjectionKey: cache.toMap(),
      'cloudSwitch': {'deviceData': local},
    });
    await LocalStore.replacePrivateCache(local);
    final finished =
        lease.previousProjection ??
        <String, dynamic>{
          'schemaVersion': 1,
          'canonicalPlanner': true,
          'plannerState': normalized,
          'settings': settings,
          'values': <String, dynamic>{},
          plannerCloudProjectionKey: cache.toMap(),
        };
    finished.remove('cloudSwitch');
    await lease.publish(finished);
  }

  @override
  Future<CloudCache> read() => _bridge.withLease(_capture);

  /// Run before providers, folder import or background-triggering initialization.
  /// A missing/mismatched secure session never exposes the last account cache.
  Future<void> guardSession(String? secureOwnerId) =>
      _bridge.withLease((lease) async {
        await _recoverSwitch(lease);
        final owner = _cache(lease).ownerId;
        if (owner != null && owner != secureOwnerId) {
          await _beforeIsolation?.call();
          await _saveArchive(lease, owner);
          final settings = _settings;
          await _swap(
            lease,
            const CloudCache(),
            PlannerState().toMap(),
            settings,
            _blankDevice(settings),
          );
        }
      });

  @override
  Future<void> activate(
    String ownerId,
    CloudSnapshot remote,
  ) => _bridge.withLease((lease) async {
    var current = await _capture(lease);
    if (current.ownerId == ownerId) {
      if (current.pending.isNotEmpty) {
        // Retry the original mutation first: a newer remote revision may be
        // our already-committed request whose response was lost.
        return;
      }
      if (remote.state != null) {
        final fingerprint = cloudFingerprint(remote.state!, remote.settings);
        current = CloudCache(
          ownerId: ownerId,
          revision: remote.revision,
          lastSyncedAt: remote.serverTime,
          timeZone: current.timeZone ?? remote.timeZone,
          lastQueuedFingerprint: fingerprint,
          acknowledgedState: remote.state,
        );
        await _write(
          lease,
          current,
          state: remote.state,
          settings: remote.settings,
        );
      }
      return;
    }
    final previousOwner = current.ownerId;
    await _beforeIsolation?.call();
    if (previousOwner == null) {
      await _retainGuest(lease, ownerId);
    } else {
      await _saveArchive(lease, previousOwner);
    }
    final saved = await _archives.read(ownerId);
    Map<String, dynamic>? ownerDevice;
    if (saved != null) {
      final archive = cloudMap(jsonDecode(saved) as Map);
      final savedCache = CloudCache.fromMap(cloudMap(archive['cache'] as Map));
      if (savedCache.ownerId != ownerId) {
        throw StateError('cloud_owner_mismatch');
      }
      ownerDevice = cloudMap(archive['deviceData'] as Map);
      if (savedCache.pending.isNotEmpty) {
        await _swap(
          lease,
          savedCache,
          cloudMap(archive['state'] as Map),
          cloudMap(archive['settings'] as Map),
          cloudMap(archive['deviceData'] as Map),
        );
        return;
      }
    }
    final zone = await _timeZone?.call() ?? remote.timeZone ?? 'UTC';
    // Empty remote may adopt the pre-account local data, but never an unrelated
    // signed-out account cache. signOut always leaves sanitized guest state.
    final state =
        remote.state ??
        (previousOwner == null ? _state(lease) : PlannerState().toMap());
    final settings = remote.state == null ? _settings : remote.settings;
    final device =
        ownerDevice ??
        (remote.state == null && previousOwner == null
            ? LocalStore.privateCacheSnapshot()
            : _blankDevice(settings));
    var next = CloudCache(
      ownerId: ownerId,
      revision: remote.revision,
      timeZone: zone,
      lastSyncedAt: remote.state == null ? null : remote.serverTime,
      lastQueuedFingerprint: remote.state == null
          ? null
          : cloudFingerprint(state, settings),
      acknowledgedState: remote.state,
    );
    if (remote.state == null) {
      next = queueCloudTransition(next, state, settings);
    }
    await _swap(lease, next, state, settings, device);
  });

  @override
  Future<bool> acknowledge(
    String ownerId,
    String mutationId,
    CloudSnapshot remote,
  ) => _bridge.withLease((lease) async {
    final cache = await _capture(lease);
    if (cache.ownerId != ownerId ||
        cache.pending.isEmpty ||
        cache.pending.first.mutationId != mutationId) {
      return false;
    }
    if (remote.state == null || remote.revision != cache.revision + 1) {
      throw const FormatException('Invalid cloud acknowledgement.');
    }
    final pending = cache.pending.skip(1).toList();
    final reconciled =
        cloudFingerprint(
          cache.pending.first.state,
          cache.pending.first.settings,
        ) !=
        cloudFingerprint(remote.state!, remote.settings);
    final next = CloudCache(
      ownerId: ownerId,
      revision: remote.revision,
      pending: pending,
      timeZone: cache.timeZone,
      acknowledgedState: remote.state,
      lastSyncedAt: remote.serverTime,
      lastQueuedFingerprint: pending.isEmpty
          ? cloudFingerprint(remote.state!, remote.settings)
          : cache.lastQueuedFingerprint,
      conflict: pending.isNotEmpty && reconciled ? remote : null,
      errorCode: pending.isNotEmpty && reconciled ? 'server_reconciled' : null,
    );
    await _write(
      lease,
      next,
      state: pending.isEmpty ? remote.state : null,
      settings: pending.isEmpty ? remote.settings : null,
    );
    return true;
  });

  @override
  Future<void> markConflict(
    String ownerId,
    CloudSnapshot? remote,
    String code,
  ) => _bridge.withLease((lease) async {
    final cache = await _capture(lease);
    if (cache.ownerId != ownerId) throw StateError('cloud_owner_mismatch');
    await _write(
      lease,
      CloudCache.fromMap({
        ...cache.toMap(),
        'errorCode': code,
        if (remote != null) 'conflict': remote.toMap(),
      }),
    );
  });

  @override
  Future<void> restoreCloud(String ownerId, CloudSnapshot remote) =>
      _bridge.withLease((lease) async {
        final cache = await _capture(lease);
        if (cache.ownerId != ownerId || remote.state == null) {
          throw StateError('cloud_owner_mismatch');
        }
        await _archives.write('$ownerId:retained', jsonEncode(_archive(lease)));
        await _write(
          lease,
          CloudCache(
            ownerId: ownerId,
            revision: remote.revision,
            lastSyncedAt: remote.serverTime,
            timeZone: cache.timeZone,
            acknowledgedState: remote.state,
            lastQueuedFingerprint: cloudFingerprint(
              remote.state!,
              remote.settings,
            ),
          ),
          state: remote.state,
          settings: remote.settings,
        );
      });

  @override
  Future<void> signOut() => _bridge.withLease((lease) async {
    final cache = await _capture(lease);
    await _beforeIsolation?.call();
    if (cache.ownerId != null) await _saveArchive(lease, cache.ownerId!);
    final settings = _settings;
    await _swap(
      lease,
      const CloudCache(),
      PlannerState().toMap(),
      settings,
      _blankDevice(settings),
    );
  });

  @override
  Future<String> exportDraft() => _bridge.withLease((lease) async {
    await _capture(lease);
    final owner = _cache(lease).ownerId;
    final retained = owner == null
        ? null
        : await _archives.read('$owner:retained');
    final guest = owner == null ? null : await _archives.read('guest:$owner');
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'Level Up', 'format': 'private-local-draft', 'version': 1,
      'current': _archive(lease),
      if (retained != null) 'retained': jsonDecode(retained),
      // A guest archive is only offered to the first account that adopted it;
      // it is never exposed to arbitrary later accounts.
      if (guest != null && owner != null) 'beforeSignIn': jsonDecode(guest),
    });
  });
}
