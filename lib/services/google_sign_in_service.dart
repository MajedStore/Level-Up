// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'package:google_sign_in/google_sign_in.dart';

/// Keeps provider-specific failures out of the account UI and never exposes
/// Google tokens beyond the immediate HTTPS exchange with the Level Up API.
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
      serverClientId: serverClientId,
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
    : _serverClientId =
          (serverClientId ??
                  const String.fromEnvironment(
                    'LEVEL_UP_GOOGLE_SERVER_CLIENT_ID',
                  ))
              .trim(),
      _gateway = gateway ?? _OfficialGoogleSignInGateway.instance;

  final String _serverClientId;
  final GoogleSignInGateway _gateway;
  Future<void>? _initialization;
  Future<String>? _inFlight;

  @override
  bool get configured => _serverClientId.isNotEmpty;

  Future<void> _initialize() =>
      _initialization ??= _gateway.initialize(_serverClientId);

  @override
  Future<String> authenticate() {
    final current = _inFlight;
    if (current != null) return current;
    return _inFlight = _authenticate().whenComplete(() => _inFlight = null);
  }

  Future<String> _authenticate() async {
    if (!configured) throw const GoogleSignInFailure('google_not_configured');
    if (!RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9._-]*\.apps\.googleusercontent\.com$',
    ).hasMatch(_serverClientId)) {
      throw const GoogleSignInFailure('google_configuration');
    }
    try {
      await _initialize();
      if (!_gateway.supportsAuthenticate) {
        throw const GoogleSignInFailure('google_not_supported');
      }
      // Level Up owns session persistence. Start each user-initiated provider
      // login fresh so a previous Google choice cannot silently select the
      // wrong account when a second person signs in on this device.
      await _gateway.signOut();
      final idToken = await _gateway.authenticate();
      if (idToken == null || idToken.length < 20) {
        throw const GoogleSignInFailure('google_configuration');
      }
      return idToken;
    } on GoogleSignInFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          throw const GoogleSignInFailure('google_canceled');
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw const GoogleSignInFailure('google_configuration');
        default:
          throw const GoogleSignInFailure('google_sign_in_failed');
      }
    } catch (_) {
      throw const GoogleSignInFailure('google_sign_in_failed');
    }
  }
}
