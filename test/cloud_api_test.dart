import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';

void main() {
  test(
    'empty API configuration is explicit and plaintext URLs are rejected',
    () async {
      final api = CloudHttpApi(baseUrl: '');
      expect(api.configured, false);
      await expectLater(
        api.getState('token'),
        throwsA(
          isA<CloudApiException>().having(
            (e) => e.code,
            'code',
            'unconfigured',
          ),
        ),
      );
      api.close();
      for (final url in [
        'http://example.com',
        'https://user:secret@example.com',
        'https://example.com?secret=x',
      ]) {
        expect(
          () => CloudHttpApi(baseUrl: url, allowInsecure: false),
          throwsA(isA<CloudApiException>()),
        );
      }
    },
  );

  test(
    'HTTP client sends fixed auth and state contract without leaking tokens into body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final content = await utf8.decoder.bind(request).join();
        final body = content.isEmpty ? null : jsonDecode(content);
        requests.add({
          'path': request.uri.path,
          'method': request.method,
          'authorization': request.headers.value('authorization'),
          'body': body,
        });
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/login')) {
          request.response.write(
            jsonEncode({
              'user': {'id': 'owner', 'email': 'a@example.com'},
              'accessToken': 'access',
              'refreshToken': 'refresh',
              'expiresIn': 900,
            }),
          );
        } else if (request.uri.path.endsWith('/logout')) {
          request.response.statusCode = 204;
        } else {
          request.response.write(
            jsonEncode({
              'revision': 1,
              'state': {'items': []},
              'settings': {'locale': 'ar'},
              'serverTime': '2026-10-29T12:00:00.000Z',
              'timeZone': 'Europe/Istanbul',
            }),
          );
        }
        await request.response.close();
      });
      final api = CloudHttpApi(
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowInsecure: true,
        clock: () => DateTime.utc(2026, 10, 29, 12),
      );
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      final session = await api.login(' a@example.com ', 'password');
      expect(session.expiresAt, DateTime.utc(2026, 10, 29, 12, 15));
      final snapshot = await api.getState(session.accessToken);
      expect(snapshot.state, {'items': []});
      expect(snapshot.timeZone, 'Europe/Istanbul');
      final mutation = CloudMutation(
        mutationId: 'stable-id',
        baseRevision: 0,
        state: {'items': []},
        settings: {'locale': 'ar'},
        timeZone: 'Europe/Istanbul',
      );
      await api.sync(session.accessToken, mutation);
      await api.logout(session.refreshToken);
      expect(requests.map((v) => v['path']), [
        '/api/v1/auth/login',
        '/api/v1/state',
        '/api/v1/sync',
        '/api/v1/auth/logout',
      ]);
      expect(requests[0]['body'], {
        'email': 'a@example.com',
        'password': 'password',
      });
      expect(requests[1]['authorization'], 'Bearer access');
      expect(requests[2]['body'], mutation.toMap());
      expect((requests[2]['body'] as Map).keys, isNot(contains('accessToken')));
      expect(requests.last['body'], {'refreshToken': 'refresh'});
    },
  );

  test(
    '409 retains structured remote snapshot while safe exception omits response secrets',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 409;
        request.response.write(
          jsonEncode({
            'error': {
              'code': 'revision_conflict',
              'message': 'secret must not be shown',
            },
            'revision': 8,
            'state': {'remote': true},
            'settings': {},
          }),
        );
        await request.response.close();
      });
      final api = CloudHttpApi(
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowInsecure: true,
      );
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      await expectLater(
        api.getState('access-secret'),
        throwsA(
          isA<CloudApiException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.snapshot!.revision, 'revision', 8)
              .having(
                (e) => e.toString(),
                'safe error',
                'CloudApiException(revision_conflict)',
              ),
        ),
      );
    },
  );

  test(
    'request timeout and malformed responses keep errors explicit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var malformed = false;
      server.listen((request) async {
        if (!malformed) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        request.response.write('not-json');
        await request.response.close();
      });
      final short = CloudHttpApi(
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowInsecure: true,
        timeout: const Duration(milliseconds: 10),
      );
      final normal = CloudHttpApi(
        baseUrl: 'http://127.0.0.1:${server.port}',
        allowInsecure: true,
      );
      addTearDown(() async {
        short.close();
        normal.close();
        await server.close(force: true);
      });
      await expectLater(
        short.getState('token'),
        throwsA(
          isA<CloudApiException>().having(
            (e) => e.code,
            'code',
            'network_error',
          ),
        ),
      );
      malformed = true;
      await expectLater(
        normal.getState('token'),
        throwsA(
          isA<CloudApiException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    },
  );
}
