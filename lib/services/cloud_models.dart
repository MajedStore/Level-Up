// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';

Map<String, dynamic> cloudMap(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class CloudSnapshot {
  CloudSnapshot({
    required this.revision,
    this.state,
    this.settings = const {},
    this.serverTime,
    this.timeZone,
  });
  final int revision;
  final Map<String, dynamic>? state;
  final Map<String, dynamic> settings;
  final DateTime? serverTime;
  final String? timeZone;

  factory CloudSnapshot.fromMap(Map<String, dynamic> value) {
    final revision = value['revision'];
    if (revision is! int || revision < 0 ||
        value['state'] != null && value['state'] is! Map) {
      throw const FormatException('Invalid cloud snapshot.');
    }
    return CloudSnapshot(
      revision: revision,
      state: value['state'] is Map ? cloudMap(value['state'] as Map) : null,
      settings: value['settings'] is Map ? cloudMap(value['settings'] as Map) : {},
      serverTime: DateTime.tryParse('${value['serverTime'] ?? ''}'),
      timeZone: value['timeZone'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'revision': revision,
    'state': state == null ? null : cloudMap(state!),
    'settings': cloudMap(settings),
    if (serverTime != null) 'serverTime': serverTime!.toIso8601String(),
    if (timeZone != null) 'timeZone': timeZone,
  };
}

/// One immutable transition checkpoint, persisted with its local domain write.
/// Retain ordering: create -> assign -> edit cannot safely be coalesced.
class CloudMutation {
  CloudMutation({
    required this.mutationId,
    required this.baseRevision,
    required Map<String, dynamic> state,
    required Map<String, dynamic> settings,
    required this.timeZone,
  }) : state = cloudMap(state), settings = cloudMap(settings);
  final String mutationId;
  final int baseRevision;
  final Map<String, dynamic> state;
  final Map<String, dynamic> settings;
  final String timeZone;

  factory CloudMutation.fromMap(Map<String, dynamic> value) => CloudMutation(
    mutationId: value['mutationId'] as String,
    baseRevision: value['baseRevision'] as int,
    state: cloudMap(value['state'] as Map),
    settings: cloudMap(value['settings'] as Map? ?? {}),
    timeZone: value['timeZone'] as String,
  );

  Map<String, dynamic> toMap() => {
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'state': cloudMap(state),
    'settings': cloudMap(settings),
    'timeZone': timeZone,
  };
}

class CloudCache {
  const CloudCache({
    this.ownerId,
    this.revision = 0,
    this.pending = const [],
    this.conflict,
    this.errorCode,
    this.lastSyncedAt,
    this.timeZone,
    this.lastQueuedFingerprint,
    this.acknowledgedState,
  });
  final String? ownerId;
  final int revision;
  final List<CloudMutation> pending;
  final CloudSnapshot? conflict;
  final String? errorCode;
  final DateTime? lastSyncedAt;
  final String? timeZone;
  final String? lastQueuedFingerprint;
  final Map<String, dynamic>? acknowledgedState;

  factory CloudCache.fromMap(Map<String, dynamic> value) => CloudCache(
    ownerId: value['ownerId'] as String?,
    revision: value['revision'] as int? ?? 0,
    pending: (value['pending'] as List? ?? []).map((v) => CloudMutation.fromMap(cloudMap(v as Map))).toList(),
    conflict: value['conflict'] is Map ? CloudSnapshot.fromMap(cloudMap(value['conflict'] as Map)) : null,
    errorCode: value['errorCode'] as String?,
    lastSyncedAt: DateTime.tryParse('${value['lastSyncedAt'] ?? ''}'),
    timeZone: value['timeZone'] as String?,
    lastQueuedFingerprint: value['lastQueuedFingerprint'] as String?,
    acknowledgedState: value['acknowledgedState'] is Map ? cloudMap(value['acknowledgedState'] as Map) : null,
  );

  Map<String, dynamic> toMap() => {
    'ownerId': ownerId,
    'revision': revision,
    'pending': pending.map((v) => v.toMap()).toList(),
    if (conflict != null) 'conflict': conflict!.toMap(),
    if (errorCode != null) 'errorCode': errorCode,
    if (lastSyncedAt != null) 'lastSyncedAt': lastSyncedAt!.toIso8601String(),
    if (timeZone != null) 'timeZone': timeZone,
    if (lastQueuedFingerprint != null) 'lastQueuedFingerprint': lastQueuedFingerprint,
    if (acknowledgedState != null) 'acknowledgedState': cloudMap(acknowledgedState!),
  };
}

abstract interface class CloudArchiveStore {
  Future<String?> read(String ownerId);
  Future<void> write(String ownerId, String json);
}

/// The application adapter implements these operations under its native planner
/// lease. Network calls are deliberately outside that lease.
abstract interface class CloudPlannerCache {
  /// Capture any uncaptured foreground/headless change before returning.
  Future<CloudCache> read();

  /// Restore-first account switch. Preserve matching owner's pending archive;
  /// never replace it with remote data. Isolate all other owners and reminders.
  Future<void> activate(String ownerId, CloudSnapshot remote);

  /// Remove only this owner's matching queue head. Replace live state only if
  /// no later/uncaptured write exists; otherwise retain that optimistic draft.
  Future<bool> acknowledge(String ownerId, String mutationId, CloudSnapshot remote);

  Future<void> markConflict(String ownerId, CloudSnapshot? remote, String code);

  /// Explicit recovery: archive pending draft privately, then use remote state.
  Future<void> restoreCloud(String ownerId, CloudSnapshot remote);

  /// Archive the account state/queue privately, swap to sanitized guest state,
  /// clear account reminder metadata and prevent prior-account auto-backups.
  Future<void> signOut();

  /// Export retained local drafts only after the user chooses the share action.
  Future<String> exportDraft();
}
