import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, debugPrintStack, visibleForTesting;
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';
import 'package:streak/services/firebase_sync_hash.dart';

/// Firebase transport for a configured Level Up project.
///
/// Authentication and user-scoped state are owned by Firebase. Planner
/// snapshots are committed with revision-checked Firestore transactions.
class FirebaseCloudApi
    implements
        CloudApi,
        CloudStateWatcher,
        CloudPasswordResetEmailFlow,
        CloudCurrentSessionReader {
  FirebaseCloudApi({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _clock = clock ?? DateTime.now;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  @override
  bool get configured => true;

  @override
  bool get passwordResetCompletesInEmail => true;

  DocumentReference<Map<String, dynamic>> _state(String uid) =>
      _firestore.doc('users/$uid/planner/state');

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const CloudApiException('unauthorized', status: 401);
    }
    return user;
  }

  CloudUser _cloudUser(User user) {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw const CloudApiException('missing_email');
    }
    final providers = user.providerData.map((provider) => provider.providerId);
    return CloudUser(
      id: user.uid,
      email: email,
      hasPassword: providers.contains('password'),
      hasGoogle: providers.contains('google.com'),
    );
  }

  Future<CloudSession> _session(User user, {bool forceRefresh = false}) async {
    try {
      final token = await user.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) {
        throw const CloudApiException('unauthorized', status: 401);
      }
      final tokenResult = await user.getIdTokenResult();
      return CloudSession(
        user: _cloudUser(user),
        accessToken: token,
        // Firebase Auth refresh credentials stay in the platform SDK's secure
        // store. This marker is intentionally not a Firebase refresh token.
        refreshToken: 'firebase-sdk',
        expiresAt:
            tokenResult.expirationTime ??
            _clock().add(const Duration(minutes: 55)),
      );
    } on FirebaseException catch (error, stackTrace) {
      _logFirebaseFailure(
        'Firebase Auth ID-token/session creation',
        'firebase-auth/users/${user.uid}',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  void _logFirebaseFailure(
    String operation,
    String path,
    FirebaseException error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[Firebase] $operation failed path=$path '
      'plugin=${error.plugin} code=${error.code} message=${error.message}',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  Future<CloudSession?> currentSession() async {
    final user = _auth.currentUser;
    debugPrint(
      '[FirebaseAuth] current session ${user == null ? 'is signed out.' : 'found uid=${user.uid}.'}',
    );
    return user == null ? null : _session(user);
  }

  String _authCode(String code, {required String operation}) =>
      mapFirebaseAuthErrorCode(code, operation: operation);

  CloudApiException _authError(
    FirebaseAuthException error, {
    required String operation,
    StackTrace? stackTrace,
  }) {
    debugPrint(
      '[FirebaseAuth] $operation failed plugin=${error.plugin} '
      'code=${error.code} exception=${error.toString()}',
    );
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
    return CloudApiException(_authCode(error.code, operation: operation));
  }

  CloudApiException _firestoreError(
    FirebaseException error, {
    required String operation,
    required String path,
    StackTrace? stackTrace,
  }) {
    if (stackTrace != null) {
      _logFirebaseFailure(operation, path, error, stackTrace);
    } else {
      debugPrint(
        '[Firestore] $operation failed path=$path '
        'plugin=${error.plugin} code=${error.code} message=${error.message}',
      );
    }
    return CloudApiException(switch (error.code) {
      'permission-denied' => 'firestore_permission_denied',
      'unauthenticated' => 'firestore_unauthenticated',
      'unavailable' || 'deadline-exceeded' => 'firestore_unavailable',
      'failed-precondition' => 'firestore_failed_precondition',
      'resource-exhausted' => 'payload_too_large',
      _ => 'service_unavailable',
    });
  }

  @override
  Future<CloudSession> register(String email, String password) async {
    debugPrint('[FirebaseAuth] starting email/password registration.');
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const CloudApiException('service_unavailable');
      debugPrint(
        '[FirebaseAuth] email/password account created uid=${user.uid}.',
      );
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'email/password registration',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<CloudSession> login(String email, String password) async {
    debugPrint('[FirebaseAuth] starting email/password sign-in.');
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const CloudApiException('invalid_credentials');
      debugPrint('[FirebaseAuth] email/password accepted uid=${user.uid}.');
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'email/password sign-in',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<CloudSession> google(String idToken) async {
    debugPrint(
      '[FirebaseAuth] exchanging Google ID token for Firebase credential.',
    );
    try {
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) throw const CloudApiException('invalid_google_token');
      debugPrint(
        '[FirebaseAuth] Google credential accepted; creating Firebase session.',
      );
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'Google credential exchange',
        stackTrace: stackTrace,
      );
    } on CloudApiException catch (error, stackTrace) {
      debugPrint(
        '[FirebaseAuth] Google session creation failed code=${error.code}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<CloudSession> refresh(String refreshToken) async {
    try {
      return await _session(_requireUser(), forceRefresh: true);
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'Firebase token refresh',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> logout(String refreshToken) => _auth.signOut();

  @override
  Future<CloudUser> linkGoogle(String accessToken, String idToken) async {
    try {
      final user = _requireUser();
      final result = await user.linkWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      final linked = result.user;
      if (linked == null) {
        throw const CloudApiException('service_unavailable');
      }
      return _cloudUser(linked);
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'Google account linking',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> requestPasswordReset(
    String email, {
    String? languageCode,
  }) async {
    try {
      // Firebase sends its built-in password-reset template (Console >
      // Authentication > Templates) in this language when one exists.
      await _auth.setLanguageCode(languageCode);
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error, stackTrace) {
      // Preserve account privacy. Firebase may still report a missing user
      // depending on the project's email-enumeration settings.
      if (error.code == 'user-not-found') return;
      throw _authError(
        error,
        operation: 'password reset email',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  ) async {
    try {
      await _auth.confirmPasswordReset(
        code: token.trim(),
        newPassword: password,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      throw _authError(
        error,
        operation: 'password reset confirmation',
        stackTrace: stackTrace,
      );
    }
  }

  CloudSnapshot _snapshotFromValues(Map<String, dynamic>? value) {
    if (value == null) return CloudSnapshot(revision: 0);
    final revision = value['revision'];
    final state = value['state'];
    final settings = value['settings'];
    if (revision is! int || revision < 0 || (state != null && state is! Map)) {
      throw const CloudApiException('invalid_response');
    }
    final updatedAt = value['updatedAt'];
    return CloudSnapshot(
      revision: revision,
      state: state is Map ? cloudMap(state) : null,
      settings: settings is Map ? cloudMap(settings) : const {},
      timeZone: value['timeZone'] as String?,
      serverTime: updatedAt is Timestamp ? updatedAt.toDate().toUtc() : null,
    );
  }

  CloudSnapshot _snapshotFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => _snapshotFromValues(document.data());

  @override
  Future<CloudSnapshot> getState(String accessToken) async {
    late final String path;
    try {
      final user = _requireUser();
      final reference = _state(user.uid);
      path = reference.path;
      return _snapshotFromDocument(await reference.get());
    } on FirebaseException catch (error, stackTrace) {
      throw _firestoreError(
        error,
        operation: 'get planner state',
        path: path,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Stream<CloudSnapshot> watchState(String accessToken) {
    final user = _requireUser();
    return _state(user.uid)
        .snapshots()
        .map(_snapshotFromDocument)
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object error,
                  StackTrace trace,
                  EventSink<CloudSnapshot> sink,
                ) {
                  if (error is FirebaseException) {
                    sink.addError(
                      _firestoreError(
                        error,
                        operation: 'listen to planner state',
                        path: _state(_auth.currentUser?.uid ?? '{uid}').path,
                        stackTrace: trace,
                      ),
                      trace,
                    );
                  } else {
                    sink.addError(error, trace);
                  }
                },
          ),
        );
  }

  @override
  Future<CloudSnapshot> sync(
    String accessToken,
    CloudMutation mutation,
  ) async {
    var path = 'users/{uid}/planner/state';
    try {
      final user = _requireUser();
      final state = PlannerState.fromMap(mutation.state).toMap();
      final settings = mutation.settings.isEmpty
          ? <String, dynamic>{'locale': 'en'}
          : cloudMap(mutation.settings);
      final request = {
        'mutationId': mutation.mutationId,
        'baseRevision': mutation.baseRevision,
        'state': state,
        'settings': settings,
        'timeZone': mutation.timeZone,
      };
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(mutation.mutationId) ||
          mutation.baseRevision < 0 ||
          mutation.timeZone.isEmpty ||
          mutation.timeZone.length > 100 ||
          settings.keys.toSet().difference({'locale'}).isNotEmpty ||
          !const {'en', 'ar'}.contains(settings['locale'])) {
        throw const CloudApiException('invalid_transition');
      }
      if (utf8.encode(jsonEncode(request)).length > 900000) {
        throw const CloudApiException('payload_too_large');
      }
      final stateRef = _state(user.uid);
      path = stateRef.path;
      final mutationRef = stateRef
          .collection('mutations')
          .doc(mutation.mutationId);
      final requestHash = firebaseSyncHash(request);
      return await _firestore.runTransaction<CloudSnapshot>((
        transaction,
      ) async {
        final documents = await Future.wait([
          transaction.get(stateRef),
          transaction.get(mutationRef),
        ]);
        final current = _snapshotFromValues(documents[0].data());
        final accepted = documents[1].data();
        if (accepted != null) {
          if (accepted['requestHash'] != requestHash) {
            throw const CloudApiException('mutation_reused', status: 409);
          }
          if (accepted['revision'] == current.revision) return current;
          throw CloudApiException(
            'revision_conflict',
            status: 409,
            snapshot: current,
          );
        }
        if (current.revision != mutation.baseRevision) {
          throw CloudApiException(
            'revision_conflict',
            status: 409,
            snapshot: current,
          );
        }
        final nextRevision = current.revision + 1;
        final now = _clock().toUtc();
        transaction.set(stateRef, {
          'schemaVersion': 1,
          'revision': nextRevision,
          'state': state,
          'settings': settings,
          'timeZone': mutation.timeZone,
          'lastMutationId': mutation.mutationId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(mutationRef, {
          'requestHash': requestHash,
          'baseRevision': current.revision,
          'revision': nextRevision,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return CloudSnapshot(
          revision: nextRevision,
          state: state,
          settings: settings,
          timeZone: mutation.timeZone,
          serverTime: now,
        );
      });
    } on CloudApiException {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      throw _firestoreError(
        error,
        operation: 'write planner state and mutation transaction',
        path: path,
        stackTrace: stackTrace,
      );
    } on StateError {
      throw const CloudApiException('invalid_transition');
    } on FormatException {
      throw const CloudApiException('invalid_transition');
    }
  }
}

/// Maps Firebase Auth failures to safe app-level error codes.
///
/// An invalid Google credential usually means Firebase did not accept the
/// provider token/client configuration. Keep that distinct from a rejected
/// email/password login so the UI can show the correct recovery steps.
@visibleForTesting
String mapFirebaseAuthErrorCode(String code, {required String operation}) {
  final isGoogleOperation = operation.toLowerCase().contains('google');
  return switch (code) {
    'email-already-in-use' => 'email_exists',
    'invalid-email' => 'invalid_email',
    'weak-password' => 'weak_password',
    'wrong-password' || 'user-not-found' => 'invalid_credentials',
    'invalid-credential' =>
      isGoogleOperation ? 'google_credential_rejected' : 'invalid_credentials',
    'network-request-failed' => 'network_error',
    'operation-not-allowed' =>
      isGoogleOperation
          ? 'google_provider_disabled'
          : 'email_provider_disabled',
    'app-not-authorized' || 'invalid-api-key' => 'firebase_configuration',
    'user-disabled' => 'account_disabled',
    'user-token-expired' => 'session_expired',
    'too-many-requests' => 'rate_limited',
    'credential-already-in-use' ||
    'provider-already-linked' => 'google_already_linked',
    'account-exists-with-different-credential' => 'google_link_required',
    'requires-recent-login' => 'session_expired',
    'expired-action-code' || 'invalid-action-code' => 'invalid_reset_token',
    _ => 'service_unavailable',
  };
}

/// Deliberately has no network fallback. Until FlutterFire configuration exists,
/// the app stays local-first and asks for Firebase setup.
class FirebaseUnavailableCloudApi implements CloudApi {
  const FirebaseUnavailableCloudApi();

  @override
  bool get configured => false;

  Never _unconfigured() => throw const CloudApiException('unconfigured');

  @override
  Future<CloudSession> register(String email, String password) async =>
      _unconfigured();
  @override
  Future<CloudSession> login(String email, String password) async =>
      _unconfigured();
  @override
  Future<CloudSession> google(String idToken) async => _unconfigured();
  @override
  Future<CloudSession> refresh(String refreshToken) async => _unconfigured();
  @override
  Future<void> logout(String refreshToken) async {}
  @override
  Future<CloudUser> linkGoogle(String accessToken, String idToken) async =>
      _unconfigured();
  @override
  Future<void> requestPasswordReset(
    String email, {
    String? languageCode,
  }) async => _unconfigured();
  @override
  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  ) async => _unconfigured();
  @override
  Future<CloudSnapshot> getState(String accessToken) async => _unconfigured();
  @override
  Future<CloudSnapshot> sync(
    String accessToken,
    CloudMutation mutation,
  ) async => _unconfigured();
}

/// Firebase Auth persists and refreshes its own credentials through the native
/// SDK. Storing duplicate Firebase tokens in the app's planner cache would add
/// risk without improving restoration, so this store keeps no token material.
class FirebaseCloudSessionStore implements CloudSessionStore {
  const FirebaseCloudSessionStore(this._api);

  final FirebaseCloudApi _api;

  @override
  Future<CloudSession?> read() => _api.currentSession();

  @override
  Future<void> write(CloudSession session) async {}

  @override
  Future<void> clear() => _api.logout('firebase-sdk');
}

class FirebaseUnavailableSessionStore implements CloudSessionStore {
  const FirebaseUnavailableSessionStore();
  @override
  Future<CloudSession?> read() async => null;
  @override
  Future<void> write(CloudSession session) async {}
  @override
  Future<void> clear() async {}
}
