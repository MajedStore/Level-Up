import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/firebase_cloud_api.dart';

void main() {
  group('mapFirebaseAuthErrorCode', () {
    test('maps a rejected Google credential to a provider-specific error', () {
      expect(
        mapFirebaseAuthErrorCode(
          'invalid-credential',
          operation: 'Google credential exchange',
        ),
        'google_credential_rejected',
      );
    });

    test(
      'keeps rejected email/password credentials as invalid credentials',
      () {
        expect(
          mapFirebaseAuthErrorCode(
            'invalid-credential',
            operation: 'email/password sign-in',
          ),
          'invalid_credentials',
        );
      },
    );
  });
}
