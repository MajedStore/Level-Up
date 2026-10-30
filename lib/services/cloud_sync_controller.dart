// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/google_sign_in_service.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';

enum CloudSyncStatus {
  localOnly,
  unconfigured,
  signedOut,
  restoring,
  syncing,
  synced,
  pending,
  offline,
  conflict,
  rejected,
  sessionExpired,
}

/// Foreground transport coordinator. Durable state, owner isolation and queue
/// checkpointing belong to CloudPlannerCache under the application's native gate.
class CloudSyncController extends ChangeNotifier {
  CloudSyncController({
    required this.api,
    required this.cache,
    required this.sessionStore,
    this.googleIdTokenProvider,
    this.onApplied,
    this.exportDraft,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final CloudApi api;
  final CloudPlannerCache cache;
  final CloudSessionStore sessionStore;
  final GoogleIdTokenProvider? googleIdTokenProvider;
  final Future<void> Function()? onApplied;
  final Future<String> Function()? exportDraft;

  /// Foreground recovery is bounded. Restarting the app or an explicit retry
  /// starts another attempt without changing the durable mutation queue.
  final List<Duration> retryDelays;
  final DateTime Function() _clock;
  CloudSession? _session;
  CloudCache _cache = const CloudCache();
  CloudSyncStatus _status = CloudSyncStatus.localOnly;
  String? _errorCode;
  Future<void>? _operation;
  String? _operationKey;
  final _queuedOperations = <String, Future<void>>{};
  Timer? _retryTimer;
  int _retryAttempts = 0;
  bool _disposed = false;

  CloudSession? get session => _session;
  CloudUser? get user => _session?.user;
  CloudCache get local => _cache;
  CloudSyncStatus get status => _status;
  String? get errorCode => _errorCode;
  bool get configured => api.configured;
  bool get busy => _operation != null;
  int get pendingCount => _cache.pending.length;
  bool get canRestore =>
      _session != null && (_cache.conflict != null || _cache.errorCode != null);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(CloudSyncStatus value, [String? error]) {
    _status = value;
    _errorCode = error;
    _notify();
  }

  Future<void> _exclusive(String key, Future<void> Function() action) {
    if (_disposed) return Future<void>.value();
    final current = _operation;
    if (current != null) {
      // Repeated form taps share their operation. A sync signal instead queues
      // one trailing pass because a local write may have arrived during the
      // last download. Different intents (especially logout) are never dropped.
      if (_operationKey == key && key != 'sync') return current;
      return _queuedOperations.putIfAbsent(key, () {
        return current.then((_) {
          _queuedOperations.remove(key);
          return _exclusive(key, action);
        });
      });
    }
    final work = Future<void>.microtask(action);
    _operation = work;
    _operationKey = key;
    _notify();
    return work.whenComplete(() {
      _operation = null;
      _operationKey = null;
      _notify();
    });
  }

  Future<void> initialize({bool sync = true}) =>
      _exclusive('initialize', () async {
        try {
          _session = await sessionStore.read();
          _cache = await cache.read();
          if (_session == null) {
            if (_cache.ownerId != null) {
              await cache.signOut();
              await onApplied?.call();
              _cache = await cache.read();
            }
            _set(
              configured
                  ? CloudSyncStatus.signedOut
                  : CloudSyncStatus.unconfigured,
            );
          } else if (sync && configured) {
            await _sync();
          } else {
            _set(configured ? _cacheStatus() : CloudSyncStatus.unconfigured);
          }
        } catch (error) {
          _fail(error);
        }
      });

  /// Credentials are used only for this request, never persisted by the client.
  /// Download must succeed before activating the account or sending local data.
  Future<void> signIn(String email, String password, {bool register = false}) =>
      _exclusive('sign-in', () async {
        _cancelRetry(resetAttempts: true);
        _set(CloudSyncStatus.restoring);
        try {
          final session = register
              ? await api.register(email, password)
              : await api.login(email, password);
          await _activateSession(session);
        } catch (error) {
          _fail(error);
        }
      });

  Future<void> _activateSession(CloudSession session) async {
    final remote = await api.getState(session.accessToken);
    final previous = _session;
    await sessionStore.write(session);
    try {
      await cache.activate(session.ownerId, remote);
    } catch (_) {
      if (previous == null) {
        await sessionStore.clear();
      } else {
        await sessionStore.write(previous);
      }
      rethrow;
    }
    _session = session;
    await onApplied?.call();
    _cache = await cache.read();
    _set(_cacheStatus());
    if (_cache.pending.isNotEmpty && _cache.errorCode == null) {
      await _sync();
    }
  }

  Future<void> signInWithGoogle() => _exclusive('google-sign-in', () async {
    _cancelRetry(resetAttempts: true);
    _set(CloudSyncStatus.restoring);
    try {
      final provider = googleIdTokenProvider;
      if (provider == null || !provider.configured) {
        throw const CloudApiException('google_not_configured');
      }
      final token = await provider.authenticate();
      await _activateSession(await api.google(token));
    } on GoogleSignInFailure catch (error) {
      _fail(CloudApiException(error.code));
    } catch (error) {
      _fail(error);
    }
  });

  Future<void> linkGoogle() => _exclusive('google-link', () async {
    _set(CloudSyncStatus.restoring);
    try {
      final provider = googleIdTokenProvider;
      if (provider == null || !provider.configured) {
        throw const CloudApiException('google_not_configured');
      }
      final token = await provider.authenticate();
      final user = await _authorized((access) => api.linkGoogle(access, token));
      _session = _session!.withUser(user);
      await sessionStore.write(_session!);
      _set(_cacheStatus());
    } on GoogleSignInFailure catch (error) {
      _fail(CloudApiException(error.code));
    } catch (error) {
      _fail(error);
    }
  });

  Future<void> requestPasswordReset(String email) =>
      _exclusive('reset-request', () async {
        try {
          await api.requestPasswordReset(email);
          _set(CloudSyncStatus.signedOut, 'password_reset_sent');
        } catch (error) {
          _fail(error);
        }
      });

  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  ) => _exclusive('reset-confirm', () async {
    try {
      await api.completePasswordReset(email, token, password);
      _set(CloudSyncStatus.signedOut, 'password_reset_complete');
    } catch (error) {
      _fail(error);
    }
  });

  Future<void> _refresh() async {
    final before = _session;
    if (before == null) throw const CloudApiException('session_expired');
    late CloudSession refreshed;
    try {
      refreshed = await api.refresh(before.refreshToken);
    } on CloudApiException catch (error) {
      if (_authenticationRejected(error)) await _invalidateExpiredSession();
      rethrow;
    }
    if (refreshed.ownerId != before.ownerId) {
      throw const CloudApiException('invalid_response');
    }
    await sessionStore.write(refreshed);
    _session = refreshed;
  }

  /// A rejected refresh means the server no longer accepts this identity. The
  /// native cache archives private pending work before swapping to guest data,
  /// so a later account cannot see it and unsynchronized work is not deleted.
  Future<void> _invalidateExpiredSession() async {
    _cancelRetry(resetAttempts: true);
    await cache.signOut();
    await sessionStore.clear();
    _session = null;
    await onApplied?.call();
    _cache = await cache.read();
  }

  Future<T> _authorized<T>(Future<T> Function(String token) action) async {
    if (_session == null) throw const CloudApiException('session_expired');
    if (!_session!.expiresAt.isAfter(
      _clock().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
    }
    try {
      return await action(_session!.accessToken);
    } on CloudApiException catch (error) {
      if (!_authenticationRejected(error)) rethrow;
      await _refresh();
      try {
        return await action(_session!.accessToken);
      } on CloudApiException catch (retryError) {
        if (_authenticationRejected(retryError)) {
          await _invalidateExpiredSession();
        }
        rethrow;
      }
    }
  }

  bool _authenticationRejected(CloudApiException error) =>
      error.code == 'unauthorized' || error.code == 'session_expired';

  Future<void> synchronize() {
    // Foreground edits/resume notifications respect an existing backoff. The
    // explicit UI retry action can bypass it through retryNow().
    if (_retryTimer != null) return Future<void>.value();
    return _exclusive('sync', _trySync);
  }

  Future<void> retryNow() {
    _cancelRetry(resetAttempts: true);
    return synchronize();
  }

  Future<void> _trySync() async {
    try {
      await _sync();
    } catch (error) {
      _fail(error);
    }
  }

  void _cancelRetry({bool resetAttempts = false}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (resetAttempts) _retryAttempts = 0;
  }

  void _scheduleRetry() {
    if (_disposed ||
        _session == null ||
        _retryTimer != null ||
        _retryAttempts >= retryDelays.length)
      return;
    final delay = retryDelays[_retryAttempts++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed && _session != null) {
        unawaited(_exclusive('sync', _trySync));
      }
    });
  }

  Future<void> _sync() async {
    if (!configured) {
      _set(CloudSyncStatus.unconfigured);
      return;
    }
    final owner = _session?.ownerId;
    if (owner == null) {
      _set(CloudSyncStatus.signedOut);
      return;
    }
    _set(CloudSyncStatus.syncing);
    _cache = await cache.read();
    if (_cache.ownerId != owner) {
      final remote = await _authorized(api.getState);
      await cache.activate(owner, remote);
      await onApplied?.call();
      _cache = await cache.read();
      if (_cache.ownerId != owner) {
        throw const CloudApiException('session_expired');
      }
    }
    if (_cache.errorCode != null) {
      _set(_cacheStatus(), _cache.errorCode);
      return;
    }
    var wrote = false;
    for (var i = 0; i < 100 && _cache.pending.isNotEmpty; i++) {
      final mutation = _cache.pending.first;
      try {
        final remote = await _authorized((token) => api.sync(token, mutation));
        if (!await cache.acknowledge(owner, mutation.mutationId, remote)) {
          _cache = await cache.read();
          _set(_cacheStatus());
          return;
        }
        wrote = true;
        await onApplied?.call();
        _cache = await cache.read();
        if (_cache.errorCode != null) {
          _set(_cacheStatus(), _cache.errorCode);
          return;
        }
      } on CloudApiException catch (error) {
        if (error.status == 409 ||
            error.status == 422 ||
            error.code == 'invalid_transition' ||
            error.code == 'deadline_passed' ||
            error.code == 'history_conflict' ||
            error.code == 'mutation_reused' ||
            error.code == 'payload_too_large') {
          await cache.markConflict(owner, error.snapshot, error.code);
          _cache = await cache.read();
        }
        rethrow;
      }
    }
    if (_cache.pending.isEmpty && !wrote) {
      // activate must re-read local state under the gate and refuse to overwrite
      // any write that arrived during this GET, including a headless deadline.
      final remote = await _authorized(api.getState);
      await cache.activate(owner, remote);
      await onApplied?.call();
      _cache = await cache.read();
    }
    _set(_cacheStatus());
    _cancelRetry(resetAttempts: true);
  }

  Future<void> restoreCloud() => _exclusive('restore', () async {
    if (_session == null) return;
    _set(CloudSyncStatus.restoring);
    try {
      final remote = await _authorized(api.getState);
      await cache.restoreCloud(_session!.ownerId, remote);
      await onApplied?.call();
      _cache = await cache.read();
      _set(_cacheStatus());
    } catch (error) {
      _fail(error);
    }
  });

  Future<void> signOut() {
    _cancelRetry(resetAttempts: true);
    return _exclusive('sign-out', () async {
      _cancelRetry(resetAttempts: true);
      final previous = _session;
      try {
        // Isolate private data first; network revocation may be unavailable.
        await cache.signOut();
        await sessionStore.clear();
        _session = null;
        await onApplied?.call();
        _cache = await cache.read();
        _set(
          configured ? CloudSyncStatus.signedOut : CloudSyncStatus.unconfigured,
        );
        if (previous != null) {
          try {
            await api.logout(previous.refreshToken);
          } catch (_) {
            /* Local sign-out remains complete. */
          }
        }
      } catch (error) {
        _fail(error);
      }
    });
  }

  CloudSyncStatus _cacheStatus() => _cache.errorCode == 'revision_conflict'
      ? CloudSyncStatus.conflict
      : _cache.errorCode != null
      ? CloudSyncStatus.rejected
      : _cache.pending.isNotEmpty
      ? CloudSyncStatus.pending
      : CloudSyncStatus.synced;

  void _fail(Object error) {
    final code = error is CloudApiException
        ? error.code
        : error is StateError && error.message == 'cloud_queue_full'
        ? 'cloud_queue_full'
        : 'local_storage_error';
    _set(switch (code) {
      'unconfigured' || 'invalid_configuration' => CloudSyncStatus.unconfigured,
      'network_error' || 'service_unavailable' => CloudSyncStatus.offline,
      'unauthorized' || 'session_expired' => CloudSyncStatus.sessionExpired,
      'revision_conflict' => CloudSyncStatus.conflict,
      _ => CloudSyncStatus.rejected,
    }, code);
    if (code == 'network_error' ||
        code == 'service_unavailable' ||
        code == 'rate_limited') {
      _scheduleRetry();
    } else {
      _cancelRetry(resetAttempts: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRetry();
    super.dispose();
  }
}
