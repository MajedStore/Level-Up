// Firebase options bootstrap.
//
// This intentionally contains no project identifiers. Until `flutterfire
// configure` replaces it with the generated file, Firebase stays disabled and
// Level Up continues using its existing cloud adapter. The temporary
// dart-defines are useful for an isolated development build only; do not put
// private credentials in them.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    const apiKey = String.fromEnvironment('LEVEL_UP_FIREBASE_API_KEY');
    const appId = String.fromEnvironment('LEVEL_UP_FIREBASE_APP_ID');
    const messagingSenderId = String.fromEnvironment(
      'LEVEL_UP_FIREBASE_MESSAGING_SENDER_ID',
    );
    const projectId = String.fromEnvironment('LEVEL_UP_FIREBASE_PROJECT_ID');
    const authDomain = String.fromEnvironment('LEVEL_UP_FIREBASE_AUTH_DOMAIN');
    const storageBucket = String.fromEnvironment(
      'LEVEL_UP_FIREBASE_STORAGE_BUCKET',
    );
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}
