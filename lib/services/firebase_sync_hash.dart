import 'dart:convert';

import 'package:crypto/crypto.dart';

Object? _canonical(Object? value) {
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// Stable digest used to make a direct Firestore transaction idempotent.
String firebaseSyncHash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
