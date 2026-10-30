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
  Future<void> requestPasswordReset(String email);
  Future<void> completePasswordReset(
    String email,
    String token,
    String password,
  );
  Future<CloudSnapshot> getState(String accessToken);
  Future<CloudSnapshot> sync(String accessToken, CloudMutation mutation);
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
