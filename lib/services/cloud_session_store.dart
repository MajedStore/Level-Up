// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:streak/services/cloud_models.dart';

class CloudUser {
  const CloudUser({
    required this.id,
    required this.email,
    this.hasPassword = true,
    this.hasGoogle = false,
  });
  final String id;
  final String email;
  final bool hasPassword;
  final bool hasGoogle;
  factory CloudUser.fromMap(Map<String, dynamic> value) {
    final id = value['id'];
    final email = value['email'];
    if (id is! String || id.isEmpty || email is! String || email.isEmpty) {
      throw const FormatException('Invalid account.');
    }
    return CloudUser(
      id: id,
      email: email,
      hasPassword: value['hasPassword'] is bool
          ? value['hasPassword'] as bool
          : true,
      hasGoogle: value['hasGoogle'] is bool
          ? value['hasGoogle'] as bool
          : false,
    );
  }
  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'hasPassword': hasPassword,
    'hasGoogle': hasGoogle,
  };
}

class CloudSession {
  const CloudSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  final CloudUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  String get ownerId => user.id;
  CloudSession withUser(CloudUser value) => CloudSession(
    user: value,
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
  );

  factory CloudSession.fromMap(Map<String, dynamic> value, {DateTime? now}) {
    final access = value['accessToken'];
    final refresh = value['refreshToken'];
    final user = value['user'];
    final expiresIn = value['expiresIn'];
    final savedExpiry = value['expiresAt'];
    if (access is! String ||
        access.isEmpty ||
        access.length > 16384 ||
        access.contains(RegExp(r'[\r\n]')) ||
        refresh is! String ||
        refresh.isEmpty ||
        refresh.length > 256 ||
        user is! Map ||
        (savedExpiry is! String &&
            (expiresIn is! int || expiresIn < 1 || expiresIn > 3600))) {
      throw const FormatException('Invalid session.');
    }
    final expiresAt = savedExpiry is String
        ? DateTime.tryParse(savedExpiry)
        : (now ?? DateTime.now()).add(Duration(seconds: expiresIn as int));
    if (expiresAt == null) throw const FormatException('Invalid session.');
    return CloudSession(
      user: CloudUser.fromMap(cloudMap(user)),
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
    );
  }
  Map<String, dynamic> toMap() => {
    'user': user.toMap(),
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

abstract interface class CloudSessionStore {
  Future<CloudSession?> read();
  Future<void> write(CloudSession session);
  Future<void> clear();
}

/// Private account drafts are encrypted at rest and never listed across owners.
class CloudSecureArchiveStore implements CloudArchiveStore {
  CloudSecureArchiveStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage _storage;
  String _key(String ownerId) =>
      'levelup.cloud.archive.v1.${base64Url.encode(utf8.encode(ownerId))}';
  @override
  Future<String?> read(String ownerId) => _storage.read(key: _key(ownerId));
  @override
  Future<void> write(String ownerId, String json) =>
      _storage.write(key: _key(ownerId), value: json);
}
