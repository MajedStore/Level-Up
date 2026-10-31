import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

ChallengeTemplate _workout({String name = 'Hard Workout', int reward = 40}) =>
    ChallengeTemplate(
      id: 'workout',
      name: name,
      description: 'A measured workout',
      difficulty: ChallengeDifficulty.hard,
      durationDays: 1,
      completionXp: reward,
      failurePenalty: 8,
      tasks: const [
        ChallengeTaskDefinition(
          id: 'warmup',
          title: 'Warm-up',
          dayOffsets: [0],
          startMinute: 17 * 60,
          durationMinutes: 10,
          rewardXp: 10,
          skipPenalty: 4,
        ),
        ChallengeTaskDefinition(
          id: 'run',
          title: 'Running',
          dayOffsets: [0],
          target: 3,
          unit: 'km',
          rewardXp: 20,
          skipPenalty: 7,
        ),
        ChallengeTaskDefinition(
          id: 'stretch',
          title: 'Stretching',
          dayOffsets: [0],
          steps: ['Left', 'Right'],
          rewardXp: 10,
          skipPenalty: 3,
        ),
      ],
    );

void main() {
  late DateTime time;
  late Map<String, dynamic> disk;
  late PlannerController controller;
  PlannerController open({Map<String, dynamic>? initial}) => PlannerController(
    clock: () => time,
    initial: initial ?? disk,
    persist: (state) async => disk = state,
    catalog: [],
  );
  setUp(() {
    time = DateTime(2026, 10, 26, 12);
    disk = {};
    controller = open();
  });
  tearDown(() => controller.dispose());

  test(
    'routine completion records progress without challenge XP or identity',
    () async {
      await controller.saveItem(
        PlannerItem(
          id: 'university',
          title: 'University',
          date: plannerDay(time),
          recurrence: PlannerRecurrence.weekdays,
          weekdays: [1, 2, 3, 4],
          startMinute: 480,
          endMinute: 840,
          xp: 999,
        ),
      );
      await controller.saveItem(
        PlannerItem(
          id: 'run',
          title: 'Running',
          date: plannerDay(time),
          recurrence: PlannerRecurrence.weekdays,
          weekdays: [3],
          startMinute: 1020,
          endMinute: 1080,
        ),
      );
      final routine = controller.occurrences(time).single;
      expect(routine.kind, PlannerTaskKind.routine);
      await controller.complete(routine.id);
      expect(controller.balance, 0);
      expect(controller.ledger, isEmpty);
      expect(controller.occurrences(DateTime(2026, 10, 28)).length, 2);
      expect(controller.instances, isEmpty);
    },
  );

  test(
    'custom package persists all tasks and immutable assignments survive editing and deletion',
    () async {
      await controller.saveTemplate(_workout());
      final selected = await controller.assignTomorrow('workout');
      expect(controller.tomorrowSelection!.instanceId, selected.id);
      expect(controller.instances.single.snapshot.tasks.length, 3);
      expect(
        controller
            .occurrences(DateTime(2026, 10, 27))
            .every(
              (o) =>
                  o.kind == PlannerTaskKind.challenge &&
                  o.challengeId == selected.id,
            ),
        isTrue,
      );
      await controller.saveTemplate(_workout(name: 'Edited', reward: 900));
      final copy = await controller.duplicateTemplate(
        'workout',
        name: 'Workout copy',
      );
      expect(copy.id, isNot('workout'));
      await controller.deleteTemplate('workout');
      controller.dispose();
      controller = open();
      expect(controller.templates.single.name, 'Workout copy');
      expect(controller.instances.single.snapshot.name, 'Hard Workout');
      expect(controller.instances.single.snapshot.completionXp, 40);
      expect(controller.instances.single.snapshot.tasks[1].target, 3);
      expect(controller.instances.single.snapshot.tasks[2].steps, [
        'Left',
        'Right',
      ]);
      await expectLater(
        controller.cancelChallenge(selected.id),
        throwsStateError,
      );
    },
  );

  test(
    'assignment is unique, preserves routines and has one shared task record',
    () async {
      await controller.saveTemplate(_workout());
      await controller.saveItem(
        PlannerItem(
          id: 'class',
          title: 'University',
          date: plannerDay(time),
          recurrence: PlannerRecurrence.daily,
          startMinute: 480,
          endMinute: 840,
        ),
      );
      final routine = jsonEncode(
        controller.items.map((i) => i.toMap()).toList(),
      );
      final assigned = await controller.assignTomorrow('workout');
      await expectLater(controller.assignTomorrow('workout'), throwsStateError);
      expect(controller.instances.length, 1);
      expect(
        jsonEncode(controller.items.map((i) => i.toMap()).toList()),
        routine,
      );
      time = DateTime(2026, 10, 27, 18);
      final id = '${assigned.id}/warmup@2026-10-27';
      await controller.complete(id);
      expect(
        controller.occurrenceById(id)!.record.status,
        CompletionStatus.completed,
      );
      expect(
        controller
            .occurrences(time)
            .singleWhere((o) => o.id == id)
            .record
            .status,
        CompletionStatus.completed,
      );
      expect(controller.balance, 10);
    },
  );

  test(
    'missed selection reconciles after restart exactly once including at zero balance',
    () async {
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 12,
      );
      expect(
        controller.nextSelectionDeadline,
        DateTime(2026, 10, 26, 20).toUtc(),
      );
      time = DateTime(2026, 10, 26, 20);
      await controller.evaluate();
      expect(controller.tomorrowSelection!.isMissed, isTrue);
      expect(controller.ledger.single.type, 'missed_selection');
      expect(
        controller.ledger.single.idempotencyKey,
        'missed_selection:2026-10-27',
      );
      expect(controller.ledger.single.change, 0);
      expect(controller.tomorrowSelection!.penalty, 12);
      final before = jsonEncode(controller.exportState);
      await controller.evaluate();
      controller.dispose();
      controller = open();
      await controller.evaluate();
      expect(jsonEncode(controller.exportState), before);
      expect(controller.unacknowledgedMisses.length, 1);
      await controller.acknowledgeMissedSelections();
      expect(controller.unacknowledgedMisses, isEmpty);
    },
  );

  test(
    'selection before deadline prevents a penalty; closed dates cannot reopen',
    () async {
      await controller.saveTemplate(_workout());
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 6,
      );
      await controller.assignTomorrow('workout');
      time = DateTime(2026, 10, 26, 21);
      await controller.evaluate();
      expect(controller.tomorrowSelection!.isSelected, isTrue);
      expect(controller.ledger, isEmpty);
      time = DateTime(2026, 10, 27, 21);
      await controller.evaluate();
      expect(controller.selectionFor(DateTime(2026, 10, 28))!.isMissed, isTrue);
      time = DateTime(2026, 10, 27, 10);
      await expectLater(controller.assignTomorrow('workout'), throwsStateError);
      await controller.updateSelectionRules(
        deadlineMinute: 1439,
        missedPenalty: 0,
      );
      expect(controller.selectionFor(DateTime(2026, 10, 28))!.penalty, 6);
      expect(
        controller.ledger.where((e) => e.type == 'missed_selection').length,
        1,
      );
    },
  );

  test('catch-up retains every local target date and frozen rules', () async {
    await controller.updateSelectionRules(
      deadlineMinute: 18 * 60,
      missedPenalty: 4,
    );
    final frozen = controller.tomorrowSelection!.deadline;
    time = DateTime(2026, 10, 29, 19);
    await controller.evaluate();
    expect(controller.selections.map((s) => s.dateKey), [
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
    ]);
    expect(
      controller.ledger.where((e) => e.type == 'missed_selection').length,
      4,
    );
    expect(controller.selections.first.deadline, frozen);
    await controller.evaluate();
    expect(controller.ledger.length, 4);
  });

  test(
    'actual skip penalty and missed-selection penalty both debit a funded ledger once',
    () async {
      await controller.saveTemplate(_workout());
      final assigned = await controller.assignTomorrow('workout');
      time = DateTime(2026, 10, 27, 12);
      await controller.complete('${assigned.id}/warmup@2026-10-27');
      await controller.skip('${assigned.id}/run@2026-10-27');
      await controller.skip('${assigned.id}/run@2026-10-27');
      expect(controller.balance, 3);
      expect(
        controller.ledger.where((e) => e.type == 'task_skip').single.change,
        -7,
      );
      time = DateTime(2026, 10, 27, 23, 59);
      await controller.evaluate();
      expect(controller.balance, 0);
      expect(
        controller.ledger
            .where((e) => e.type == 'missed_selection')
            .single
            .change,
        -3,
      );
      await controller.evaluate();
      controller.dispose();
      controller = open();
      await controller.evaluate();
      expect(controller.balance, 0);
      expect(controller.ledger.length, 3);
    },
  );

  test(
    'v1 migration preserves historical routine rewards and enrolls only today',
    () async {
      final old = PlannerState().toMap();
      old['schemaVersion'] = 1;
      old.remove('selections');
      old.remove('templates');
      old.remove('templatesInitialized');
      old['ledger'] = [
        XpTransaction(
          id: 'legacy',
          reason: 'Completed old routine',
          change: 25,
          type: 'task_completion',
          at: DateTime(2026, 10, 1),
          idempotencyKey: 'complete:legacy@2026-10-01',
        ).toMap(),
      ];
      controller.dispose();
      controller = open(initial: old);
      await controller.evaluate();
      expect(controller.balance, 25);
      expect(controller.ledger.single.id, 'legacy');
      expect(controller.selections.single.dateKey, '2026-10-27');
      expect(
        controller.exportState['schemaVersion'],
        PlannerState.schemaVersion,
      );
      await controller.saveItem(
        PlannerItem(id: 'new', title: 'New routine', date: plannerDay(time)),
      );
      await controller.complete('new@2026-10-26');
      expect(controller.balance, 25);
      expect(controller.ledger.length, 1);
    },
  );

  test(
    'two foreground/background controllers reread and commit under one lease',
    () async {
      var tail = Future<void>.value();
      var locked = false;
      var effects = 0;
      Future<void> transaction(Future<void> Function() action) {
        final completer = Completer<void>();
        tail = tail.then((_) async {
          locked = true;
          try {
            await action();
            completer.complete();
          } catch (error, stack) {
            completer.completeError(error, stack);
          } finally {
            locked = false;
          }
        });
        return completer.future;
      }

      PlannerController shared() => PlannerController(
        initial: {},
        catalog: [],
        clock: () => time,
        transaction: transaction,
        loadLatest: () async {
          expect(locked, isTrue);
          return disk;
        },
        persist: (state) async {
          expect(locked, isTrue);
          disk = state;
        },
        // Reacquiring the same lease proves side effects run after release.
        afterCommit: () => transaction(() async {
          effects++;
        }),
      );
      final a = shared();
      final b = shared();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.saveTemplate(_workout());
      final results = await Future.wait([
        a.assignTomorrow('workout').then((_) => true, onError: (_) => false),
        b.assignTomorrow('workout').then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((result) => result), hasLength(1));
      expect(PlannerState.fromMap(disk).instances, hasLength(1));
      time = DateTime(2026, 10, 26, 23, 59);
      await b.evaluate();
      expect(b.ledger, isEmpty);
      expect(effects, 2);
      await b.updateSelectionRules(deadlineMinute: 1439, missedPenalty: 9);
      var notifications = 0;
      a.addListener(() => notifications++);
      await a.evaluate();
      expect(a.instances, hasLength(1));
      // Reading a newer background snapshot refreshes UI even without a new write.
      expect(notifications, 1);
      expect(a.missedSelectionPenalty, 9);
      expect(a.sideEffectError, isNull);
    },
  );

  test(
    'spring/fall DST and time-zone changes keep one frozen deadline per local target date',
    () async {
      tzdata.initializeTimeZones();
      var location = tz.getLocation('America/New_York');
      var wall = tz.TZDateTime(location, 2026, 3, 7, 12);
      final dst = PlannerController(
        initial: {},
        catalog: [],
        clock: () => wall,
        persist: (_) async {},
        deadlineForLocalDay: (day, minute) => tz.TZDateTime(
          location,
          day.year,
          day.month,
          day.day,
          minute ~/ 60,
          minute % 60,
        ),
      );
      addTearDown(dst.dispose);
      await dst.evaluate();
      final first = dst.tomorrowSelection!.deadline;
      wall = tz.TZDateTime(location, 2026, 3, 8, 12);
      await dst.evaluate();
      final second = dst.tomorrowSelection!.deadline;
      expect(second.difference(first).inHours, 23);
      final frozen = dst.selections.first.deadline;
      location = tz.getLocation('Europe/Istanbul');
      wall = tz.TZDateTime(location, 2026, 3, 8, 21);
      await dst.evaluate();
      expect(dst.selections.first.deadline, frozen);
      expect(
        dst.selections.where((s) => s.dateKey == '2026-03-08'),
        hasLength(1),
      );
      expect(
        dst.ledger.where((e) => e.relatedId == '2026-03-08'),
        hasLength(1),
      );

      location = tz.getLocation('America/New_York');
      wall = tz.TZDateTime(location, 2026, 10, 31, 12);
      final fall = PlannerController(
        initial: {},
        catalog: [],
        clock: () => wall,
        persist: (_) async {},
        deadlineForLocalDay: (day, minute) => tz.TZDateTime(
          location,
          day.year,
          day.month,
          day.day,
          minute ~/ 60,
          minute % 60,
        ),
      );
      addTearDown(fall.dispose);
      await fall.evaluate();
      final beforeFall = fall.tomorrowSelection!.deadline;
      wall = tz.TZDateTime(location, 2026, 11, 1, 12);
      await fall.evaluate();
      expect(
        fall.tomorrowSelection!.deadline.difference(beforeFall).inHours,
        25,
      );
    },
  );

  test(
    'open settings apply immediately but a charged deadline survives rule edits and clock rollback',
    () async {
      final funded = PlannerState().toMap();
      funded['ledger'] = [
        XpTransaction(
          id: 'historical',
          reason: 'Historical reward',
          change: 20,
          type: 'task_completion',
          at: time,
          idempotencyKey: 'complete:historical@2026-10-25',
        ).toMap(),
      ];
      controller.dispose();
      controller = open(initial: funded);
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 4,
      );
      time = DateTime(2026, 10, 26, 17);
      await controller.updateSelectionRules(
        deadlineMinute: 21 * 60,
        missedPenalty: 9,
      );
      time = DateTime(2026, 10, 26, 20);
      await controller.evaluate();
      expect(controller.tomorrowSelection!.isPending, isTrue);
      time = DateTime(2026, 10, 26, 21);
      await controller.evaluate();
      expect(controller.balance, 11);
      final charged = controller.tomorrowSelection!;
      time = DateTime(2026, 10, 26, 18);
      await controller.updateSelectionRules(
        deadlineMinute: 1439,
        missedPenalty: 0,
      );
      expect(controller.tomorrowSelection!.deadline, charged.deadline);
      expect(controller.tomorrowSelection!.penalty, 9);
      controller.dispose();
      controller = open();
      await controller.evaluate();
      expect(controller.balance, 11);
      expect(
        controller.ledger.where((e) => e.type == 'missed_selection'),
        hasLength(1),
      );
    },
  );

  test(
    'selected commitments retain frozen selection rules after settings change',
    () async {
      await controller.saveTemplate(_workout());
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 4,
      );
      final assigned = await controller.assignTomorrow('workout');
      final commitment = controller.tomorrowSelection!;
      await controller.updateSelectionRules(
        deadlineMinute: 21 * 60,
        missedPenalty: 9,
      );
      expect(controller.tomorrowSelection!.deadline, commitment.deadline);
      expect(controller.tomorrowSelection!.penalty, 4);
      expect(controller.tomorrowSelection!.instanceId, assigned.id);
      time = DateTime(2026, 10, 26, 22);
      await controller.evaluate();
      expect(controller.ledger, isEmpty);
      expect(controller.tomorrowSelection!.isSelected, isTrue);
    },
  );

  test(
    'migration honors future legacy commitments and retains all overlapping historical instances',
    () async {
      time = DateTime(2026, 10, 26, 23, 59, 30);
      final first = await controller.startChallenge(
        _workout(),
        startDate: DateTime(2026, 10, 27),
      );
      time = time.add(const Duration(seconds: 1));
      final second = await controller.startChallenge(
        _workout(),
        startDate: DateTime(2026, 10, 27),
      );
      final old = controller.exportState;
      old['schemaVersion'] = 1;
      old.remove('selections');
      old.remove('lastObservedAt');
      old['ledger'] = []; // V1 had no daily-selection transactions.
      controller.dispose();
      controller = open(initial: old);
      await controller.evaluate();
      final migrated = controller.tomorrowSelection!;
      expect(migrated.instanceId, first.id);
      expect(migrated.deadline.isAfter(first.startedAt), isTrue);
      expect(controller.instances.map((i) => i.id), [first.id, second.id]);
      expect(controller.ledger, isEmpty);
      time = DateTime(2026, 10, 27, 12);
      await controller.evaluate();
      expect(
        controller.selectionFor(DateTime(2026, 10, 27))!.isSelected,
        isTrue,
      );
      expect(
        controller.ledger.where((e) => e.type == 'missed_selection'),
        isEmpty,
      );
      controller.dispose();
      controller = open();
      expect(
        controller.selectionFor(DateTime(2026, 10, 27))!.instanceId,
        first.id,
      );
      expect(controller.instances, hasLength(2));
    },
  );

  test(
    "tomorrow's package can be cancelled and replaced before the deadline",
    () async {
      await controller.saveTemplate(_workout());
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 6,
      );
      final deadline = controller.tomorrowSelection!.deadline;
      final first = await controller.assignTomorrow('workout');
      await controller.cancelTomorrow();
      expect(controller.instances, isEmpty);
      expect(controller.tomorrowSelection!.isPending, isTrue);
      expect(controller.tomorrowSelection!.deadline, deadline);
      expect(controller.tomorrowSelection!.penalty, 6);
      expect(controller.exportState['records'], isEmpty);
      expect(
        controller
            .occurrences(DateTime(2026, 10, 27))
            .where(
              (o) => o.challengeId == first.id,
            ),
        isEmpty,
      );
      await expectLater(controller.cancelTomorrow(), throwsStateError);
      final second = await controller.assignTomorrow('workout');
      expect(controller.tomorrowSelection!.instanceId, second.id);
      time = DateTime(2026, 10, 26, 21);
      await controller.evaluate();
      expect(controller.ledger, isEmpty);
    },
  );

  test(
    'cancelling after the deadline records the missed-selection penalty once',
    () async {
      await controller.saveTemplate(_workout());
      await controller.updateSelectionRules(
        deadlineMinute: 20 * 60,
        missedPenalty: 6,
      );
      await controller.assignTomorrow('workout');
      time = DateTime(2026, 10, 26, 22);
      await controller.cancelTomorrow();
      expect(controller.instances, isEmpty);
      expect(controller.tomorrowSelection!.isMissed, isTrue);
      expect(
        controller.ledger.where((e) => e.type == 'missed_selection').length,
        1,
      );
      await expectLater(controller.assignTomorrow('workout'), throwsStateError);
      await controller.evaluate();
      expect(controller.ledger.length, 1);
    },
  );

  test('a package that has started cannot be cancelled', () async {
    await controller.saveTemplate(_workout());
    await controller.assignTomorrow('workout');
    time = DateTime(2026, 10, 27, 12);
    await controller.evaluate();
    await expectLater(controller.cancelTomorrow(), throwsStateError);
    expect(controller.instances, hasLength(1));
  });
}
