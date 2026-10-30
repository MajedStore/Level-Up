import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/cloud_models.dart';

/// Synchronizes account-owned records that are outside the XP planner model.
///
/// The client never writes this document directly. Every update is an
/// idempotent callable transaction, while the document listener supplies
/// offline-cache-backed, real-time updates from another device.
class FirebasePrivateDataSync {
  FirebasePrivateDataSync({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Future<void> Function()? onApplied,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _onApplied = onApplied;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Future<void> Function()? _onApplied;
  final _uuid = const Uuid();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _updates;
  Timer? _settle;
  String? _ownerId;
  int _revision = 0;
  bool _dirty = false;
  bool _writing = false;
  bool _applyingRemote = false;
  bool _disposed = false;

  DocumentReference<Map<String, dynamic>> _state(String uid) =>
      _firestore.doc('users/$uid/private/state');

  void _onLocalChanged() {
    if (_disposed || _ownerId == null || _applyingRemote) return;
    _dirty = true;
    _settle?.cancel();
    _settle = Timer(const Duration(seconds: 2), () => unawaited(synchronize()));
  }

  Future<void> activate(String? ownerId) async {
    _settle?.cancel();
    await _updates?.cancel();
    _updates = null;
    _ownerId = ownerId;
    _revision = 0;
    _dirty = false;
    if (_disposed || ownerId == null) return;

    final document = await _state(ownerId).get();
    await _applyDocument(document, initial: true);
    _updates = _state(ownerId).snapshots().listen(
      (document) => unawaited(_applyDocument(document)),
      // Cached local data stays usable when a listener is temporarily offline.
      onError: (_, __) {},
    );
  }

  Future<void> _applyDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    bool initial = false,
  }) async {
    if (_disposed || document.id != 'state') return;
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
    try {
      await LocalStore.replaceFirebasePrivateData(cloudMap(data));
      _revision = revision;
      await _onApplied?.call();
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> synchronize() async {
    if (_disposed || _ownerId == null || !_dirty || _writing) return;
    _writing = true;
    try {
      final data = cloudMap(LocalStore.firebasePrivateSnapshot());
      final result = await _functions
          .httpsCallable(
            'syncPrivateData',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call({
            'mutationId': _uuid.v4(),
            'baseRevision': _revision,
            'data': data,
          });
      if (result.data is! Map) return;
      final response = cloudMap(result.data as Map);
      final revision = response['revision'];
      final returnedData = response['data'];
      if (revision is int && revision >= 0 && returnedData is Map) {
        _revision = revision;
        _dirty = false;
      }
    } on FirebaseFunctionsException {
      // Keep the dirty bit: the next local write, account reactivation or app
      // foreground sync will retry with the retained local snapshot.
    } finally {
      _writing = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _settle?.cancel();
    LocalStore.removeChangeListener(_onLocalChanged);
    await _updates?.cancel();
  }

  void start() => LocalStore.addChangeListener(_onLocalChanged);
}
