import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/planner_background.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_reminder_schedule.dart';
import 'package:streak/services/planner_repository.dart';

import 'support/app_harness.dart';

const channel = MethodChannel('levelup_repository_test');

void main() {
  useEmptyStore();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, dynamic>? native;
  var held = false;
  var token = 0;
  var publishes = 0;
  setUp(() {
    native = null;
    held = false;
    publishes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'acquire':
          expect(held, false);
          held = true;
          return {'lease': '${++token}', 'projection': native};
        case 'publish':
          expect(held, true);
          publishes++;
          native = detachedPlannerMap(args!['projection'] as Map);
          return true;
        case 'release':
          expect(held, true);
          held = false;
          return true;
        case 'readBackground':
          return native;
        case 'checkpointBackground':
          native = detachedPlannerMap({
            ...native!,
            'plannerState': args!['plannerState'],
            'values': args['values'],
          });
          return true;
        case 'completeBackground':
          native = detachedPlannerMap({
            ...native!,
            if (args!['plannerState'] is Map)
              'plannerState': args['plannerState'],
            'values': args['values'],
          });
          return true;
      }
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  PlannerRepository repository() => PlannerRepository(
    bridge: PlannerRefreshBridge(channel: channel, enabled: true),
  );

  test(
    'migration ignores a stale notification mirror and recovers Hive from canonical state',
    () async {
      final legacy = PlannerController(
        initial: {},
        persist: (_) async {},
        clock: () => DateTime(2026, 10, 29, 8),
      );
      await legacy.saveItem(
        PlannerItem(
          id: 'keep',
          title: 'University',
          date: DateTime(2026, 10, 29),
        ),
      );
      await LocalStore.writeSetting('levelUpState', legacy.exportState);
      native = {'schemaVersion': 1, 'plannerState': {}, 'values': {}};
      final repo = repository();
      await repo.initialize();
      expect(native!['canonicalPlanner'], true);
      expect(
        PlannerState.fromMap(
          native!['plannerState'] as Map<String, dynamic>,
        ).items.single.id,
        'keep',
      );
      final authoritative = jsonEncode(native!['plannerState']);
      await LocalStore.writeSetting('levelUpState', {});
      await repo.initialize();
      expect(jsonEncode(LocalStore.settingMap('levelUpState')), authoritative);
      legacy.dispose();
    },
  );

  test(
    'startup commits schema migration once and preserves legacy active rules and ledger',
    () async {
      final now = DateTime(2026, 10, 29, 8);
      final seed = PlannerController(
        initial: {},
        persist: (_) async {},
        clock: () => now,
        catalog: [],
      );
      const template = ChallengeTemplate(
        id: 'legacy-template',
        name: 'Original package',
        description: '',
        difficulty: ChallengeDifficulty.hard,
        durationDays: 1,
        completionXp: 40,
        tasks: [
          ChallengeTaskDefinition(
            id: 'a',
            title: 'First',
            dayOffsets: [0],
            rewardXp: 10,
            skipPenalty: 3,
          ),
          ChallengeTaskDefinition(
            id: 'b',
            title: 'Second',
            dayOffsets: [0],
            rewardXp: 10,
            skipPenalty: 4,
          ),
        ],
      );
      await seed.saveItem(
        PlannerItem(id: 'university', title: 'University', date: now),
      );
      final instance = await seed.startChallenge(template);
      await seed.complete('${instance.id}/a@2026-10-29');
      final old = seed.exportState;
      old['schemaVersion'] = 2;
      old.remove('categories');
      Map<String, dynamic> v2(ChallengeTemplate t) {
        final map = t.toMap()
          ..remove('rewardMode')
          ..remove('categoryId')
          ..remove('categoryName');
        for (final task in map['tasks'] as List) {
          (task as Map).remove('type');
          task.remove('parentId');
        }
        return map;
      }

      old['templates'] = [v2(template)];
      ((old['instances'] as List).single as Map)['snapshot'] = v2(template);
      final ledger = jsonEncode(old['ledger']);
      final routines = jsonEncode(old['items']);
      native = {
        'schemaVersion': 1,
        'canonicalPlanner': true,
        'plannerState': old,
        'values': {},
      };
      final repo = repository();
      await repo.initialize();
      final migrated = PlannerState.fromMap(PlannerRepository.stateIn(native)!);
      expect(
        (native!['plannerState'] as Map)['schemaVersion'],
        PlannerState.schemaVersion,
      );
      expect(
        migrated.templates.single.rewardMode,
        ChallengeRewardMode.packageOnly,
      );
      expect(migrated.templates.single.completionXp, 60);
      expect(
        migrated.instances.single.snapshot.rewardMode,
        ChallengeRewardMode.legacyPerTask,
      );
      expect(migrated.instances.single.snapshot.completionXp, 40);
      expect(migrated.instances.single.snapshot.tasks.last.skipPenalty, 4);
      expect(jsonEncode(migrated.toMap()['ledger']), ledger);
      expect(jsonEncode(migrated.toMap()['items']), routines);
      expect(migrated.balance, 10);
      final firstPublishes = publishes;
      // Android JSON maps are not required to preserve Dart's key order.
      native!['plannerState'] = Map.fromEntries(
        (native!['plannerState'] as Map<String, dynamic>).entries
            .toList()
            .reversed,
      );
      await repo.initialize();
      expect(publishes, firstPublishes);
      expect(
        LocalStore.settingMap('levelUpState')['schemaVersion'],
        PlannerState.schemaVersion,
      );
      // Explicit old-backup restores also migrate in the same atomic save,
      // without waiting for another launch or domain command.
      await repo.transaction(() => repo.save(old));
      expect(
        (native!['plannerState'] as Map)['schemaVersion'],
        PlannerState.schemaVersion,
      );
      expect(
        LocalStore.settingMap('levelUpState')['schemaVersion'],
        PlannerState.schemaVersion,
      );
      seed.dispose();
    },
  );

  test(
    'two foreground controllers reload inside the lease without losing either edit',
    () async {
      await repository().initialize();
      PlannerController make() {
        final repo = repository();
        return PlannerController(
          initial: {},
          clock: () => DateTime(2026, 10, 29, 8),
          transaction: repo.transaction,
          loadLatest: repo.loadLatest,
          persist: repo.save,
          afterCommit: () async {
            // It must be possible to acquire a fresh lease for reminder sync.
            // Another queued controller may already hold the gate at this point.
            await repo.transaction(() async {
              expect(held, true);
            });
          },
        );
      }

      final a = make();
      final b = make();
      await Future.wait([
        a.saveItem(
          PlannerItem(
            id: 'a',
            title: 'University',
            date: DateTime(2026, 10, 29),
          ),
        ),
        b.saveItem(
          PlannerItem(id: 'b', title: 'Run', date: DateTime(2026, 10, 29)),
        ),
      ]);
      expect(
        PlannerState.fromMap(
          native!['plannerState'] as Map<String, dynamic>,
        ).items.map((i) => i.id),
        ['a', 'b'],
      );
      a.dispose();
      b.dispose();
    },
  );

  test(
    'headless penalties commit to canonical storage, survive reopen and are never repeated',
    () async {
      final seed = PlannerController(
        initial: {},
        persist: (_) async {},
        clock: () => DateTime(2026, 10, 29, 8),
      );
      await seed.evaluate();
      await LocalStore.writeSetting('levelUpState', seed.exportState);
      final repo = repository();
      await repo.initialize();
      final hiveBefore = jsonEncode(LocalStore.settingMap('levelUpState'));
      Future<bool> run() => runPlannerBackgroundRefresh(
        bridge: PlannerRefreshBridge(channel: channel, enabled: true),
        clock: () => DateTime(2026, 10, 30, 1),
        scheduler: (occurrences, {required now, required storage}) async {
          // The native checkpoint must precede every plugin call, including
          // one that could hang until Android cancels the worker.
          expect(
            PlannerState.fromMap(
              native!['plannerState'] as Map<String, dynamic>,
            ).ledger.single.type,
            'missed_selection',
          );
          return const PlannerReminderSyncResult(
            ids: {},
            scheduled: 0,
            permissionGranted: false,
            exact: false,
          );
        },
      );
      expect(await run(), true);
      expect(jsonEncode(LocalStore.settingMap('levelUpState')), hiveBefore);
      var saved = PlannerState.fromMap(
        native!['plannerState'] as Map<String, dynamic>,
      );
      expect(saved.ledger.where((e) => e.type == 'missed_selection').length, 1);
      expect(saved.selections.first.isMissed, true);
      expect(saved.selections.first.acknowledged, false);
      final eventId = saved.ledger.single.id;
      expect(await run(), true);
      await repo.initialize();
      saved = PlannerState.fromMap(LocalStore.settingMap('levelUpState'));
      expect(saved.ledger.single.id, eventId);
      seed.dispose();
    },
  );

  test(
    'notification failure cannot discard a reconciled headless penalty',
    () async {
      final seed = PlannerController(
        initial: {},
        persist: (_) async {},
        clock: () => DateTime(2026, 10, 29, 8),
      );
      await seed.evaluate();
      native = {
        'schemaVersion': 1,
        'canonicalPlanner': true,
        'plannerState': seed.exportState,
        'values': {},
      };
      final ok = await runPlannerBackgroundRefresh(
        bridge: PlannerRefreshBridge(channel: channel, enabled: true),
        clock: () => DateTime(2026, 10, 30, 1),
        scheduler: (occurrences, {required now, required storage}) async =>
            const PlannerReminderSyncResult(
              ids: {},
              scheduled: 0,
              permissionGranted: true,
              exact: false,
              errors: ['Android unavailable'],
            ),
      );
      expect(ok, false);
      expect(
        PlannerState.fromMap(
          native!['plannerState'] as Map<String, dynamic>,
        ).ledger.single.type,
        'missed_selection',
      );
      seed.dispose();
    },
  );
}
