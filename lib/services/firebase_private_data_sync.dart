import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:uuid/uuid.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/firebase_sync_hash.dart';

/// Synchronizes account-owned records that are outside the XP planner model.
///
/// Every update uses an idempotent owner-scoped Firestore transaction, while
/// the document listener supplies
/// offline-cache-backed, real-time updates from another device.
class FirebasePrivateDataSync {
  FirebasePrivateDataSync({
    FirebaseFirestore? firestore,
    Future<void> Function()? onApplied,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _onApplied = onApplied;

  final FirebaseFirestore _firestore;
  final Future<void> Function()? _onApplied;
  final _uuid = const Uuid();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _updates;
  Timer? _settle;
  String? _ownerId;
  int _revision = 0;
  int _localVersion = 0;
  bool _dirty = false;
  bool _writing = false;
  bool _applyingRemote = false;
  bool _disposed = false;
  Completer<void>? _applyCompletion;

  DocumentReference<Map<String, dynamic>> _state(String uid) =>
      _firestore.doc('users/$uid/private/state');

  String _revisionKey(String uid) => 'firebasePrivateRevision.$uid';
  String _dirtyKey(String uid) => 'firebasePrivateDirty.$uid';
  String _pendingKey(String uid) => 'firebasePrivateMutation.$uid';

  Future<void> _saveMetadata(String uid) async {
    final revision = _revision;
    final dirty = _dirty;
    await LocalStore.writeSetting(_revisionKey(uid), revision);
    await LocalStore.writeSetting(_dirtyKey(uid), dirty);
  }

  void _onLocalChanged() {
    if (_disposed || _ownerId == null || _applyingRemote) return;
    _localVersion++;
    _dirty = true;
    unawaited(_saveMetadata(_ownerId!));
    _settle?.cancel();
    _settle = Timer(const Duration(seconds: 2), () => unawaited(synchronize()));
  }

  Future<void> activate(String? ownerId) async {
    _settle?.cancel();
    await _updates?.cancel();
    _updates = null;
    await _applyCompletion?.future;
    _ownerId = ownerId;
    _localVersion = 0;
    _revision = ownerId == null
        ? 0
        : LocalStore.setting(_revisionKey(ownerId), 0);
    _dirty = ownerId != null && LocalStore.setting(_dirtyKey(ownerId), false);
    if (_disposed || ownerId == null) return;

    final stateRef = _state(ownerId);
    late final DocumentSnapshot<Map<String, dynamic>> document;
    try {
      document = await stateRef.get();
    } on FirebaseException catch (error, stackTrace) {
      _logFirestoreFailure(
        'read private state',
        stateRef.path,
        error,
        stackTrace,
      );
      rethrow;
    }
    await _applyDocument(document, ownerId: ownerId, initial: true);
    if (_disposed || _ownerId != ownerId) return;
    _updates = _state(ownerId).snapshots().listen(
      (document) => unawaited(_applyDocument(document, ownerId: ownerId)),
      // Cached local data stays usable when a listener is temporarily offline.
      onError: (Object error, StackTrace stackTrace) {
        if (error is FirebaseException) {
          _logFirestoreFailure(
            'listen to private state',
            stateRef.path,
            error,
            stackTrace,
          );
        } else {
          debugPrint('[Firestore] listen to private state failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      },
    );
    if (_dirty) unawaited(synchronize());
  }

  Future<void> _applyDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String ownerId,
    bool initial = false,
  }) async {
    if (_disposed || _ownerId != ownerId || document.id != 'state') return;
    if (!document.exists) {
      if (initial) {
        _dirty = true;
        unawaited(synchronize());
      }
      return;
    }
    final value = document.data();
    final revision = value?['revision'];
    final data = value?['data'];
    if (revision is! int || revision < 0 || data is! Map) return;
    if (revision <= _revision || _dirty || _writing) return;
    _applyingRemote = true;
    final completion = Completer<void>();
    _applyCompletion = completion;
    try {
      await LocalStore.replaceFirebasePrivateData(cloudMap(data));
      _revision = revision;
      _dirty = false;
      final ownerId = _ownerId;
      if (ownerId != null) await _saveMetadata(ownerId);
      await _onApplied?.call();
    } finally {
      _applyingRemote = false;
      if (identical(_applyCompletion, completion)) _applyCompletion = null;
      completion.complete();
    }
  }

  Future<void> synchronize() async {
    if (_disposed || _ownerId == null || !_dirty || _writing) return;
    final ownerId = _ownerId!;
    final localVersion = _localVersion;
    _writing = true;
    try {
      final data = cloudMap(LocalStore.firebasePrivateSnapshot());
      if (data.keys.toSet().difference({
            'habits',
            'categories',
            'notes',
            'focus',
            'todos',
            'todoTags',
          }).isNotEmpty ||
          data.length != 6 ||
          data.values.any((value) => value is! Map) ||
          utf8.encode(jsonEncode(data)).length > 900000) {
        return;
      }
      final storedPending = LocalStore.setting<dynamic>(
        _pendingKey(ownerId),
        const <String, dynamic>{},
      );
      final pending = storedPending is Map
          ? cloudMap(storedPending)
          : <String, dynamic>{};
      final pendingData = pending['data'];
      final hasPending =
          pending['mutationId'] is String &&
          pending['baseRevision'] is int &&
          pendingData is Map;
      final mutationId = hasPending
          ? pending['mutationId'] as String
          : _uuid.v4();
      final baseRevision = hasPending
          ? pending['baseRevision'] as int
          : _revision;
      final requestData = hasPending ? cloudMap(pendingData) : data;
      final request = {
        'mutationId': mutationId,
        'baseRevision': baseRevision,
        'data': requestData,
      };
      if (!hasPending) {
        await LocalStore.writeSetting(_pendingKey(ownerId), request);
      }
      final stateRef = _state(ownerId);
      final mutationRef = stateRef.collection('mutations').doc(mutationId);
      final requestHash = firebaseSyncHash(request);
      final revision = await _firestore.runTransaction<int?>((
        transaction,
      ) async {
        final documents = await Future.wait([
          transaction.get(stateRef),
          transaction.get(mutationRef),
        ]);
        final currentData = documents[0].data();
        final currentRevision = currentData?['revision'] ?? 0;
        final accepted = documents[1].data();
        if (currentRevision is! int || currentRevision < 0) return null;
        if (accepted != null) {
          if (accepted['requestHash'] != requestHash ||
              accepted['revision'] != currentRevision) {
            return null;
          }
          return currentRevision;
        }
        if (currentRevision != baseRevision) return null;
        final nextRevision = currentRevision + 1;
        transaction.set(stateRef, {
          'schemaVersion': 1,
          'revision': nextRevision,
          'data': requestData,
          'lastMutationId': mutationId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(mutationRef, {
          'requestHash': requestHash,
          'baseRevision': currentRevision,
          'revision': nextRevision,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return nextRevision;
      });
      // An account switch or local edit can occur while the transaction is in
      // flight. Do not attribute its response to a different account, and do
      // not clear a newer pending local snapshot.
      if (revision != null && _ownerId == ownerId) {
        _revision = revision;
        _dirty =
            _localVersion != localVersion ||
            firebaseSyncHash(data) != firebaseSyncHash(requestData);
        await LocalStore.writeSetting(_pendingKey(ownerId), const {});
        await _saveMetadata(ownerId);
        if (_dirty) {
          _settle?.cancel();
          _settle = Timer(
            const Duration(milliseconds: 250),
            () => unawaited(synchronize()),
          );
        }
      }
    } on FirebaseException catch (error, stackTrace) {
      // Keep local changes queued while offline or when rules reject a write.
      _logFirestoreFailure(
        'write private state and mutation transaction',
        'users/$ownerId/private/state',
        error,
        stackTrace,
      );
    } finally {
      _writing = false;
      if (!_disposed && _ownerId != ownerId && _ownerId != null && _dirty) {
        _settle?.cancel();
        _settle = Timer(
          const Duration(milliseconds: 250),
          () => unawaited(synchronize()),
        );
      }
    }
  }

  void _logFirestoreFailure(
    String operation,
    String path,
    FirebaseException error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[Firestore] $operation failed path=$path '
      'plugin=${error.plugin} code=${error.code} message=${error.message}',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  Future<void> dispose() async {
    _disposed = true;
    _settle?.cancel();
    LocalStore.removeChangeListener(_onLocalChanged);
    await _updates?.cancel();
  }

  void start() => LocalStore.addChangeListener(_onLocalChanged);
}
