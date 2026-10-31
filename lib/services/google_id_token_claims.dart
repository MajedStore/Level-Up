import 'dart:convert';

/// Safely decodes only the public payload claims needed for diagnostics.
///
/// This does not validate the JWT signature. Firebase Authentication performs
/// the authoritative token verification during credential exchange.
class GoogleIdTokenClaims {
  const GoogleIdTokenClaims({
    required this.audiences,
    required this.issuer,
    required this.authorizedParty,
    required this.expiresAtEpochSeconds,
    required this.issuedAtEpochSeconds,
  });

  final List<String> audiences;
  final String? issuer;
  final String? authorizedParty;
  final int? expiresAtEpochSeconds;
  final int? issuedAtEpochSeconds;

  static GoogleIdTokenClaims? decodeUnverified(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3 || parts[1].isEmpty) {
      return null;
    }

    try {
      final normalizedPayload = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(normalizedPayload)),
      );
      if (decoded is! Map<String, dynamic>) return null;

      final rawAudience = decoded['aud'];
      final audiences = switch (rawAudience) {
        final String value => [value],
        final List<dynamic> values => values.whereType<String>().toList(),
        _ => const <String>[],
      };
      final rawIssuer = decoded['iss'];
      final rawAuthorizedParty = decoded['azp'];

      return GoogleIdTokenClaims(
        audiences: List.unmodifiable(audiences),
        issuer: rawIssuer is String ? rawIssuer : null,
        authorizedParty: rawAuthorizedParty is String
            ? rawAuthorizedParty
            : null,
        expiresAtEpochSeconds: _epochSeconds(decoded['exp']),
        issuedAtEpochSeconds: _epochSeconds(decoded['iat']),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static int? _epochSeconds(Object? value) => switch (value) {
    final int seconds => seconds,
    final num seconds when seconds.isFinite => seconds.toInt(),
    _ => null,
  };

  bool? get isExpired {
    final expiry = expiresAtEpochSeconds;
    return expiry == null
        ? null
        : expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  bool? get issuedInFuture {
    final issuedAt = issuedAtEpochSeconds;
    return issuedAt == null
        ? null
        : issuedAt > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
  }

  bool audienceMatches(String expectedClientId) =>
      expectedClientId.isNotEmpty && audiences.contains(expectedClientId);

  bool get hasGoogleIssuer =>
      issuer == 'accounts.google.com' ||
      issuer == 'https://accounts.google.com';
}
