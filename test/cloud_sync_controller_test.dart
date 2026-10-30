import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/google_sign_in_service.dart';
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
  Object? refreshError;
  Object? googleError;
  Object? resetError;
  final resetRequests = <String>[];
  final resetCompletions = <({String email, String token, String password})>[];
  int refreshes = 0;
  Completer<void>? hold;
  Completer<void>? getGate;
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
  Future<CloudSession> google(String idToken) async {
    events.add('google');
    if (googleError != null) throw googleError!;
    return cloudSession();
  }

  @override
  Future<CloudUser> linkGoogle(String accessToken, String idToken) async {
    events.add('link-google');
    if (googleError != null) throw googleError!;
    return const CloudUser(
      id: 'a',
      email: 'a@example.com',
      hasGoogle: true,
    );
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    events.add('reset-request');
    if (resetError != null) throw resetError!;
    resetRequests.add(email);
  }

  @override
  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  ) async {
    events.add('reset-confirm');
    if (resetError != null) throw resetError!;
    resetCompletions.add((email: email, token: token, password: password));
  }

  @override
  Future<CloudSession> refresh(String refreshToken) async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
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
    if (getGate != null) await getGate!.future;
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

class FakeGoogleIdTokens implements GoogleIdTokenProvider {
  @override
  bool configured = true;
  Object? error;
  int requests = 0;
  @override
  Future<String> authenticate() async {
    requests++;
    if (error != null) throw error!;
    return 'verified-google-id-token';
  }
}

void main() {
  late FakeCloudApi api;
  late MemoryCloudCache cache;
  late MemorySessions sessions;
  late CloudSyncController controller;
  late FakeGoogleIdTokens google;
  late int applied;
  setUp(() {
    api = FakeCloudApi();
    cache = MemoryCloudCache();
    sessions = MemorySessions();
    google = FakeGoogleIdTokens();
    applied = 0;
    controller = CloudSyncController(
      api: api,
      cache: cache,
      sessionStore: sessions,
      googleIdTokenProvider: google,
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
    'Google cancellation leaves the app signed out without a server call',
    () async {
      google.error = const GoogleSignInFailure('google_canceled');
      await controller.signInWithGoogle();
      expect(google.requests, 1);
      expect(api.events, isEmpty);
      expect(controller.user, isNull);
      expect(controller.errorCode, 'google_canceled');
    },
  );
  test(
    'Google session follows the same restore-first and secure-storage path',
    () async {
      await controller.signInWithGoogle();
      expect(api.events, ['google', 'get']);
      expect(controller.user, isNotNull);
      expect(sessions.value, isNotNull);
      expect(cache.events, ['activate']);
    },
  );
  test(
    'invalid Google linking proof does not revoke the Level Up session',
    () async {
      await existing(count: 0);
      api.googleError = const CloudApiException(
        'invalid_google_token',
        status: 401,
      );
      await controller.linkGoogle();
      expect(controller.user?.id, 'a');
      expect(sessions.value, isNotNull);
      expect(api.refreshes, 0);
      expect(cache.archived, 0);
      expect(controller.errorCode, 'invalid_google_token');
    },
  );
  test(
    'password reset only records generic client-side status after API acceptance',
    () async {
      await controller.requestPasswordReset('a@example.com');
      expect(api.resetRequests, ['a@example.com']);
      expect(controller.errorCode, 'password_reset_sent');
      await controller.completePasswordReset(
        'a@example.com',
        List.filled(64, 'a').join(),
        'A-new-long-password-123',
      );
      expect(api.resetCompletions, hasLength(1));
      expect(controller.errorCode, 'password_reset_complete');
    },
  );
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
      await controller.retryNow();
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
  test(
    'rejected refresh clears secure identity and archives account data',
    () async {
      await existing(expired: true);
      api.refreshError = const CloudApiException(
        'session_expired',
        status: 401,
      );
      await controller.synchronize();
      expect(sessions.value, isNull);
      expect(cache.value.ownerId, isNull);
      expect(cache.archived, 1);
      expect(controller.user, isNull);
      expect(controller.status, CloudSyncStatus.sessionExpired);
      expect(api.refreshes, 1);
    },
  );
  test(
    'temporary refresh failure preserves secure identity and pending draft',
    () async {
      await existing(expired: true);
      api.refreshError = const CloudApiException('network_error');
      await controller.synchronize();
      expect(controller.user?.id, 'a');
      expect(sessions.value, isNotNull);
      expect(cache.archived, 0);
      expect(controller.pendingCount, 1);
      expect(controller.status, CloudSyncStatus.offline);
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
  test('a sync signal during a download schedules one trailing pass', () async {
    await existing(count: 0);
    final downloaded = Completer<void>();
    api.getGate = downloaded;
    final first = controller.synchronize();
    await Future<void>.delayed(Duration.zero);
    final second = controller.synchronize();
    final third = controller.synchronize();
    downloaded.complete();
    await Future.wait([first, second, third]);
    expect(api.events.where((event) => event == 'get'), hasLength(2));
  });
  test(
    'logout requested during an upload waits then isolates the account',
    () async {
      await existing();
      api.hold = Completer<void>();
      final syncing = controller.synchronize();
      await Future<void>.delayed(Duration.zero);
      final loggingOut = controller.signOut();
      expect(controller.user?.id, 'a');
      api.hold!.complete();
      await Future.wait([syncing, loggingOut]);
      expect(controller.user, isNull);
      expect(cache.value.ownerId, isNull);
      expect(sessions.value, isNull);
      expect(api.events.last, 'logout');
    },
  );
  testWidgets(
    'foreground retry backs off, is bounded, and retains the same mutation',
    (tester) async {
      controller.dispose();
      controller = CloudSyncController(
        api: api,
        cache: cache,
        sessionStore: sessions,
        clock: () => cloudNow,
        retryDelays: const [Duration(seconds: 2), Duration(seconds: 4)],
      );
      await existing();
      api.syncError = const CloudApiException('network_error');
      await controller.synchronize();
      expect(api.sent, hasLength(1));
      await controller.synchronize();
      expect(api.sent, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(api.sent, hasLength(2));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(api.sent, hasLength(3));
      await tester.pump(const Duration(minutes: 1));
      expect(api.sent, hasLength(3));
      expect(api.sent.map((mutation) => mutation.mutationId), [
        'm0',
        'm0',
        'm0',
      ]);
      expect(controller.pendingCount, 1);
      api.syncError = null;
      await controller.retryNow();
      expect(controller.status, CloudSyncStatus.synced);
    },
  );
  testWidgets('logout cancels scheduled recovery', (tester) async {
    await existing();
    api.syncError = const CloudApiException('service_unavailable');
    await controller.synchronize();
    await controller.signOut();
    await tester.pump(const Duration(minutes: 1));
    expect(api.sent, hasLength(1));
    expect(controller.user, isNull);
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
