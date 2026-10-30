// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:streak/services/cloud_models.dart';

class CloudUser {
  const CloudUser({required this.id, required this.email});
  final String id;
  final String email;
  factory CloudUser.fromMap(Map<String, dynamic> value) {
    final id = value['id'];
    final email = value['email'];
    if (id is! String || id.isEmpty || email is! String || email.isEmpty) {
      throw const FormatException('Invalid account.');
    }
    return CloudUser(id: id, email: email);
  }
  Map<String, dynamic> toMap() => {'id': id, 'email': email};
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

  factory CloudSession.fromMap(Map<String, dynamic> value, {DateTime? now}) {
    final access = value['accessToken'];
    final refresh = value['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const FormatException('Invalid session.');
    }
    return CloudSession(
      user: CloudUser.fromMap(cloudMap(value['user'] as Map)),
      accessToken: access,
      refreshToken: refresh,
      expiresAt: value['expiresAt'] is String
          ? DateTime.parse(value['expiresAt'] as String)
          : (now ?? DateTime.now()).add(
              Duration(seconds: value['expiresIn'] as int),
            ),
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

/// Tokens never enter Hive, backups or planner projection. The whole session is
/// one encrypted value so refresh-token rotation does not tear across keys.
class CloudSecureSessionStore implements CloudSessionStore {
  CloudSecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'levelup.cloud.session.v1';
  @override
  Future<CloudSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    return CloudSession.fromMap(cloudMap(jsonDecode(value) as Map));
  }

  @override
  Future<void> write(CloudSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toMap()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
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
