import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:streak/services/google_sign_in_service.dart';

class _GoogleGateway implements GoogleSignInGateway {
  final events = <String>[];
  String? clientId;
  String? token = 'google-id-token-returned-by-provider';
  Object? error;
  Completer<void>? hold;
  @override
  bool supportsAuthenticate = true;

  @override
  Future<void> initialize(String serverClientId) async {
    events.add('initialize');
    clientId = serverClientId;
  }

  @override
  Future<void> signOut() async => events.add('sign-out');

  @override
  Future<String?> authenticate() async {
    events.add('authenticate');
    await hold?.future;
    if (error != null) throw error!;
    return token;
  }
}

Matcher _failure(String code) => isA<GoogleSignInFailure>().having(
  (error) => error.code,
  'safe failure code',
  code,
);

void main() {
  const clientId = '123-valid-web.apps.googleusercontent.com';

  test('missing or malformed Web client ID fails before provider UI', () async {
    for (final value in ['', 'not-a-web-client']) {
      final gateway = _GoogleGateway();
      final service = GoogleSignInService(
        serverClientId: value,
        gateway: gateway,
      );
      await expectLater(
        service.authenticate(),
        throwsA(
          _failure(
            value.isEmpty ? 'google_not_configured' : 'google_configuration',
          ),
        ),
      );
      expect(gateway.events, isEmpty);
    }
  });

  test(
    'one initialization, fresh provider choice for every explicit sign-in',
    () async {
      final gateway = _GoogleGateway();
      final service = GoogleSignInService(
        serverClientId: clientId,
        gateway: gateway,
      );
      expect(await service.authenticate(), gateway.token);
      expect(await service.authenticate(), gateway.token);
      expect(gateway.clientId, clientId);
      expect(gateway.events, [
        'initialize',
        'sign-out',
        'authenticate',
        'sign-out',
        'authenticate',
      ]);
    },
  );

  test('concurrent taps share one native provider request', () async {
    final gateway = _GoogleGateway()..hold = Completer<void>();
    final service = GoogleSignInService(
      serverClientId: clientId,
      gateway: gateway,
    );
    final first = service.authenticate();
    final second = service.authenticate();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.events.where((e) => e == 'authenticate'), hasLength(1));
    gateway.hold!.complete();
    expect(await first, gateway.token);
    expect(await second, gateway.token);
  });

  test('provider cancellation is safe and a later retry can proceed', () async {
    final gateway = _GoogleGateway()
      ..error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'provider implementation detail that must not reach UI',
      );
    final service = GoogleSignInService(
      serverClientId: clientId,
      gateway: gateway,
    );
    await expectLater(
      service.authenticate(),
      throwsA(_failure('google_canceled')),
    );
    gateway.error = null;
    expect(await service.authenticate(), gateway.token);
  });

  test(
    'provider/client configuration and missing ID token are rejected',
    () async {
      for (final code in [
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
      ]) {
        final gateway = _GoogleGateway()
          ..error = GoogleSignInException(code: code);
        final service = GoogleSignInService(
          serverClientId: clientId,
          gateway: gateway,
        );
        await expectLater(
          service.authenticate(),
          throwsA(_failure('google_configuration')),
        );
      }
      final gateway = _GoogleGateway()..token = null;
      final service = GoogleSignInService(
        serverClientId: clientId,
        gateway: gateway,
      );
      await expectLater(
        service.authenticate(),
        throwsA(_failure('google_configuration')),
      );
    },
  );

  test('unsupported provider UI produces a specific safe failure', () async {
    final gateway = _GoogleGateway()..supportsAuthenticate = false;
    final service = GoogleSignInService(
      serverClientId: clientId,
      gateway: gateway,
    );
    await expectLater(
      service.authenticate(),
      throwsA(_failure('google_not_supported')),
    );
    expect(gateway.events, ['initialize']);
  });
}
