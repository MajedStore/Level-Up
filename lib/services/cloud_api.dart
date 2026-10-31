// Shared contracts for Firebase-backed account and planner synchronization.
import 'dart:async';

import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';

class CloudApiException implements Exception {
  const CloudApiException(this.code, {this.status, this.snapshot});
  final String code;
  final int? status;
  final CloudSnapshot? snapshot;
  @override
  String toString() => 'CloudApiException($code)';
}

abstract interface class CloudApi {
  bool get configured;
  Future<CloudSession> register(String email, String password);
  Future<CloudSession> login(String email, String password);
  Future<CloudSession> google(String idToken);
  Future<CloudSession> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<CloudUser> linkGoogle(String accessToken, String idToken);

  /// [languageCode] selects the localized reset email where the backend has
  /// one (Firebase Auth's built-in templates); null keeps its default.
  Future<void> requestPasswordReset(String email, {String? languageCode});
  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  );
  Future<CloudSnapshot> getState(String accessToken);
  Future<CloudSnapshot> sync(String accessToken, CloudMutation mutation);
}

/// A Firebase adapter can reconcile an account that Firebase Auth accepted
/// before a subsequent profile/planner restore failed.
abstract interface class CloudCurrentSessionReader {
  Future<CloudSession?> currentSession();
}

/// Firebase password-reset links are completed outside the app.
abstract interface class CloudPasswordResetEmailFlow {
  bool get passwordResetCompletesInEmail;
}

/// The authenticated user's Firestore planner document can be observed in
/// real time. Local queued changes always take precedence over an update.
abstract interface class CloudStateWatcher {
  Stream<CloudSnapshot> watchState(String accessToken);
}
