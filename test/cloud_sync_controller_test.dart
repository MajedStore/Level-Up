import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';
import 'package:streak/services/cloud_sync_controller.dart';

final cloudNow = DateTime.utc(2026, 10, 29, 12);
CloudSession cloudSession({
  String owner = 'a',
  String token = 'access',
  String refresh = 'refresh',
  bool expired = false,
}) => CloudSession(
  user: CloudUser(id: owner, email: '$owner@example.com'),
  accessToken: token,
  refreshToken: refresh,
  expiresAt: cloudNow.add(Duration(minutes: expired ? -1 : 15)),
);
CloudMutation cloudMutation(String id, int revision) => CloudMutation(
  mutationId: id,
  baseRevision: revision,
  state: {
    'tasks': [id],
  },
  settings: {'locale': 'ar'},
  timeZone: 'Europe/Istanbul',
);

class MemorySessions implements CloudSessionStore {
  CloudSession? value;
  int writes = 0;
  List<String>? events;
  @override
  Future<CloudSession?> read() async => value;
  @override
  Future<void> write(CloudSession session) async {
    value = session;
    writes++;
    events?.add('session-write');
  }

  @override
  Future<void> clear() async {
    value = null;
    events?.add('session-clear');
  }
}

class MemoryCloudCache implements CloudPlannerCache {
  CloudCache value = const CloudCache();
  final events = <String>[];
  int archived = 0;
  bool reconcile = false;
  bool failActivation = false;
  @override
  Future<CloudCache> read() async => value;
  @override
  Future<void> activate(String ownerId, CloudSnapshot remote) async {
    events.add('activate');
    if (failActivation) throw StateError('storage failure');
    if (value.ownerId == ownerId && value.pending.isNotEmpty) return;
    value = CloudCache(
      ownerId: ownerId,
      revision: remote.revision,
      pending: remote.state == null
          ? [cloudMutation('initial', remote.revision)]
          : [],
      acknowledgedState: remote.state,
    );
  }

  @override
  Future<bool> acknowledge(
    String ownerId,
    String mutationId,
    CloudSnapshot remote,
  ) async {
    events.add('ack:$mutationId');
    if (ownerId != value.ownerId ||
        value.pending.first.mutationId != mutationId) {
      return false;
    }
    value = CloudCache(
      ownerId: ownerId,
      revision: remote.revision,
      pending: value.pending.skip(1).toList(),
      errorCode: reconcile && value.pending.length > 1
          ? 'server_reconciled'
          : null,
    );
    return true;
  }

  @override
  Future<void> markConflict(
    String ownerId,
    CloudSnapshot? remote,
    String code,
  ) async {
    value = CloudCache(
      ownerId: value.ownerId,
      revision: value.revision,
      pending: value.pending,
      conflict: remote,
      errorCode: code,
    );
  }

  @override
  Future<void> restoreCloud(String ownerId, CloudSnapshot remote) async {
    archived++;
    value = CloudCache(
      ownerId: ownerId,
      revision: remote.revision,
      acknowledgedState: remote.state,
    );
  }

  @override
  Future<void> signOut() async {
    events.add('isolate');
    archived++;
    value = const CloudCache();
  }

  @override
  Future<String> exportDraft() async => '{}';
}

class FakeCloudApi implements CloudApi {
  @override
  bool configured = true;
  CloudSnapshot remote = CloudSnapshot(revision: 4, state: {'cloud': true});
  final events = <String>[];
  final sent = <CloudMutation>[];
  Object? getError;
  Object? syncError;
  Object? logoutError;
  int refreshes = 0;
  Completer<void>? hold;
  Future<void> Function()? duringSync;
  bool unauthorizedOnce = false;
  @override
  Future<CloudSession> register(String email, String password) async {
    events.add('register');
    return cloudSession();
  }

  @override
  Future<CloudSession> login(String email, String password) async {
    events.add('login');
    return cloudSession();
  }

  @override
  Future<CloudSession> refresh(String refreshToken) async {
    refreshes++;
    return cloudSession(token: 'rotated-access', refresh: 'rotated-refresh');
  }

  @override
  Future<void> logout(String refreshToken) async {
    events.add('logout');
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<CloudSnapshot> getState(String accessToken) async {
    events.add('get');
    if (getError != null) throw getError!;
    if (unauthorizedOnce) {
      unauthorizedOnce = false;
      throw const CloudApiException('unauthorized', status: 401);
    }
    return remote;
  }

  @override
  Future<CloudSnapshot> sync(String accessToken, CloudMutation mutation) async {
    events.add('sync');
    sent.add(mutation);
    if (hold != null) await hold!.future;
    await duringSync?.call();
    if (syncError != null) throw syncError!;
    return CloudSnapshot(
      revision: mutation.baseRevision + 1,
      state: mutation.state,
    );
  }
}

void main() {
  late FakeCloudApi api;
  late MemoryCloudCache cache;
  late MemorySessions sessions;
  late CloudSyncController controller;
  late int applied;
  setUp(() {
    api = FakeCloudApi();
    cache = MemoryCloudCache();
    sessions = MemorySessions();
    applied = 0;
    controller = CloudSyncController(
      api: api,
      cache: cache,
      sessionStore: sessions,
      clock: () => cloudNow,
      onApplied: () async {
        applied++;
      },
    );
  });
  tearDown(() => controller.dispose());
  Future<void> existing({bool expired = false, int count = 1}) async {
    sessions.value = cloudSession(expired: expired);
    cache.value = CloudCache(
      ownerId: 'a',
      revision: 4,
      pending: [for (var i = 0; i < count; i++) cloudMutation('m$i', 4 + i)],
    );
    await controller.initialize(sync: false);
  }

  test(
    'login restores cloud before any local upload; fresh cache never replaces cloud with empty state',
    () async {
      await controller.signIn('a@example.com', 'long-enough-password');
      expect(api.events, ['login', 'get']);
      expect(cache.events, ['activate']);
      expect(cache.value.acknowledgedState, {'cloud': true});
      expect(api.sent, isEmpty);
      expect(controller.status, CloudSyncStatus.synced);
      expect(applied, 1);
    },
  );
  test('failed restore leaves guest and secure identity untouched', () async {
    api.getError = const CloudApiException('network_error');
    await controller.signIn('a@example.com', 'password');
    expect(sessions.writes, 0);
    expect(cache.events, isEmpty);
    expect(controller.user, isNull);
    expect(controller.status, CloudSyncStatus.offline);
  });
  test(
    'empty cloud imports only after restore-first GET and registration',
    () async {
      api.remote = CloudSnapshot(revision: 0);
      await controller.signIn('a@example.com', 'long-password', register: true);
      expect(api.events, ['register', 'get', 'sync']);
      expect(api.sent.single.mutationId, 'initial');
      expect(controller.status, CloudSyncStatus.synced);
    },
  );
  test(
    'ordered checkpoints keep original mutation IDs and revisions',
    () async {
      await existing(count: 3);
      await controller.synchronize();
      expect(api.sent.map((v) => v.mutationId), ['m0', 'm1', 'm2']);
      expect(api.sent.map((v) => v.baseRevision), [4, 5, 6]);
      expect(controller.pendingCount, 0);
      expect(cache.value.revision, 7);
    },
  );
  test(
    'network failure retains durable checkpoint and retry uses same idempotency key',
    () async {
      await existing();
      api.syncError = const CloudApiException('network_error');
      await controller.synchronize();
      expect(controller.pendingCount, 1);
      expect(controller.status, CloudSyncStatus.offline);
      api.syncError = null;
      await controller.synchronize();
      expect(api.sent.map((v) => v.mutationId), ['m0', 'm0']);
      expect(controller.status, CloudSyncStatus.synced);
    },
  );
  test(
    '401 rotates tokens securely then retries; secrets never enter mutation',
    () async {
      await existing(count: 0);
      api.unauthorizedOnce = true;
      await controller.synchronize();
      expect(api.refreshes, 1);
      expect(sessions.value!.refreshToken, 'rotated-refresh');
      expect(api.events, ['get', 'get']);
      expect(controller.status, CloudSyncStatus.synced);
    },
  );
  test(
    'expired access is refreshed before transmitting a queued change',
    () async {
      await existing(expired: true);
      await controller.synchronize();
      expect(api.refreshes, 1);
      expect(sessions.value!.accessToken, 'rotated-access');
    },
  );
  for (final code in [
    'revision_conflict',
    'deadline_passed',
    'history_conflict',
  ]) {
    test('$code preserves local draft until explicit cloud restore', () async {
      await existing();
      api.syncError = CloudApiException(
        code,
        status: code == 'revision_conflict' ? 409 : 422,
        snapshot: api.remote,
      );
      await controller.synchronize();
      expect(controller.pendingCount, 1);
      expect(controller.canRestore, isTrue);
      await controller.synchronize();
      expect(api.sent, hasLength(1));
      await controller.restoreCloud();
      expect(cache.archived, 1);
      expect(controller.pendingCount, 0);
      expect(controller.status, CloudSyncStatus.synced);
    });
  }
  test(
    'server reconciliation stops before a later checkpoint can overwrite its result',
    () async {
      await existing(count: 2);
      cache.reconcile = true;
      await controller.synchronize();
      expect(api.sent, hasLength(1));
      expect(controller.pendingCount, 1);
      expect(controller.status, CloudSyncStatus.rejected);
      expect(controller.errorCode, 'server_reconciled');
    },
  );
  test('a new foreground checkpoint during network is not lost', () async {
    await existing();
    api.duringSync = () async {
      if (cache.value.pending.length == 1 &&
          cache.value.pending.first.mutationId == 'm0') {
        cache.value = CloudCache(
          ownerId: 'a',
          revision: 4,
          pending: [...cache.value.pending, cloudMutation('new-write', 5)],
        );
      }
    };
    await controller.synchronize();
    expect(api.sent.map((v) => v.mutationId), ['m0', 'new-write']);
    expect(controller.status, CloudSyncStatus.synced);
  });
  test('repeated sync taps share the running operation', () async {
    await existing();
    api.hold = Completer<void>();
    final first = controller.synchronize();
    final second = controller.synchronize();
    await Future<void>.delayed(Duration.zero);
    expect(api.sent, hasLength(1));
    api.hold!.complete();
    await Future.wait([first, second]);
    expect(api.sent, hasLength(1));
  });
  test(
    'signout isolates cache before clearing tokens even when network logout fails',
    () async {
      await existing();
      sessions.events = cache.events;
      api.logoutError = const CloudApiException('network_error');
      await controller.signOut();
      expect(cache.events, ['isolate', 'session-clear']);
      expect(cache.archived, 1);
      expect(controller.user, isNull);
      expect(controller.status, CloudSyncStatus.signedOut);
      expect(cache.value.ownerId, isNull);
    },
  );
  test('missing secure session sanitizes a leftover account cache', () async {
    cache.value = const CloudCache(ownerId: 'other');
    await controller.initialize();
    expect(cache.events, ['isolate']);
    expect(controller.status, CloudSyncStatus.signedOut);
    expect(api.events, isEmpty);
  });
  test('unconfigured builds do not attempt a network sync', () async {
    api.configured = false;
    await controller.initialize();
    await controller.synchronize();
    expect(controller.status, CloudSyncStatus.unconfigured);
    expect(api.events, isEmpty);
  });
  test(
    'activation failure rolls back public and secure identity before retry',
    () async {
      cache.failActivation = true;
      await controller.signIn('a@example.com', 'password');
      expect(controller.user, isNull);
      expect(sessions.value, isNull);
      expect(cache.value.ownerId, isNull);
      cache.failActivation = false;
      await controller.signIn('a@example.com', 'password');
      expect(cache.value.ownerId, 'a');
      expect(controller.status, CloudSyncStatus.synced);
    },
  );
}
