import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:streak/firebase_options.dart';

/// The app remains usable without Firebase configuration as a local-only app.
/// This boundary makes a missing project explicit and prevents an accidental
/// fallback to the retired HTTP cloud transport.
class FirebaseRuntime {
  const FirebaseRuntime._({required this.ready, this.errorCode});

  final bool ready;
  final String? errorCode;

  static Future<FirebaseRuntime> initialize() async {
    late final FirebaseOptions options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
    } on UnsupportedError {
      // FlutterFire's generated getter is non-nullable. It signals a platform
      // without generated options by throwing instead of returning null.
      return const FirebaseRuntime._(ready: false, errorCode: 'unconfigured');
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      await _activateAppCheck();
      return const FirebaseRuntime._(ready: true);
    } on FirebaseException catch (error, stackTrace) {
      // Firebase errors can include project-specific data. Keep logs useful
      // without exposing configuration or credentials.
      debugPrint(
        'Firebase initialization failed: plugin=${error.plugin} '
        'code=${error.code} message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return FirebaseRuntime._(ready: false, errorCode: error.code);
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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
    } on FirebaseException catch (error, stackTrace) {
      // Authentication and local use can continue. Firestore enforcement may
      // reject cloud requests until App Check is configured for this app.
      debugPrint(
        'Firebase App Check unavailable: plugin=${error.plugin} '
        'code=${error.code} message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
