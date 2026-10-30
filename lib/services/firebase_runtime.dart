import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:streak/firebase_options.dart';

/// The app must remain fully usable without Firebase configuration. This
/// boundary makes configuration failure explicit and keeps the existing cloud
/// transport available during a staged migration.
class FirebaseRuntime {
  const FirebaseRuntime._({required this.ready, this.errorCode});

  final bool ready;
  final String? errorCode;

  static Future<FirebaseRuntime> initialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options == null) {
      return const FirebaseRuntime._(ready: false, errorCode: 'unconfigured');
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      await _activateAppCheck();
      return const FirebaseRuntime._(ready: true);
    } on FirebaseException catch (error) {
      // Firebase errors can include project-specific data. Keep logs useful
      // without exposing configuration or credentials.
      debugPrint('Firebase initialization failed: ${error.code}');
      return FirebaseRuntime._(ready: false, errorCode: error.code);
    } catch (_) {
      return const FirebaseRuntime._(
        ready: false,
        errorCode: 'initialization_failed',
      );
    }
  }

  static Future<void> _activateAppCheck() async {
    if (!Platform.isAndroid) return;
    const useDebugProvider = bool.fromEnvironment(
      'LEVEL_UP_FIREBASE_DEBUG_APP_CHECK',
    );
    if (useDebugProvider && kReleaseMode) {
      throw StateError('Debug App Check cannot be enabled in release builds.');
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugProvider
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } on FirebaseException catch (error) {
      // Authentication may still work while App Check is being enrolled. The
      // protected callable rejects sync until attestation is configured.
      debugPrint('Firebase App Check unavailable: ${error.code}');
    }
  }
}
