import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/google_id_token_claims.dart';

String _jwt(Map<String, Object?> payload) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'RS256'})}.${encode(payload)}.signature-not-logged';
}

void main() {
  group('GoogleIdTokenClaims.decodeUnverified', () {
    test('reads audience and Google issuer without retaining the token', () {
      const expectedClientId =
          '38989698072-c3s590e64bstmeh7d65vrd4luu0452d6.apps.googleusercontent.com';
      final claims = GoogleIdTokenClaims.decodeUnverified(
        _jwt({
          'aud': expectedClientId,
          'iss': 'https://accounts.google.com',
          'azp': 'android-client.apps.googleusercontent.com',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'sub': 'private-subject-value',
          'email': 'private@example.com',
        }),
      );

      expect(claims, isNotNull);
      expect(claims!.audiences, [expectedClientId]);
      expect(claims.issuer, 'https://accounts.google.com');
      expect(
        claims.authorizedParty,
        'android-client.apps.googleusercontent.com',
      );
      expect(claims.expiresAtEpochSeconds, isNotNull);
      expect(claims.issuedAtEpochSeconds, isNotNull);
      expect(claims.isExpired, isFalse);
      expect(claims.issuedInFuture, isFalse);
      expect(claims.audienceMatches(expectedClientId), isTrue);
      expect(claims.hasGoogleIssuer, isTrue);
      expect(claims.toString(), isNot(contains('private@example.com')));
      expect(claims.toString(), isNot(contains('private-subject-value')));
    });

    test('supports multiple audiences and detects mismatch', () {
      final claims = GoogleIdTokenClaims.decodeUnverified(
        _jwt({
          'aud': [
            'client-a.apps.googleusercontent.com',
            'client-b.apps.googleusercontent.com',
          ],
          'iss': 'accounts.google.com',
        }),
      );

      expect(
        claims!.audienceMatches('client-b.apps.googleusercontent.com'),
        isTrue,
      );
      expect(
        claims.audienceMatches('other.apps.googleusercontent.com'),
        isFalse,
      );
      expect(claims.hasGoogleIssuer, isTrue);
    });

    test('malformed or non-JWT values return no claims', () {
      expect(GoogleIdTokenClaims.decodeUnverified('not-a-jwt'), isNull);
      expect(GoogleIdTokenClaims.decodeUnverified('a.!.c'), isNull);
      expect(
        GoogleIdTokenClaims.decodeUnverified(
          _jwt({'sub': 'no-aud-or-iss'}),
        )?.audiences,
        isEmpty,
      );
    });

    test(
      'identifies an expired token using exp without signature validation',
      () {
        final claims = GoogleIdTokenClaims.decodeUnverified(
          _jwt({'exp': 1, 'iat': 1}),
        );

        expect(claims!.expiresAtEpochSeconds, 1);
        expect(claims.issuedAtEpochSeconds, 1);
        expect(claims.isExpired, isTrue);
        expect(claims.issuedInFuture, isFalse);
      },
    );
  });
}
