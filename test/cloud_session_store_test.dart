import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/cloud_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'secure session round trip keeps account owner and complete rotated token pair',
    () async {
      final store = CloudSecureSessionStore();
      final session = CloudSession(
        user: const CloudUser(id: 'a', email: 'a@example.com'),
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2026, 10, 29),
      );
      expect(await store.read(), isNull);
      await store.write(session);
      expect((await store.read())!.toMap(), session.toMap());
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
  test(
    'private archive keys isolate owners and session clearing does not discard drafts',
    () async {
      final archive = CloudSecureArchiveStore();
      await archive.write('owner:a', '{"private":"a"}');
      await archive.write('owner/b', '{"private":"b"}');
      await CloudSecureSessionStore().clear();
      expect(await archive.read('owner:a'), '{"private":"a"}');
      expect(await archive.read('owner/b'), '{"private":"b"}');
      expect(await archive.read('unknown'), isNull);
    },
  );
}
