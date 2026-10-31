// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:streak/services/google_id_token_claims.dart';

/// Keeps provider-specific failures out of the account UI and never exposes
/// Google tokens beyond the immediate Firebase Authentication credential exchange.
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure(this.code);
  final String code;
}

abstract interface class GoogleIdTokenProvider {
  bool get configured;
  Future<String> authenticate();
}

/// A small boundary around the official plugin lets tests exercise real
/// cancellation/configuration handling without launching account UI.
abstract interface class GoogleSignInGateway {
  Future<void> initialize(String serverClientId);
  bool get supportsAuthenticate;
  Future<void> signOut();
  Future<String?> authenticate();
}

class _OfficialGoogleSignInGateway implements GoogleSignInGateway {
  static final instance = _OfficialGoogleSignInGateway();
  Future<void>? _initialization;
  String? _serverClientId;

  @override
  Future<void> initialize(String serverClientId) {
    if (_serverClientId != null && _serverClientId != serverClientId) {
      throw const GoogleSignInFailure('google_configuration');
    }
    _serverClientId = serverClientId;
    // GoogleSignIn is a singleton and must be initialized exactly once, even if
    // an account page/controller is rebuilt and constructs another adapter.
    return _initialization ??= GoogleSignIn.instance.initialize(
      // When empty, Android reads default_web_client_id generated from
      // google-services.json. An explicit Web client override supports an
      // existing Android OAuth client owned by another Google Cloud project.
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
  }

  @override
  bool get supportsAuthenticate => GoogleSignIn.instance.supportsAuthenticate();

  @override
  Future<void> signOut() => GoogleSignIn.instance.signOut();

  @override
  Future<String?> authenticate() async {
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
  }
}

class GoogleSignInService implements GoogleIdTokenProvider {
  GoogleSignInService({String? serverClientId, GoogleSignInGateway? gateway})
    : _serverClientId = (serverClientId ?? _defaultServerClientId).trim(),
      _gateway = gateway ?? _OfficialGoogleSignInGateway.instance;

  static String get _defaultServerClientId {
    // The Android OAuth client for this package/SHA is retained in
    // level-up-513216, so use that project's paired Web client. The Firebase
    // project's generated Web client is in a different Cloud project and
    // Credential Manager rejects that cross-project pair (error 28444).
    return const String.fromEnvironment(
      'LEVEL_UP_GOOGLE_SERVER_CLIENT_ID',
      defaultValue:
          '38989698072-c3s590e64bstmeh7d65vrd4luu0452d6.apps.googleusercontent.com',
    );
  }

  final String _serverClientId;
  final GoogleSignInGateway _gateway;
  Future<void>? _initialization;
  Future<String>? _inFlight;

  @override
  bool get configured =>
      _serverClientId.isNotEmpty ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<void> _initialize() =>
      _initialization ??= _gateway.initialize(_serverClientId);

  @override
  Future<String> authenticate() {
    final current = _inFlight;
    if (current != null) return current;
    return _inFlight = _authenticate().whenComplete(() => _inFlight = null);
  }

  Future<String> _authenticate() async {
    if (!configured) {
      debugPrint('Google Sign-In is not configured for this platform/build.');
      throw const GoogleSignInFailure('google_not_configured');
    }
    if (_serverClientId.isNotEmpty &&
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._-]*\.apps\.googleusercontent\.com$',
        ).hasMatch(_serverClientId)) {
      debugPrint('Google Sign-In has a malformed Web server client ID.');
      throw const GoogleSignInFailure('google_configuration');
    }
    var stage = 'initialize';
    try {
      await _initialize();
      stage = 'check device support';
      if (!_gateway.supportsAuthenticate) {
        debugPrint(
          'Google Sign-In authenticate UI is unsupported on this platform.',
        );
        throw const GoogleSignInFailure('google_not_supported');
      }
      // Level Up owns session persistence. Start each user-initiated provider
      // login fresh so a previous Google choice cannot silently select the
      // wrong account when a second person signs in on this device.
      stage = 'clear previous Google provider session';
      await _gateway.signOut();
      stage = 'account chooser and ID-token retrieval';
      final idToken = await _gateway.authenticate();
      if (idToken == null || idToken.length < 20) {
        debugPrint('Google Sign-In returned no usable ID token at $stage.');
        throw const GoogleSignInFailure('google_configuration');
      }
      _logIdTokenClaims(idToken);
      return idToken;
    } on GoogleSignInFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      debugPrint(
        'Google Sign-In failed during $stage: '
        'code=${error.code.name}, details=$error',
      );
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          throw const GoogleSignInFailure('google_canceled');
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw const GoogleSignInFailure('google_configuration');
        case GoogleSignInExceptionCode.unknownError:
          final diagnostic = error.toString().toLowerCase();
          if (diagnostic.contains('28444') ||
              diagnostic.contains(
                'developer console is not set up correctly',
              )) {
            throw const GoogleSignInFailure('google_configuration');
          }
          throw const GoogleSignInFailure('google_sign_in_failed');
        default:
          throw const GoogleSignInFailure('google_sign_in_failed');
      }
    } catch (error, stackTrace) {
      debugPrint('Google Sign-In failed during $stage: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const GoogleSignInFailure('google_sign_in_failed');
    }
  }

  void _logIdTokenClaims(String idToken) {
    final claims = GoogleIdTokenClaims.decodeUnverified(idToken);
    if (claims == null) {
      debugPrint(
        '[GoogleSignIn] ID token retrieved, but JWT claims could not be decoded; token omitted.',
      );
      return;
    }
    debugPrint(
      '[GoogleSignIn] decoded ID token claims (unverified): '
      'aud=${claims.audiences.join(',')}; iss=${claims.issuer ?? '<missing>'}; '
      'azp=${claims.authorizedParty ?? '<missing>'}; '
      'exp=${claims.expiresAtEpochSeconds ?? '<missing>'}; '
      'iat=${claims.issuedAtEpochSeconds ?? '<missing>'}.',
    );
  }
}
