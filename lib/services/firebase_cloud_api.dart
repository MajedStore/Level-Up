import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';

/// Firebase transport for a configured Level Up project.
///
/// Authentication is owned by Firebase Auth. Planner writes go through the
/// `syncPlannerState` callable rather than direct Firestore writes, so the
/// server-side progression validation stays authoritative.
class FirebaseCloudApi
    implements CloudApi, CloudStateWatcher, CloudPasswordResetEmailFlow {
  FirebaseCloudApi({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    DateTime Function()? clock,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _clock = clock ?? DateTime.now;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
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
  }

  Future<CloudSession?> currentSession() async {
    final user = _auth.currentUser;
    return user == null ? null : _session(user);
  }

  String _authCode(String code) => switch (code) {
    'email-already-in-use' => 'email_exists',
    'invalid-email' => 'invalid_email',
    'weak-password' => 'weak_password',
    'wrong-password' ||
    'user-not-found' ||
    'invalid-credential' => 'invalid_credentials',
    'network-request-failed' => 'network_error',
    'too-many-requests' => 'rate_limited',
    'credential-already-in-use' ||
    'provider-already-linked' => 'google_already_linked',
    'account-exists-with-different-credential' => 'google_link_required',
    'requires-recent-login' => 'session_expired',
    'expired-action-code' || 'invalid-action-code' => 'invalid_reset_token',
    _ => 'service_unavailable',
  };

  CloudApiException _authError(FirebaseAuthException error) =>
      CloudApiException(_authCode(error.code));

  CloudApiException _firestoreError(FirebaseException error) =>
      CloudApiException(
        switch (error.code) {
          'permission-denied' || 'unauthenticated' => 'unauthorized',
          'unavailable' || 'deadline-exceeded' => 'network_error',
          'resource-exhausted' => 'payload_too_large',
          _ => 'service_unavailable',
        },
      );

  CloudApiException _functionError(FirebaseFunctionsException error) {
    final firebaseCode = error.code.toString().split('.').last;
    CloudSnapshot? snapshot;
    final details = error.details;
    if (details is Map && details['snapshot'] is Map) {
      try {
        snapshot = CloudSnapshot.fromMap(cloudMap(details['snapshot'] as Map));
      } on FormatException {
        snapshot = null;
      }
    }
    final detailCode = details is Map && details['code'] is String
        ? details['code'] as String
        : null;
    final code =
        detailCode ??
        switch (firebaseCode) {
          'unauthenticated' || 'permission-denied' => 'unauthorized',
          'aborted' || 'failed-precondition' => 'revision_conflict',
          'already-exists' => 'mutation_reused',
          'invalid-argument' => 'invalid_transition',
          'resource-exhausted' => 'payload_too_large',
          'unavailable' || 'deadline-exceeded' => 'network_error',
          _ => 'service_unavailable',
        };
    return CloudApiException(code, snapshot: snapshot);
  }

  @override
  Future<CloudSession> register(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const CloudApiException('service_unavailable');
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  @override
  Future<CloudSession> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const CloudApiException('invalid_credentials');
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  @override
  Future<CloudSession> google(String idToken) async {
    try {
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) throw const CloudApiException('invalid_google_token');
      return await _session(user, forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  @override
  Future<CloudSession> refresh(String refreshToken) async {
    try {
      return await _session(_requireUser(), forceRefresh: true);
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
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
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // Preserve account privacy. Firebase may still report a missing user
      // depending on the project's email-enumeration settings.
      if (error.code == 'user-not-found') return;
      throw _authError(error);
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
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  CloudSnapshot _snapshotFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (!document.exists) return CloudSnapshot(revision: 0);
    final value = document.data();
    if (value == null) throw const CloudApiException('invalid_response');
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

  @override
  Future<CloudSnapshot> getState(String accessToken) async {
    try {
      final user = _requireUser();
      return _snapshotFromDocument(await _state(user.uid).get());
    } on FirebaseException catch (error) {
      throw _firestoreError(error);
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
                    sink.addError(_firestoreError(error), trace);
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
    try {
      final result = await _functions
          .httpsCallable(
            'syncPlannerState',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 60),
            ),
          )
          .call(mutation.toMap());
      if (result.data is! Map) {
        throw const CloudApiException('invalid_response');
      }
      return CloudSnapshot.fromMap(cloudMap(result.data as Map));
    } on FirebaseFunctionsException catch (error) {
      throw _functionError(error);
    } on FirebaseException catch (error) {
      throw _firestoreError(error);
    } on FormatException {
      throw const CloudApiException('invalid_response');
    }
  }
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
  Future<void> requestPasswordReset(String email) async => _unconfigured();
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
