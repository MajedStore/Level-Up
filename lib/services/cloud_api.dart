// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  Future<CloudSession> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<CloudSnapshot> getState(String accessToken);
  Future<CloudSnapshot> sync(String accessToken, CloudMutation mutation);
}

class CloudHttpApi implements CloudApi {
  CloudHttpApi({
    String? baseUrl,
    HttpClient? client,
    bool? allowInsecure,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _client = client ?? HttpClient(),
       _clock = clock ?? DateTime.now,
       _base = _parseBase(
         baseUrl ?? const String.fromEnvironment('LEVEL_UP_API_BASE_URL'),
         allowInsecure ??
             (!kReleaseMode &&
                 const bool.fromEnvironment('LEVEL_UP_ALLOW_INSECURE_API')),
       );
  final HttpClient _client;
  final Uri? _base;
  final Duration timeout;
  final DateTime Function() _clock;
  static const maxBodyBytes = 2 * 1024 * 1024;

  static Uri? _parseBase(String raw, bool allowInsecure) {
    if (raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(allowInsecure && uri.scheme == 'http'))) {
      throw const CloudApiException('invalid_configuration');
    }
    return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/');
  }

  @override
  bool get configured => _base != null;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    if (_base == null) throw const CloudApiException('unconfigured');
    try {
      return await (() async {
        final bytes = body == null ? null : utf8.encode(jsonEncode(body));
        if (bytes != null && bytes.length > maxBodyBytes) {
          throw const CloudApiException('payload_too_large');
        }
        final request = await _client.openUrl(method, _base.resolve(path));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (token != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        if (bytes != null) {
          request.headers.contentType = ContentType.json;
          request.add(bytes);
        }
        final response = await request.close();
        final chunks = <int>[];
        await for (final chunk in response) {
          chunks.addAll(chunk);
          if (chunks.length > maxBodyBytes) {
            throw const CloudApiException('invalid_response');
          }
        }
        final decoded = chunks.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(utf8.decode(chunks));
        if (decoded is! Map) throw const CloudApiException('invalid_response');
        final value = cloudMap(decoded);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final error = value['error'];
          final code = error is Map && error['code'] is String
              ? error['code'] as String
              : 'service_unavailable';
          throw CloudApiException(
            code,
            status: response.statusCode,
            snapshot: value['revision'] is int
                ? CloudSnapshot.fromMap(value)
                : null,
          );
        }
        return value;
      })().timeout(timeout);
    } on CloudApiException {
      rethrow;
    } on TimeoutException {
      throw const CloudApiException('network_error');
    } on SocketException {
      throw const CloudApiException('network_error');
    } on HttpException {
      throw const CloudApiException('network_error');
    } on HandshakeException {
      throw const CloudApiException('network_error');
    } on FormatException {
      throw const CloudApiException('invalid_response');
    } on TypeError {
      throw const CloudApiException('invalid_response');
    }
  }

  Future<CloudSession> _auth(String action, Map<String, dynamic> body) async =>
      CloudSession.fromMap(
        await _request('POST', 'api/v1/auth/$action', body: body),
        now: _clock(),
      );
  @override
  Future<CloudSession> register(String email, String password) =>
      _auth('register', {'email': email.trim(), 'password': password});
  @override
  Future<CloudSession> login(String email, String password) =>
      _auth('login', {'email': email.trim(), 'password': password});
  @override
  Future<CloudSession> refresh(String refreshToken) =>
      _auth('refresh', {'refreshToken': refreshToken});
  @override
  Future<void> logout(String refreshToken) async {
    await _request(
      'POST',
      'api/v1/auth/logout',
      body: {'refreshToken': refreshToken},
    );
  }

  @override
  Future<CloudSnapshot> getState(String accessToken) async =>
      CloudSnapshot.fromMap(
        await _request('GET', 'api/v1/state', token: accessToken),
      );
  @override
  Future<CloudSnapshot> sync(
    String accessToken,
    CloudMutation mutation,
  ) async => CloudSnapshot.fromMap(
    await _request(
      'POST',
      'api/v1/sync',
      token: accessToken,
      body: mutation.toMap(),
    ),
  );
  void close() => _client.close(force: true);
}
