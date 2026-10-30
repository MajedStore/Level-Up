import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/services/planner_background.dart';
import 'package:streak/services/planner_refresh_bridge.dart';
import 'package:streak/services/planner_reminder_schedule.dart';

final _start = DateTime(2026, 1, 1, 8);
const _channel = MethodChannel('levelup_background_test');

PlannerController _controller() => PlannerController(
  initial: {},
  clock: () => _start,
  persist: (_) async {},
);

Map<String, dynamic> _projection(
  PlannerController controller, {
  Map values = const {},
}) => {
  'schemaVersion': 1,
  'plannerState': controller.exportState,
  'values': values,
  'settings': {'locale': 'en'},
};

PlannerItem _daily({
  String id = 'daily',
  int? start,
  int? end,
  bool overnight = false,
}) => PlannerItem(
  id: id,
  title: id,
  date: plannerDay(_start),
  recurrence: PlannerRecurrence.daily,
  startMinute: start,
  endMinute: end,
  overnight: overnight,
  reminder: const PlannerReminder(enabled: true, minute: 9 * 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test(
    'unopened reminders regenerate beyond the original 28-day window without Hive',
    () async {
      final controller = _controller();
      await controller.saveItem(_daily());
      final raw = _projection(controller);
      final before = jsonEncode(raw);
      final projection = PlannerReminderProjection.fromMap(raw);
      final initial = projection.occurrences(_start);
      final later = projection.occurrences(DateTime(2026, 2, 15, 8));
      expect(initial.length, 28);
      expect(later.length, 28);
      expect(later.first.id, 'daily@2026-02-15');
      expect(later.last.id, 'daily@2026-03-14');
      expect(jsonEncode(raw), before);
      expect(jsonEncode(projection.toMap()), before);
      controller.dispose();
    },
  );

  test(
    'repeated projection is deterministic and overnight occurrences do not duplicate',
    () async {
      final controller = _controller();
      await controller.saveItem(
        _daily(start: 23 * 60, end: 60, overnight: true),
      );
      final projection = PlannerReminderProjection.fromMap(
        _projection(controller),
      );
      final now = DateTime(2026, 1, 2, 0, 30);
      final first = projection.occurrences(now);
      final second = projection.occurrences(now);
      expect(first.map((o) => o.id), second.map((o) => o.id));
      expect(first.map((o) => o.id).toSet().length, first.length);
      final firstIds = PlannerReminderSchedule.allocateIds(
        first.map((o) => o.id),
      );
      final secondIds = PlannerReminderSchedule.allocateIds(
        second.map((o) => o.id),
      );
      expect(firstIds, secondIds);
      controller.dispose();
    },
  );

  test(
    'seven-day lead times include origin dates beyond the notification horizon',
    () async {
      final controller = _controller();
      await controller.saveItem(
        PlannerItem(
          id: 'early',
          title: 'Prepare',
          date: DateTime(2026, 1, 31),
          startMinute: 9 * 60,
          endMinute: 10 * 60,
          reminder: const PlannerReminder(
            enabled: true,
            offsetMinutes: 7 * 24 * 60,
          ),
        ),
      );
      await controller.saveItem(
        PlannerItem(
          id: 'too-late',
          title: 'Later',
          date: DateTime(2026, 2, 10),
          startMinute: 9 * 60,
          endMinute: 10 * 60,
          reminder: const PlannerReminder(
            enabled: true,
            offsetMinutes: 7 * 24 * 60,
          ),
        ),
      );
      final occurrences = projectPlannerOccurrences(controller, now: _start);
      expect(occurrences.map((o) => o.id), ['early@2026-01-31']);
      expect(
        PlannerReminderSchedule.build(occurrences, now: _start).single.fireAt,
        DateTime(2026, 1, 24, 9),
      );
      controller.dispose();
    },
  );

  test(
    'a pending snooze survives refresh even when its original task is older',
    () async {
      final controller = _controller();
      await controller.saveItem(
        PlannerItem(
          id: 'old',
          title: 'Old reminder',
          date: plannerDay(_start),
          reminder: const PlannerReminder(enabled: true, minute: 9 * 60),
        ),
      );
      final now = DateTime(2026, 1, 3, 14, 30);
      final when = now.add(const Duration(minutes: 10));
      final values = {
        'plannerSnoozes': {'old@2026-01-01': when.toUtc().toIso8601String()},
      };
      final occurrences = projectPlannerOccurrences(
        controller,
        now: now,
        values: values,
      );
      expect(occurrences.single.id, 'old@2026-01-01');
      final requests = PlannerReminderSchedule.build(
        occurrences,
        now: now,
        snoozes: {'old@2026-01-01': when},
      );
      expect(requests.single.fireAt, when);
      controller.dispose();
    },
  );

  test(
    'expired challenge reminders disappear without changing canonical status or XP',
    () async {
      final controller = _controller();
      await controller.startChallenge(
        const ChallengeTemplate(
          id: 'one-day',
          name: 'One day',
          description: 'Expires tomorrow',
          difficulty: ChallengeDifficulty.hard,
          durationDays: 1,
          completionXp: 100,
          failurePenalty: 25,
          tasks: [
            ChallengeTaskDefinition(
              id: 'focus',
              title: 'Focus',
              dayOffsets: [0],
              startMinute: 15 * 60,
              durationMinutes: 30,
              reminder: PlannerReminder(enabled: true, minute: 15 * 60),
            ),
          ],
        ),
      );
      final raw = _projection(controller);
      final before = jsonEncode(raw);
      final projection = PlannerReminderProjection.fromMap(raw);
      expect(projection.occurrences(_start).length, 1);
      expect(projection.occurrences(DateTime(2026, 1, 3, 8)), isEmpty);
      expect(jsonEncode(projection.toMap()), before);
      expect(controller.instances.single.status, ChallengeStatus.active);
      expect(controller.ledger, isEmpty);
      controller.dispose();
    },
  );

  test(
    'projection snapshots and auxiliary storage are detached from callers',
    () async {
      final controller = _controller();
      await controller.saveItem(_daily());
      final raw = _projection(
        controller,
        values: {
          'plannerNotificationIds': {'daily': 123},
        },
      );
      final projection = PlannerReminderProjection.fromMap(raw);
      (raw['plannerState'] as Map)['items'] = [];
      final stateCopy = projection.plannerState;
      (stateCopy['items'] as List).clear();
      expect(projection.occurrences(_start), hasLength(28));
      final storage = MapPlannerReminderStorage(projection.values);
      storage.readMap('plannerNotificationIds').clear();
      storage.exportValues.clear();
      expect(storage.readMap('plannerNotificationIds'), {'daily': 123});
      await expectLater(
        storage.writeValue('levelUpState', {}),
        throwsArgumentError,
      );
      controller.dispose();
    },
  );

  test('worker completion publishes only notification metadata', () async {
    final controller = _controller();
    await controller.saveItem(_daily());
    final raw = _projection(controller);
    final before = jsonEncode(raw);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'readBackground') return raw;
      return true;
    });
    final success = await runPlannerBackgroundRefresh(
      bridge: PlannerRefreshBridge(channel: _channel, enabled: true),
      clock: () => _start,
      scheduler: (occurrences, {required now, required storage}) async {
        expect(occurrences, hasLength(28));
        await storage.writeValue('plannerNotificationIds', {
          'daily@2026-01-01': 1200000001,
        });
        await storage.writeValue('plannerReminderStatus', 'Scheduled');
        return const PlannerReminderSyncResult(
          ids: {'daily@2026-01-01': 1200000001},
          scheduled: 1,
          permissionGranted: true,
          exact: false,
        );
      },
    );
    expect(success, isTrue);
    expect(calls.map((c) => c.method), [
      'readBackground',
      'completeBackground',
    ]);
    final completion = calls.last.arguments as Map;
    expect(completion['success'], isTrue);
    expect(completion.containsKey('plannerState'), isFalse);
    expect((completion['values'] as Map).keys.toSet(), {
      'plannerNotificationIds',
      'plannerReminderStatus',
    });
    expect(jsonEncode(raw), before);
    controller.dispose();
  });

  test(
    'worker backend failure is reported without publishing planner data',
    () async {
      final controller = _controller();
      await controller.saveItem(_daily());
      final raw = _projection(controller);
      final before = jsonEncode(raw);
      Map? completed;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'readBackground') return raw;
        if (call.method == 'completeBackground') {
          completed = call.arguments as Map;
        }
        return true;
      });
      final success = await runPlannerBackgroundRefresh(
        bridge: PlannerRefreshBridge(channel: _channel, enabled: true),
        clock: () => _start,
        scheduler: (occurrences, {required now, required storage}) async =>
            throw StateError('Android unavailable'),
      );
      expect(success, isFalse);
      expect(completed!['success'], isFalse);
      expect(completed!['error'], contains('Android unavailable'));
      expect(completed!.containsKey('plannerState'), isFalse);
      expect(jsonEncode(raw), before);
      controller.dispose();
    },
  );

  test(
    'notification denial records status without treating user permission as transient failure',
    () async {
      final controller = _controller();
      final raw = _projection(controller);
      Map? completed;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'readBackground') return raw;
        completed = call.arguments as Map;
        return true;
      });
      final success = await runPlannerBackgroundRefresh(
        bridge: PlannerRefreshBridge(channel: _channel, enabled: true),
        clock: () => _start,
        scheduler: (occurrences, {required now, required storage}) async {
          await storage.writeValue(
            'plannerReminderStatus',
            'Notifications are disabled',
          );
          return const PlannerReminderSyncResult(
            ids: {},
            scheduled: 0,
            permissionGranted: false,
            exact: false,
          );
        },
      );
      expect(success, isTrue);
      expect(
        (completed!['values'] as Map)['plannerReminderStatus'],
        'Notifications are disabled',
      );
      controller.dispose();
    },
  );

  test('foreground lease releases after a callback failure', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'acquire') {
        return {'lease': 'lease-a', 'projection': null};
      }
      return true;
    });
    final bridge = PlannerRefreshBridge(channel: _channel, enabled: true);
    await expectLater(
      bridge.withLease<void>((lease) async {
        await lease.publish({
          'schemaVersion': 1,
          'plannerState': {},
          'values': {},
        });
        throw StateError('failed save');
      }),
      throwsStateError,
    );
    expect(calls.map((c) => c.method), ['acquire', 'publish', 'release']);
    expect((calls.last.arguments as Map)['lease'], 'lease-a');
  });

  test(
    'concurrent foreground refreshes serialize across bridge instances',
    () async {
      final calls = <String>[];
      final entered = Completer<void>();
      final allowFinish = Completer<void>();
      var acquired = 0;
      var held = false;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        if (call.method == 'acquire') {
          expect(held, isFalse);
          held = true;
          return {'lease': 'lease-${++acquired}', 'projection': null};
        }
        if (call.method == 'release') held = false;
        return true;
      });
      final first = PlannerRefreshBridge(channel: _channel, enabled: true)
          .withLease((lease) async {
            entered.complete();
            await allowFinish.future;
            return 'first';
          });
      await entered.future;
      final second = PlannerRefreshBridge(
        channel: _channel,
        enabled: true,
      ).withLease((lease) async => 'second');
      expect(acquired, 1);
      allowFinish.complete();
      expect(await first, 'first');
      expect(await second, 'second');
      expect(calls, ['acquire', 'release', 'acquire', 'release']);
    },
  );

  test(
    'failed acquisition does not block the next foreground refresh',
    () async {
      var attempts = 0;
      var released = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'acquire') {
          attempts++;
          if (attempts == 1) throw PlatformException(code: 'native-busy');
          return {'lease': 'recovered', 'projection': null};
        }
        if (call.method == 'release') released++;
        return true;
      });
      final bridge = PlannerRefreshBridge(channel: _channel, enabled: true);
      await expectLater(
        bridge.withLease((_) async => true),
        throwsA(isA<PlatformException>()),
      );
      expect(await bridge.withLease((_) async => true), isTrue);
      expect(attempts, 2);
      expect(released, 1);
    },
  );

  test('explicit wipe clears the native projection under its lease', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'acquire') {
        return {'lease': 'wipe', 'projection': null};
      }
      return true;
    });
    final bridge = PlannerRefreshBridge(channel: _channel, enabled: true);
    await bridge.withLease((lease) => lease.clear());
    await bridge.configure(enabled: false);
    expect(calls.map((c) => c.method), [
      'acquire',
      'clear',
      'release',
      'configure',
    ]);
    expect((calls.last.arguments as Map)['enabled'], isFalse);
  });

  test('unsupported mirrors fail visibly without scheduling', () async {
    Map? completed;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'readBackground') {
        return {'schemaVersion': 999, 'plannerState': {}};
      }
      completed = call.arguments as Map;
      return true;
    });
    var scheduled = false;
    final success = await runPlannerBackgroundRefresh(
      bridge: PlannerRefreshBridge(channel: _channel, enabled: true),
      scheduler: (occurrences, {required now, required storage}) async {
        scheduled = true;
        throw StateError('must not schedule');
      },
    );
    expect(success, isFalse);
    expect(scheduled, isFalse);
    expect(completed!['success'], isFalse);
  });

  test('future reminder definitions keep periodic refresh enabled', () async {
    final controller = _controller();
    expect(hasPlannerReminderDefinitions(controller), isFalse);
    await controller.saveItem(
      PlannerItem(
        id: 'next-year',
        title: 'Future appointment',
        date: DateTime(2027, 1, 1),
        reminder: const PlannerReminder(enabled: true, minute: 9 * 60),
      ),
    );
    expect(projectPlannerOccurrences(controller, now: _start), isEmpty);
    expect(hasPlannerReminderDefinitions(controller), isTrue);
    controller.dispose();
  });

  test(
    'deleted and disabled reminder preferences do not keep a worker alive',
    () async {
      final controller = _controller();
      await controller.saveItem(_daily());
      await controller.setReminder(
        'daily@2026-01-01',
        const PlannerReminder(enabled: true, minute: 600),
      );
      expect(hasPlannerReminderDefinitions(controller), isTrue);
      await controller.deleteItem('daily');
      expect(hasPlannerReminderDefinitions(controller), isFalse);
      await controller.saveItem(_daily(id: 'disabled'));
      await controller.setReminder(
        'disabled@2026-01-01',
        const PlannerReminder(enabled: false),
        entireSeries: true,
      );
      expect(hasPlannerReminderDefinitions(controller), isFalse);
      controller.dispose();
    },
  );

  test('historical challenge preferences do not keep a worker alive', () async {
    final controller = _controller();
    final instance = await controller.startChallenge(
      const ChallengeTemplate(
        id: 'past',
        name: 'Past challenge',
        description: 'One required step',
        difficulty: ChallengeDifficulty.easy,
        durationDays: 1,
        completionXp: 10,
        tasks: [
          ChallengeTaskDefinition(id: 'one', title: 'One', dayOffsets: [0]),
        ],
      ),
    );
    await controller.setReminder(
      '${instance.id}/one@2026-01-01',
      const PlannerReminder(enabled: true, minute: 9 * 60),
      entireSeries: true,
    );
    expect(hasPlannerReminderDefinitions(controller), isTrue);
    await controller.complete('${instance.id}/one@2026-01-01');
    expect(controller.instances.single.status, ChallengeStatus.completed);
    expect(hasPlannerReminderDefinitions(controller), isFalse);
    controller.dispose();
  });
}
