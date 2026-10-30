import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/native_cloud_planner_cache.dart';
import 'package:streak/services/planner_cloud_queue.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_repository.dart';
import 'support/app_harness.dart';

class _Vault implements CloudArchiveStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String ownerId) async => values[ownerId];
  @override
  Future<void> write(String ownerId, String json) async {
    values[ownerId] = json;
  }
}

void main() {
  useEmptyStore();
  const channel = MethodChannel('cloud_cache_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Vault vault;
  late NativeCloudPlannerCache cache;
  late PlannerRepository repo;
  late PlannerRefreshBridge bridge;
  Map<String, dynamic>? native;
  var locked = false;
  var canceled = 0;
  setUp(() async {
    native = null;
    locked = false;
    canceled = 0;
    vault = _Vault();
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'acquire':
          expect(locked, false);
          locked = true;
          return {'lease': 'test', 'projection': native};
        case 'publish':
          expect(locked, true);
          native = cloudMap((call.arguments as Map)['projection'] as Map);
        case 'release':
          expect(locked, true);
          locked = false;
        case 'clear':
          native = null;
      }
      return true;
    });
    bridge = PlannerRefreshBridge(channel: channel, enabled: true);
    repo = PlannerRepository(bridge: bridge);
    cache = NativeCloudPlannerCache(
      archives: vault,
      bridge: bridge,
      cancelNotifications: () async {
        canceled++;
      },
      timeZone: () async => 'Europe/Istanbul',
    );
    await repo.initialize();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, dynamic> state() => cloudMap(native!['plannerState'] as Map);
  Future<void> write(Map<String, dynamic> next) =>
      repo.transaction(() => repo.save(next));
  CloudSnapshot remote(Map<String, dynamic>? value, int revision) =>
      CloudSnapshot(
        revision: revision,
        state: value,
        settings: const {'locale': 'en'},
        timeZone: 'Europe/Istanbul',
        serverTime: DateTime.utc(2026, 10, 29, 12),
      );

  test(
    'empty account adopts existing local data and queues until confirmed',
    () async {
      final seed = PlannerController(
        initial: {},
        clock: () => DateTime(2026, 10, 29, 8),
        persist: (_) async {},
        catalog: [],
      );
      await seed.saveItem(
        PlannerItem(id: 'keep', title: 'University', date: seed.now),
      );
      await write(seed.exportState);
      await LocalStore.writeHabit(
        testHabit(id: 'habit', name: 'Private habit'),
      );
      await cache.activate('alice', remote(null, 0));
      var local = await cache.read();
      expect(local.ownerId, 'alice');
      expect(local.pending, hasLength(1));
      expect(local.lastSyncedAt, isNull);
      final mutation = local.pending.single;
      expect(PlannerState.fromMap(mutation.state).items.single.id, 'keep');
      await coldStart();
      await repo.initialize();
      local = await cache.read();
      expect(local.pending.single.mutationId, mutation.mutationId);
      expect(
        await cache.acknowledge(
          'alice',
          mutation.mutationId,
          remote(mutation.state, 1),
        ),
        true,
      );
      expect((await cache.read()).pending, isEmpty);
      expect(LocalStore.readHabits().values.single.name, 'Private habit');
      seed.dispose();
    },
  );

  test(
    'foreground checkpoints remain ordered across pending saves and acknowledgements',
    () async {
      final base = state();
      await cache.activate('alice', remote(base, 4));
      final next = state()
        ..['categories'] = [
          {'id': 'first', 'name': 'Fitness'},
        ];
      await write(next);
      final first = (await cache.read()).pending.single;
      final later = state()
        ..['categories'] = [
          {'id': 'first', 'name': 'Wellness'},
        ];
      await write(later);
      var local = await cache.read();
      expect(local.pending.map((m) => m.baseRevision), [4, 5]);
      expect(first.state['categories'], [
        {'id': 'first', 'name': 'Fitness'},
      ]);
      await cache.acknowledge(
        'alice',
        first.mutationId,
        remote(first.state, 5),
      );
      local = await cache.read();
      expect(local.pending, hasLength(1));
      expect((state()['categories'] as List).single['name'], 'Wellness');
      await cache.acknowledge(
        'alice',
        local.pending.single.mutationId,
        remote(local.pending.single.state, 6),
      );
      expect((await cache.read()).pending, isEmpty);
    },
  );

  test(
    'late worker or locale write is captured before a pull or an acknowledgement',
    () async {
      await cache.activate('alice', remote(state(), 2));
      final first = state()
        ..['categories'] = [
          {'id': 'a', 'name': 'First'},
        ];
      await write(first);
      final head = (await cache.read()).pending.single;
      // Worker owns the native gate and updates canonical state without Hive.
      final worker = state()
        ..['categories'] = [
          {'id': 'a', 'name': 'Worker'},
        ];
      native!['plannerState'] = worker;
      await LocalStore.writeSetting('locale', 'ar');
      await cache.acknowledge('alice', head.mutationId, remote(head.state, 3));
      final local = await cache.read();
      expect(local.pending, hasLength(1));
      expect(local.pending.single.settings['locale'], 'ar');
      expect((state()['categories'] as List).single['name'], 'Worker');
      // Pull cannot overwrite a write that arrived while the HTTP request ran.
      await cache.activate('alice', remote(first, 3));
      expect((state()['categories'] as List).single['name'], 'Worker');
    },
  );

  test(
    'clock-only evaluations do not enqueue and lost response can retry original mutation',
    () async {
      await cache.activate('alice', remote(state(), 0));
      final next = state()
        ..['lastObservedAt'] = DateTime.utc(2026, 10, 29, 12).toIso8601String();
      await write(next);
      expect((await cache.read()).pending, isEmpty);
      next['categories'] = [
        {'id': 'a', 'name': 'Fitness'},
      ];
      await write(next);
      final head = (await cache.read()).pending.single;
      await cache.activate('alice', remote(head.state, 1));
      expect((await cache.read()).errorCode, isNull);
      expect((await cache.read()).pending.single.mutationId, head.mutationId);
      expect(
        await cache.acknowledge('bob', head.mutationId, remote(head.state, 1)),
        false,
      );
      expect(
        await cache.acknowledge(
          'alice',
          head.mutationId,
          remote(head.state, 1),
        ),
        true,
      );
    },
  );

  test(
    'sign out isolates all private tools and restores only same owner pending archive',
    () async {
      await cache.activate('alice', remote(state(), 0));
      await LocalStore.writeHabit(
        testHabit(id: 'secret', name: 'Alice private habit'),
      );
      await LocalStore.writeSetting('profileName', 'Alice');
      final draft = state()
        ..['categories'] = [
          {'id': 'secret', 'name': 'Alice goal'},
        ];
      await write(draft);
      final head = (await cache.read()).pending.single.mutationId;
      await cache.signOut();
      expect(LocalStore.readHabits(), isEmpty);
      expect(LocalStore.setting('profileName', ''), '');
      expect(PlannerState.fromMap(state()).categories, isEmpty);
      await cache.activate('bob', remote(state(), 5));
      expect(LocalStore.readHabits(), isEmpty);
      expect(await cache.exportDraft(), isNot(contains('Alice private habit')));
      await cache.signOut();
      await cache.activate('alice', remote(draft, 1));
      expect(LocalStore.readHabits().values.single.name, 'Alice private habit');
      expect((await cache.read()).pending.single.mutationId, head);
      expect((await cache.read()).errorCode, isNull);
      expect(canceled, greaterThanOrEqualTo(5));
    },
  );

  test(
    'restore-first keeps old guest draft private and rejection never deletes pending writes',
    () async {
      final guest = state()
        ..['categories'] = [
          {'id': 'guest', 'name': 'Original local'},
        ];
      await write(guest);
      final server = PlannerState().toMap()
        ..['categories'] = [
          {'id': 'remote', 'name': 'Cloud'},
        ];
      await cache.activate('alice', remote(server, 8));
      expect((state()['categories'] as List).single['name'], 'Cloud');
      expect(await cache.exportDraft(), contains('Original local'));
      final draft = state()
        ..['categories'] = [
          {'id': 'remote', 'name': 'Local edit'},
        ];
      await write(draft);
      await cache.markConflict('alice', remote(server, 9), 'revision_conflict');
      expect((await cache.read()).pending, hasLength(1));
      expect((state()['categories'] as List).single['name'], 'Local edit');
      await cache.restoreCloud('alice', remote(server, 9));
      expect((await cache.read()).pending, isEmpty);
      final exported = jsonDecode(await cache.exportDraft()) as Map;
      expect(jsonEncode(exported['retained']), contains('Local edit'));
    },
  );

  test(
    'startup guard and interrupted native swap cannot expose a previous owner',
    () async {
      await cache.activate('alice', remote(state(), 0));
      await LocalStore.writeHabit(testHabit(id: 'secret', name: 'Alice'));
      await cache.guardSession(null);
      expect(LocalStore.readHabits(), isEmpty);
      expect((await cache.read()).ownerId, isNull);
      final recovered = PlannerState().toMap()
        ..['categories'] = [
          {'id': 'b', 'name': 'Bob'},
        ];
      native = {
        'schemaVersion': 1,
        'canonicalPlanner': true,
        'plannerState': recovered,
        'settings': {'locale': 'ar'},
        'values': {},
        'cloudSync': CloudCache(
          ownerId: 'bob',
          revision: 2,
          lastQueuedFingerprint: cloudFingerprint(recovered, {'locale': 'ar'}),
        ).toMap(),
        'cloudSwitch': {
          'deviceData': {
            'settings': {'locale': 'ar'},
          },
        },
      };
      await cache.guardSession('bob');
      expect(LocalStore.readHabits(), isEmpty);
      expect(LocalStore.setting('locale', 'en'), 'ar');
      expect(native!.containsKey('cloudSwitch'), false);
      expect(
        LocalStore.settingMap('levelUpState')['categories'],
        recovered['categories'],
      );
    },
  );

  test(
    'server reconciliation with later queued changes keeps draft and stops for recovery',
    () async {
      await cache.activate('alice', remote(state(), 0));
      final first = state()
        ..['categories'] = [
          {'id': 'a', 'name': 'First'},
        ];
      await write(first);
      final head = (await cache.read()).pending.single;
      final later = state()
        ..['categories'] = [
          {'id': 'a', 'name': 'Later'},
        ];
      await write(later);
      final authoritative = cloudMap(first)..['missedSelectionPenalty'] = 10;
      await cache.acknowledge(
        'alice',
        head.mutationId,
        remote(authoritative, 1),
      );
      final local = await cache.read();
      expect(local.pending, hasLength(1));
      expect(local.errorCode, 'server_reconciled');
      expect((state()['categories'] as List).single['name'], 'Later');
    },
  );

  test(
    'synced account retains private tools and first guest archive across repeated sign-in',
    () async {
      final original = state()
        ..['categories'] = [
          {'id': 'local', 'name': 'Before first sign-in'},
        ];
      await write(original);
      final server = PlannerState().toMap()
        ..['categories'] = [
          {'id': 'remote', 'name': 'Cloud first'},
        ];
      await cache.activate('alice', remote(server, 2));
      await LocalStore.writeHabit(
        testHabit(id: 'private', name: 'Saved device tool'),
      );
      await LocalStore.writeSetting('profileName', 'Alice profile');
      await cache.signOut();
      final newer = cloudMap(server)
        ..['categories'] = [
          {'id': 'remote', 'name': 'Cloud newer'},
        ];
      await cache.activate('alice', remote(newer, 3));
      expect((await cache.read()).pending, isEmpty);
      expect(LocalStore.readHabits().values.single.name, 'Saved device tool');
      expect(LocalStore.setting('profileName', ''), 'Alice profile');
      expect((state()['categories'] as List).single['name'], 'Cloud newer');
      expect(await cache.exportDraft(), contains('Before first sign-in'));
    },
  );

  test(
    'queue limit rejects next mutation before either authority is overwritten',
    () async {
      await cache.activate('alice', remote(state(), 0));
      final base = state();
      final cacheMap = CloudCache(
        ownerId: 'alice',
        revision: 0,
        timeZone: 'UTC',
        lastQueuedFingerprint: cloudFingerprint(base, {'locale': 'en'}),
        pending: List.generate(
          256,
          (i) => CloudMutation(
            mutationId: 'pending-$i',
            baseRevision: i,
            state: base,
            settings: {'locale': 'en'},
            timeZone: 'UTC',
          ),
        ),
      ).toMap();
      native!['cloudSync'] = cacheMap;
      await LocalStore.writeSetting(plannerCloudCacheKey, cacheMap);
      final protectedNative = jsonEncode(native),
          protectedHive = jsonEncode(LocalStore.settingMap('levelUpState'));
      final next = cloudMap(base)
        ..['categories'] = [
          {'id': 'new', 'name': 'Must remain unsaved'},
        ];
      await expectLater(write(next), throwsA(isA<StateError>()));
      expect(jsonEncode(native), protectedNative);
      expect(jsonEncode(LocalStore.settingMap('levelUpState')), protectedHive);
      expect(
        (LocalStore.settingMap(plannerCloudCacheKey)['pending'] as List).length,
        256,
      );
    },
  );

  test(
    'Node integer quantities and normalized Dart doubles acknowledge without another upload',
    () async {
      final base = PlannerState().toMap();
      base['items'] = [
        PlannerItem(
          id: 'routine',
          title: 'Read',
          date: DateTime(2026, 10, 29),
        ).toMap(),
      ];
      base['records'] = {
        'routine@2026-10-29': {
          'status': 'pending',
          'completedSteps': [],
          'amount': 0.0,
          'at': null,
        },
      };
      await cache.activate('alice', remote(base, 0));
      final next = state()
        ..['categories'] = [
          {'id': 'a', 'name': 'New category'},
        ];
      await write(next);
      final head = (await cache.read()).pending.single;
      final node = cloudMap(head.state);
      ((node['records'] as Map)['routine@2026-10-29'] as Map)['amount'] = 0;
      expect(
        cloudFingerprint(head.state, head.settings),
        cloudFingerprint(node, head.settings),
      );
      await cache.acknowledge('alice', head.mutationId, remote(node, 1));
      expect((await cache.read()).pending, isEmpty);
      expect(
        ((state()['records'] as Map)['routine@2026-10-29'] as Map)['amount'],
        0.0,
      );
    },
  );
}
