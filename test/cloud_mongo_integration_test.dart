import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_session_store.dart';
import 'package:streak/services/cloud_sync_controller.dart';
import 'package:streak/services/native_cloud_planner_cache.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_repository.dart';

import 'support/app_harness.dart';

/// Opt in against backend/scripts/local-test-server.js, a real temporary Mongo
/// replica set. This test never connects to the emulator or a user's data dir.
class _Sessions implements CloudSessionStore {
  CloudSession? value;
  @override
  Future<CloudSession?> read() async => value;
  @override
  Future<void> write(CloudSession session) async => value = session;
  @override
  Future<void> clear() async => value = null;
}

class _Archives implements CloudArchiveStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String ownerId) async => values[ownerId];
  @override
  Future<void> write(String ownerId, String json) async =>
      values[ownerId] = json;
}

List<String> _differencePaths(Object? a, Object? b, [String path = '']) {
  if (a is Map && b is Map) {
    return [
      for (final key in {...a.keys, ...b.keys})
        ..._differencePaths(a[key], b[key], '$path/$key'),
    ];
  }
  if (a is List && b is List && a.length == b.length) {
    return [
      for (var i = 0; i < a.length; i++)
        ..._differencePaths(a[i], b[i], '$path/$i'),
    ];
  }
  return jsonEncode(a) == jsonEncode(b)
      ? []
      : ['$path (${a.runtimeType}/${b.runtimeType})'];
}

void main() {
  useEmptyStore();
  final url = Platform.environment['LEVEL_UP_TEST_API_URL'];
  const channel = MethodChannel('levelup_mongo_integration');

  test(
    'real API and Mongo restore planner after offline restart, signout and fresh local storage',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<String, dynamic>? native;
      var locked = false;
      var cancellations = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'acquire':
            expect(locked, false);
            locked = true;
            return {'lease': 'mongo-test', 'projection': native};
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
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final bridge = PlannerRefreshBridge(channel: channel, enabled: true);
      final archives = _Archives();
      final sessions = _Sessions();
      NativeCloudPlannerCache newCache() => NativeCloudPlannerCache(
        archives: archives,
        bridge: bridge,
        timeZone: () async => 'Europe/Istanbul',
        cancelNotifications: () async {
          cancellations++;
        },
      );
      final repo = PlannerRepository(bridge: bridge);
      await repo.initialize();
      PlannerController newPlanner() => PlannerController(
        loadLatest: repo.loadLatest,
        transaction: repo.transaction,
        persist: repo.save,
        catalog: [],
      );
      var planner = newPlanner();
      await LocalStore.writeSetting('locale', 'ar');
      await LocalStore.writeSetting('profileName', 'Private account name');
      await LocalStore.writeHabit(
        testHabit(id: 'private-tool', name: 'Private local habit'),
      );
      final day = plannerDay(planner.now);
      await planner.saveItem(
        PlannerItem(
          id: 'routine',
          title: 'University الجامعة',
          date: day,
          recurrence: PlannerRecurrence.weekdays,
          weekdays: const [1, 2, 3, 4],
          startMinute: 540,
          endMinute: 720,
        ),
      );
      final category = await planner.saveCategory(name: 'My fitness');
      final template = ChallengeTemplate(
        id: 'nested-package',
        name: 'Original package',
        categoryId: category.id,
        rewardMode: ChallengeRewardMode.packageOnly,
        completionXp: 15,
        failurePenalty: 5,
        skipPenalty: 2,
        tasks: const [
          ChallengeTaskDefinition(
            id: 'group',
            title: 'Exercise',
            type: ChallengeTaskType.group,
          ),
          ChallengeTaskDefinition(
            id: 'first',
            title: 'First child',
            parentId: 'group',
          ),
          ChallengeTaskDefinition(
            id: 'deeper',
            title: 'Deeper group',
            type: ChallengeTaskType.group,
            parentId: 'group',
          ),
          ChallengeTaskDefinition(
            id: 'last',
            title: 'Last child',
            parentId: 'deeper',
          ),
        ],
      );
      await planner.saveTemplate(template);
      final completed = await planner.startChallenge(template);
      final date = plannerDateKey(day);
      await planner.complete('${completed.id}/first@$date');
      await planner.complete('${completed.id}/last@$date');
      final active = await planner.startChallenge(template);
      await planner.saveTemplate(
        template.copyWith(name: 'Edited reusable package'),
      );
      expect(planner.balance, 15);
      expect(planner.instances.last.snapshot.name, 'Original package');
      final originalSnapshot = jsonEncode(active.snapshot.toMap());

      final clients = <CloudHttpApi>[];
      CloudHttpApi api([String? base]) {
        final client = CloudHttpApi(
          baseUrl: base ?? url,
          allowInsecure: true,
          timeout: const Duration(seconds: 10),
        );
        clients.add(client);
        return client;
      }

      addTearDown(() {
        for (final client in clients) {
          client.close();
        }
      });
      var cache = newCache();
      var cloud = CloudSyncController(
        api: api(),
        cache: cache,
        sessionStore: sessions,
        onApplied: planner.reload,
      );
      final email =
          'flutter-${DateTime.now().microsecondsSinceEpoch}@example.com';
      const password = 'Test-only-password-123!';
      await cloud.initialize(sync: false);
      await cloud.signIn(email, password, register: true);
      expect(
        cloud.status,
        CloudSyncStatus.synced,
        reason:
            'Initial import failed: ${cloud.errorCode}; revision=${cloud.local.revision}; differences=${cloud.local.pending.isEmpty ? [] : _differencePaths(cloud.local.acknowledgedState, cloud.local.pending.last.state)}',
      );
      final owner = cloud.user!.id;
      final firstRemote = await cloud.api.getState(cloud.session!.accessToken);
      expect(firstRemote.revision, greaterThanOrEqualTo(1));
      final firstState = PlannerState.fromMap(firstRemote.state!);
      expect(firstState.balance, 15);
      expect(firstState.ledger, hasLength(1));
      expect(firstState.instances.last.snapshot.name, 'Original package');
      expect(firstRemote.settings['locale'], 'ar');
      expect((await cache.read()).pending, isEmpty);

      // Two domain writes while offline produce ordered immutable checkpoints.
      cloud.dispose();
      await planner.saveItem(
        PlannerItem(
          id: 'offline-routine',
          title: 'Offline reading',
          date: day,
          recurrence: PlannerRecurrence.daily,
        ),
      );
      await planner.saveCategory(id: category.id, name: 'Movement');
      final pendingBeforeRestart = (await cache.read()).pending
          .map((v) => v.mutationId)
          .toList();
      expect(pendingBeforeRestart, hasLength(2));
      planner.dispose();
      await coldStart();
      await repo.initialize();
      planner = newPlanner();
      cache = newCache();
      cloud = CloudSyncController(
        api: api('http://127.0.0.1:1'),
        cache: cache,
        sessionStore: sessions,
        onApplied: planner.reload,
      );
      await cloud.initialize(sync: false);
      await cloud.synchronize();
      expect(cloud.status, CloudSyncStatus.offline);
      expect(
        (await cache.read()).pending.map((v) => v.mutationId),
        pendingBeforeRestart,
      );
      expect(planner.items.map((v) => v.id), contains('offline-routine'));
      cloud.dispose();
      cloud = CloudSyncController(
        api: api(),
        cache: cache,
        sessionStore: sessions,
        onApplied: planner.reload,
      );
      await cloud.initialize(sync: false);
      await cloud.synchronize();
      expect(
        cloud.status,
        CloudSyncStatus.synced,
        reason: 'Replay failed: ${cloud.errorCode}',
      );
      expect((await cache.read()).pending, isEmpty);
      expect(planner.balance, 15);
      expect(planner.categories.single.name, 'Movement');
      expect(
        jsonEncode(planner.instances.last.snapshot.toMap()),
        originalSnapshot,
      );

      // Sign-out removes every active private cache without deleting cloud data.
      await cloud.signOut();
      expect(cloud.user, isNull);
      expect((await cache.read()).ownerId, isNull);
      expect(
        PlannerState.fromMap(LocalStore.settingMap('levelUpState')).items,
        isEmpty,
      );
      expect(LocalStore.readHabits(), isEmpty);
      expect(LocalStore.setting('profileName', ''), isEmpty);
      expect(archives.values, contains(owner));
      expect(cancellations, greaterThanOrEqualTo(2));
      cloud.dispose();
      planner.dispose();

      // This is temporary Hive only: simulate clear-app-data and an empty vault.
      await LocalStore.wipeEverything();
      native = null;
      archives.values.clear();
      await sessions.clear();
      await coldStart();
      await repo.initialize();
      planner = newPlanner();
      cache = newCache();
      cloud = CloudSyncController(
        api: api(),
        cache: cache,
        sessionStore: sessions,
        onApplied: planner.reload,
      );
      await cloud.initialize(sync: false);
      expect(planner.items, isEmpty);
      await cloud.signIn(email, password);
      expect(
        cloud.status,
        CloudSyncStatus.synced,
        reason: 'Fresh install restore failed: ${cloud.errorCode}',
      );
      expect(cloud.user!.id, owner);
      expect(
        planner.items.map((v) => v.id),
        containsAll(['routine', 'offline-routine']),
      );
      expect(planner.items.firstWhere((v) => v.id == 'routine').weekdays, [
        1,
        2,
        3,
        4,
      ]);
      expect(planner.categories.single.name, 'Movement');
      expect(planner.templates.single.name, 'Edited reusable package');
      expect(planner.templates.single.childrenOf('group').map((v) => v.id), [
        'first',
        'deeper',
      ]);
      expect(planner.templates.single.childrenOf('deeper').single.id, 'last');
      expect(planner.instances, hasLength(2));
      expect(planner.instances.first.status, ChallengeStatus.completed);
      expect(planner.instances.last.status, ChallengeStatus.active);
      expect(
        jsonEncode(planner.instances.last.snapshot.toMap()),
        originalSnapshot,
      );
      expect(
        planner.occurrenceById('${completed.id}/first@$date')!.record.status,
        CompletionStatus.completed,
      );
      expect(planner.balance, 15);
      expect(planner.ledger, hasLength(1));
      expect(LocalStore.setting('locale', 'en'), 'ar');
      expect((await cache.read()).pending, isEmpty);
      expect(locked, false);
      cloud.dispose();
      planner.dispose();
    },
    skip: url == null || url.isEmpty
        ? 'Set LEVEL_UP_TEST_API_URL to the local real-Mongo fixture.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
