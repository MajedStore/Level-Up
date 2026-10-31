import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';

void main() {
  late DateTime clock;
  late PlannerController controller;
  late Map<String, dynamic> saved;

  PlannerItem item(
    String id, {
    PlannerRecurrence recurrence = PlannerRecurrence.once,
    List<int> weekdays = const [],
    int? start,
    int? end,
    bool overnight = false,
    List<String> steps = const [],
    double? target,
    String unit = '',
    List<String> dependencies = const [],
    int xp = 10,
    DateTime? date,
  }) => PlannerItem(
    id: id,
    title: id,
    date: date ?? DateTime(2026, 10, 26),
    recurrence: recurrence,
    weekdays: weekdays,
    startMinute: start,
    endMinute: end,
    overnight: overnight,
    steps: steps,
    target: target,
    unit: unit,
    dependencies: dependencies,
    xp: xp,
  );
  ChallengeTemplate package({
    List<ChallengeTaskDefinition>? tasks,
    int duration = 2,
    int failurePenalty = 0,
  }) => ChallengeTemplate(
    id: 'test',
    name: 'Test package',
    description: 'Rules are explicit',
    difficulty: ChallengeDifficulty.hard,
    durationDays: duration,
    completionXp: 50,
    failurePenalty: failurePenalty,
    tasks:
        tasks ??
        const [
          ChallengeTaskDefinition(
            id: 'move',
            title: 'Move',
            dayOffsets: [0, 1],
            startMinute: 900,
            durationMinutes: 90,
            rewardXp: 20,
            skipPenalty: 15,
          ),
        ],
  );
  String id(String itemId, [DateTime? day]) =>
      '$itemId@${plannerDateKey(day ?? clock)}';

  Future<void> legacyBalance(int amount) async {
    final state = controller.exportState;
    state['ledger'] = [
      XpTransaction(
        id: 'legacy-grant',
        reason: 'Preserved historical XP',
        change: amount,
        type: 'legacy_balance',
        at: clock,
        idempotencyKey: 'legacy-grant',
      ).toMap(),
    ];
    controller.dispose();
    controller = PlannerController(
      clock: () => clock,
      initial: state,
      persist: (value) async => saved = value,
    );
    await controller.updateSelectionRules(
      deadlineMinute: 1439,
      missedPenalty: 0,
    );
  }

  setUp(() {
    clock = DateTime(2026, 10, 26, 10);
    saved = {};
    controller = PlannerController(
      clock: () => clock,
      initial: {},
      persist: (value) async {
        saved = value;
      },
    );
  });
  tearDown(() => controller.dispose());

  test('an empty existing installation has no fabricated progress', () {
    expect(controller.items, isEmpty);
    expect(controller.instances, isEmpty);
    expect(controller.balance, 0);
    expect(controller.achievements, isEmpty);
    expect(controller.templates.length, 3);
  });

  test(
    'challenge occurrence validity follows its immutable deadline',
    () async {
      await controller.saveItem(item('ordinary'));
      final instance = await controller.startChallenge(package());
      final occurrenceId = '${instance.id}/move@2026-10-26';
      expect(
        controller.occurrenceById(occurrenceId)!.validUntil,
        instance.deadline,
      );
      expect(
        controller.occurrenceById('ordinary@2026-10-26')!.validUntil,
        isNull,
      );
      expect(controller.exportState.toString(), isNot(contains('validUntil')));

      clock = instance.deadline;
      await controller.evaluate();
      final balance = controller.balance;
      final ledgerCount = controller.ledger.length;
      final history = controller.occurrenceById(occurrenceId)!;
      expect(history.validUntil, instance.deadline);
      expect(history.record.status, CompletionStatus.pending);
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(controller.balance, balance);
      expect(controller.ledger.length, ledgerCount);
    },
  );

  test('early completion limits pending historical task reminders', () async {
    final instance = await controller.startChallenge(
      package(
        tasks: const [
          ChallengeTaskDefinition(
            id: 'required',
            title: 'Required',
            dayOffsets: [0],
            startMinute: 8 * 60,
            durationMinutes: 15,
          ),
          ChallengeTaskDefinition(
            id: 'optional',
            title: 'Optional',
            dayOffsets: [0],
            startMinute: 9 * 60,
            durationMinutes: 15,
            mandatory: false,
            reminder: PlannerReminder(enabled: true),
          ),
        ],
      ),
    );
    await controller.complete('${instance.id}/required@2026-10-26');
    expect(controller.instances.single.status, ChallengeStatus.completed);
    final history = controller.occurrenceById(
      '${instance.id}/optional@2026-10-26',
    )!;
    expect(history.validUntil, clock);
    expect(history.validUntil!.isBefore(instance.deadline), isTrue);
    expect(history.record.status, CompletionStatus.pending);
    final before = controller.exportState;
    controller.occurrences(clock);
    expect(controller.exportState, before);
  });

  test(
    'selected weekdays and once-only activities use real calendar days',
    () async {
      await controller.saveItem(
        item(
          'university',
          recurrence: PlannerRecurrence.weekdays,
          weekdays: [1, 2, 4],
          start: 480,
          end: 840,
        ),
      );
      await controller.saveItem(item('once', date: DateTime(2026, 10, 28)));
      expect(
        controller.occurrences(DateTime(2026, 10, 26)).map((o) => o.title),
        ['university'],
      );
      expect(
        controller.occurrences(DateTime(2026, 10, 27)).map((o) => o.title),
        ['university'],
      );
      expect(
        controller.occurrences(DateTime(2026, 10, 28)).map((o) => o.title),
        ['once'],
      );
      expect(
        controller.occurrences(DateTime(2026, 10, 29)).map((o) => o.title),
        ['university'],
      );
      expect(controller.occurrences(DateTime(2026, 10, 25)), isEmpty);
    },
  );

  test('weekly intervals anchor to the Monday of the start week', () async {
    await controller.saveItem(
      item(
        'run',
        recurrence: PlannerRecurrence.weekly,
        weekdays: [3, 6],
      ).copyWith(everyWeeks: 2),
    );
    expect(controller.occurrences(DateTime(2026, 10, 28)), hasLength(1));
    expect(controller.occurrences(DateTime(2026, 10, 31)), hasLength(1));
    expect(controller.occurrences(DateTime(2026, 11, 4)), isEmpty);
    expect(controller.occurrences(DateTime(2026, 11, 11)), hasLength(1));
    expect(
      PlannerController.weekStart(DateTime(2026, 11, 1)),
      DateTime(2026, 10, 26),
    );
    expect(
      PlannerController.weekStart(DateTime(2026, 11, 1), firstWeekday: 7),
      DateTime(2026, 11, 1),
    );
  });

  test(
    'overnight activity intersects both days without duplicate occurrences',
    () async {
      await controller.saveItem(
        item('night', start: 1380, end: 60, overnight: true),
      );
      final monday = controller.occurrences(clock).single;
      final tuesday = controller.occurrences(DateTime(2026, 10, 27)).single;
      expect(monday.id, tuesday.id);
      expect(tuesday.start, DateTime(2026, 10, 26, 23));
      expect(tuesday.end, DateTime(2026, 10, 27, 1));
      expect(controller.occurrences(DateTime(2026, 10, 28)), isEmpty);
    },
  );

  test(
    'overlap detection includes challenge overlays and overnight boundaries',
    () async {
      await controller.saveItem(item('base', start: 900, end: 960));
      final started = await controller.startChallenge(package());
      final occurrences = controller.occurrences(clock);
      expect(occurrences, hasLength(2));
      expect(controller.conflictsFor(occurrences.first), hasLength(1));
      expect(controller.items.single.title, 'base');
      expect(
        occurrences.where((o) => o.challengeId == started.id),
        hasLength(1),
      );
      expect(
        controller.occurrences(clock).map((o) => o.id).toSet(),
        occurrences.map((o) => o.id).toSet(),
      );
    },
  );

  test(
    'single occurrence editing and deletion preserve the recurring series',
    () async {
      final series = item(
        'class',
        recurrence: PlannerRecurrence.daily,
        start: 480,
        end: 600,
      );
      await controller.saveItem(series);
      await controller.saveItem(
        series.copyWith(title: 'Special class', startMinute: 540),
        occurrenceDay: clock,
      );
      expect(controller.occurrences(clock).single.title, 'Special class');
      expect(
        controller.occurrences(DateTime(2026, 10, 27)).single.title,
        'class',
      );
      await controller.deleteItem('class', occurrenceDay: clock);
      expect(controller.occurrences(clock), isEmpty);
      expect(controller.occurrences(DateTime(2026, 10, 27)), hasLength(1));
      expect(controller.items.single.startMinute, 480);
    },
  );

  test(
    'moving one occurrence preserves its original key and never duplicates it',
    () async {
      final series = item(
        'class',
        recurrence: PlannerRecurrence.weekdays,
        weekdays: [1],
      );
      await controller.saveItem(series);
      await controller.saveItem(
        series.copyWith(date: DateTime(2026, 10, 27)),
        occurrenceDay: clock,
      );
      expect(controller.occurrences(clock), isEmpty);
      expect(
        controller.occurrences(DateTime(2026, 10, 27)).single.id,
        id('class'),
      );
    },
  );

  test('invalid forms and cyclic dependencies fail without saving', () async {
    await expectLater(
      controller.saveItem(item('bad', start: 1000, end: 900)),
      throwsArgumentError,
    );
    await expectLater(
      controller.saveItem(item('bad', recurrence: PlannerRecurrence.weekdays)),
      throwsArgumentError,
    );
    await controller.saveItem(item('first'));
    await controller.saveItem(item('second', dependencies: ['first']));
    await expectLater(
      controller.saveItem(item('first', dependencies: ['second'])),
      throwsArgumentError,
    );
    expect(controller.items.first.dependencies, isEmpty);
  });

  test('starting creates separate instances and immutable snapshots', () async {
    final tasks = [
      const ChallengeTaskDefinition(
        id: 'work',
        title: 'Original',
        dayOffsets: [0],
      ),
    ];
    final template = package(tasks: tasks);
    final first = await controller.startChallenge(template);
    tasks[0] = const ChallengeTaskDefinition(
      id: 'work',
      title: 'Edited',
      dayOffsets: [0],
      rewardXp: 999,
    );
    final second = await controller.startChallenge(template);
    expect(first.id, isNot(second.id));
    expect(controller.instances.first.snapshot.tasks.single.title, 'Original');
    expect(controller.instances.last.snapshot.tasks.single.title, 'Edited');
    first.snapshot.tasks.clear();
    expect(controller.instances.first.snapshot.tasks, hasLength(1));
    expect(controller.exportState['records'], hasLength(2));
    await expectLater(controller.cancelChallenge(first.id), throwsStateError);
    await expectLater(
      controller.deleteItem('${first.id}/work'),
      throwsStateError,
    );
  });

  test(
    'mandatory task rewards and package reward are each awarded once',
    () async {
      final instance = await controller.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(
              id: 'work',
              title: 'Work',
              dayOffsets: [0],
              rewardXp: 20,
            ),
          ],
        ),
      );
      final occurrenceId = id('${instance.id}/work');
      await Future.wait([
        controller.complete(occurrenceId),
        controller.complete(occurrenceId),
      ]);
      expect(controller.balance, 70);
      expect(
        controller.ledger.where((e) => e.type == 'task_completion'),
        hasLength(1),
      );
      expect(
        controller.ledger.where((e) => e.type == 'challenge_completion'),
        hasLength(1),
      );
      expect(controller.instances.single.status, ChallengeStatus.completed);
      expect(
        controller.achievements.map((a) => a.id),
        containsAll(['first-task', 'first-package', 'first-hard']),
      );
      await controller.evaluate();
      expect(controller.balance, 70);
    },
  );

  test(
    'skip uses captured penalty once, never rewards completion, and floors XP at zero',
    () async {
      await legacyBalance(100);
      await controller.saveItem(item('seed', xp: 100));
      await controller.complete(id('seed'));
      final instance = await controller.startChallenge(package());
      final taskId = id('${instance.id}/move');
      await Future.wait([controller.skip(taskId), controller.skip(taskId)]);
      await controller.complete(taskId);
      expect(controller.balance, 85);
      expect(
        controller.occurrenceById(taskId)!.record.status,
        CompletionStatus.skipped,
      );
      expect(
        controller.ledger.where((e) => e.type == 'task_skip').single.change,
        -15,
      );
      expect(controller.instances.single.status, ChallengeStatus.active);
      clock = DateTime(2026, 10, 27, 10);
      await controller.skip(id('${instance.id}/move'));
      expect(controller.balance, 70);
      clock = DateTime(2026, 10, 28);
      await controller.evaluate();
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(
        controller.ledger.where((e) => e.type == 'challenge_completion'),
        isEmpty,
      );
    },
  );

  test(
    'a penalty at zero is auditable and applies only the available balance',
    () async {
      final instance = await controller.startChallenge(package());
      await controller.skip(id('${instance.id}/move'));
      expect(controller.balance, 0);
      expect(controller.ledger.single.change, 0);
      expect(controller.ledger.single.reason, contains('15 XP'));
      expect(controller.ledger.single.type, 'task_skip');
    },
  );

  test('stored steps never block completing a task', () async {
    await controller.saveItem(
      item('legacy', steps: ['Warm up', 'Workout', 'Stretch']),
    );
    await controller.complete(id('legacy'));
    expect(
      controller.occurrenceById(id('legacy'))!.record.status,
      CompletionStatus.completed,
    );
  });

  test(
    'legacy step records still apply in order when recorded',
    () async {
      await controller.saveItem(
        item('sequence', steps: ['Warm up', 'Workout', 'Stretch']),
      );
      final taskId = id('sequence');
      await expectLater(controller.completeStep(taskId, 1), throwsStateError);
      await controller.completeStep(taskId, 0);
      await controller.completeStep(taskId, 0);
      expect(controller.occurrenceById(taskId)!.record.completedSteps, [0]);
      expect(controller.balance, 0);
      await controller.completeStep(taskId, 1);
      await controller.completeStep(taskId, 2);
      expect(
        controller.occurrenceById(taskId)!.record.status,
        CompletionStatus.completed,
      );
      expect(controller.balance, 0);
    },
  );

  test(
    'amount tasks validate finite input and complete only at their target',
    () async {
      await controller.saveItem(item('read', target: 20, unit: 'pages'));
      final taskId = id('read');
      await expectLater(
        controller.recordAmount(taskId, double.nan),
        throwsArgumentError,
      );
      await expectLater(
        controller.recordAmount(taskId, -1),
        throwsArgumentError,
      );
      await controller.recordAmount(taskId, 19);
      await expectLater(controller.complete(taskId), throwsStateError);
      await controller.recordAmount(taskId, 20);
      expect(controller.balance, 0);
      await controller.recordAmount(taskId, 30);
      expect(controller.balance, 0);
    },
  );

  test(
    'prerequisites block completion and skipped prerequisites do not qualify',
    () async {
      await controller.saveItem(item('first'));
      await controller.saveItem(item('second', dependencies: ['first']));
      await expectLater(controller.complete(id('second')), throwsStateError);
      await controller.complete(id('first'));
      await controller.complete(id('second'));
      expect(controller.completedCount, 2);
    },
  );

  test(
    'challenge prerequisites enforce task definitions on each scheduled day',
    () async {
      final instance = await controller.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(
              id: 'first',
              title: 'First',
              dayOffsets: [0],
            ),
            ChallengeTaskDefinition(
              id: 'second',
              title: 'Second',
              dayOffsets: [0],
              dependencies: ['first'],
            ),
          ],
        ),
      );
      await expectLater(
        controller.complete(id('${instance.id}/second')),
        throwsStateError,
      );
      await controller.skip(id('${instance.id}/first'));
      await expectLater(
        controller.complete(id('${instance.id}/second')),
        throwsStateError,
      );
      await controller.skip(id('${instance.id}/second'));
      expect(controller.skippedCount, 2);
    },
  );

  test('future challenge tasks cannot be completed or skipped ahead', () async {
    final instance = await controller.startChallenge(package());
    final futureId = id('${instance.id}/move', DateTime(2026, 10, 27));
    await expectLater(controller.complete(futureId), throwsStateError);
    await expectLater(controller.skip(futureId), throwsStateError);
    expect(controller.balance, 0);
  });

  test(
    'expiration and failure penalties run exactly once with historical schedule intact',
    () async {
      await legacyBalance(100);
      await controller.saveItem(
        item(
          'base',
          recurrence: PlannerRecurrence.daily,
          start: 800,
          end: 850,
          xp: 100,
        ),
      );
      await controller.complete(id('base'));
      final instance = await controller.startChallenge(
        package(failurePenalty: 25),
      );
      clock = DateTime(2026, 10, 28);
      await controller.evaluate();
      await controller.evaluate();
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(controller.balance, 75);
      expect(
        controller.ledger.where((e) => e.type == 'challenge_failure'),
        hasLength(1),
      );
      expect(
        controller
            .occurrences(DateTime(2026, 10, 26))
            .where((o) => o.challengeId == instance.id),
        hasLength(1),
      );
      expect(
        controller
            .occurrences(DateTime(2026, 10, 28))
            .where((o) => o.isChallenge),
        isEmpty,
      );
      expect(controller.items.single.id, 'base');
      await expectLater(
        controller.complete(id('${instance.id}/move', DateTime(2026, 10, 26))),
        throwsStateError,
      );
    },
  );

  test(
    'finishing required work removes optional future schedule without losing history',
    () async {
      final instance = await controller.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(
              id: 'required',
              title: 'Required',
              dayOffsets: [0],
            ),
            ChallengeTaskDefinition(
              id: 'optional',
              title: 'Optional',
              dayOffsets: [1],
              mandatory: false,
              startMinute: 900,
            ),
          ],
        ),
      );
      await controller.complete(id('${instance.id}/required'));
      expect(controller.instances.single.status, ChallengeStatus.completed);
      expect(
        controller
            .occurrences(DateTime(2026, 10, 27))
            .where((o) => o.isChallenge),
        isEmpty,
      );
      expect(
        controller.occurrences(clock).single.record.status,
        CompletionStatus.completed,
      );
      expect(controller.exportState['records'], hasLength(2));
    },
  );

  test(
    'a late completion is rejected while deadline failure is persisted',
    () async {
      final instance = await controller.startChallenge(
        package(failurePenalty: 20),
      );
      clock = DateTime(2026, 10, 28);
      await expectLater(
        controller.complete(id('${instance.id}/move', DateTime(2026, 10, 26))),
        throwsStateError,
      );
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(
        PlannerState.fromMap(saved).instances.single.status,
        ChallengeStatus.failed,
      );
      expect(
        controller.ledger.where((e) => e.type == 'task_completion'),
        isEmpty,
      );
    },
  );

  test(
    'challenge reminder preferences persist independently of snapshot rules',
    () async {
      final instance = await controller.startChallenge(package());
      final occurrenceId = id('${instance.id}/move');
      await controller.setReminder(
        occurrenceId,
        const PlannerReminder(enabled: true, offsetMinutes: 10, sound: 'soft'),
        entireSeries: true,
      );
      expect(
        controller.occurrenceById(occurrenceId)!.item.reminder.enabled,
        isTrue,
      );
      expect(
        controller
            .occurrences(DateTime(2026, 10, 27))
            .single
            .item
            .reminder
            .offsetMinutes,
        10,
      );
      expect(
        controller.instances.single.snapshot.tasks.single.reminder.enabled,
        isFalse,
      );
    },
  );

  test(
    'one atomic save holds completion, XP, achievements and challenge lifecycle',
    () async {
      final instance = await controller.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(id: 'work', title: 'Work', dayOffsets: [0]),
          ],
        ),
      );
      await controller.complete(id('${instance.id}/work'));
      final restarted = PlannerController(
        clock: () => clock,
        initial: saved,
        persist: (_) async {},
      );
      addTearDown(restarted.dispose);
      expect(restarted.balance, 60);
      expect(restarted.instances.single.status, ChallengeStatus.completed);
      expect(restarted.achievements.length, 3);
      await restarted.complete(id('${instance.id}/work'));
      expect(restarted.balance, 60);
    },
  );

  test(
    'failed saves roll back all state and do not poison subsequent commands',
    () async {
      var fail = true;
      final failing = PlannerController(
        clock: () => clock,
        initial: {},
        persist: (_) async {
          if (fail) throw StateError('Disk full');
        },
      );
      addTearDown(failing.dispose);
      await expectLater(failing.saveItem(item('write')), throwsStateError);
      expect(failing.items, isEmpty);
      fail = false;
      await failing.saveItem(item('write'));
      expect(failing.items, hasLength(1));
    },
  );

  test(
    'reminder failure is surfaced without rolling back committed completion',
    () async {
      controller.afterCommit = () async =>
          throw StateError('Permission unavailable');
      await controller.saveItem(item('work'));
      await controller.complete(id('work'));
      expect(controller.balance, 0);
      expect(controller.sideEffectError, contains('data was saved'));
    },
  );

  test(
    'ledger survives serialization and rejects unsupported schemas',
    () async {
      await controller.saveItem(item('work'));
      await controller.complete(id('work'));
      final instance = await controller.startChallenge(package());
      await controller.skip(id('${instance.id}/move'));
      expect(
        PlannerState.fromMap(saved).ledger.single.idempotencyKey,
        'skip:${id('${instance.id}/move')}',
      );
      final exported = controller.exportState;
      (exported['items'] as List).clear();
      expect(controller.items, hasLength(1));
      expect(
        () => PlannerState.fromMap({'schemaVersion': 99}),
        throwsStateError,
      );
      final duplicated = controller.exportState;
      (duplicated['ledger'] as List).add((duplicated['ledger'] as List).single);
      expect(() => PlannerState.fromMap(duplicated), throwsStateError);
    },
  );

  test('level progression uses deterministic increasing thresholds', () {
    const progression = LevelProgression();
    expect(progression.levelFor(0), 1);
    expect(progression.levelFor(99), 1);
    expect(progression.levelFor(100), 2);
    expect(progression.levelFor(249), 2);
    expect(progression.levelFor(250), 3);
    expect(progression.levelFor(450), 4);
    expect(progression.progress(175), 0.5);
  });

  test(
    'streaks count real completion days and achievements unlock once',
    () async {
      await controller.saveItem(
        item('daily', recurrence: PlannerRecurrence.daily),
      );
      for (var i = 0; i < 7; i++) {
        clock = DateTime(2026, 10, 26 + i, 10);
        await controller.complete(id('daily'));
      }
      expect(controller.currentStreak, 7);
      expect(controller.bestStreak, 7);
      expect(
        controller.achievements.where((a) => a.id == 'seven-days'),
        hasLength(1),
      );
      clock = DateTime(2026, 11, 4);
      await controller.evaluate();
      expect(controller.currentStreak, 0);
      expect(controller.bestStreak, 7);
      expect(controller.earnedXp, 0);
      expect(controller.lostXp, 0);
    },
  );

  test(
    'concurrent saves are serialized before publishing to consumers',
    () async {
      final gate = Completer<void>();
      var count = 0;
      final queued = PlannerController(
        clock: () => clock,
        initial: {},
        persist: (_) async {
          if (++count == 1) await gate.future;
        },
      );
      addTearDown(queued.dispose);
      final first = queued.saveItem(item('a'));
      final second = queued.saveItem(item('b'));
      await Future<void>.value();
      expect(queued.items, isEmpty);
      gate.complete();
      await Future.wait([first, second]);
      expect(queued.items.map((i) => i.id), ['a', 'b']);
    },
  );

  test(
    'single-occurrence reminder form saves replace stale and inherited preferences',
    () async {
      final series = item(
        'remind',
        recurrence: PlannerRecurrence.daily,
        start: 540,
        end: 600,
      );
      await controller.saveItem(series);
      await controller.setReminder(
        id('remind'),
        const PlannerReminder(enabled: true, offsetMinutes: 10),
        entireSeries: true,
      );
      await controller.setReminder(
        id('remind'),
        const PlannerReminder(enabled: true, offsetMinutes: 20),
      );
      await controller.saveItem(
        series.copyWith(reminder: const PlannerReminder()),
        occurrenceDay: clock,
      );
      expect(
        controller.occurrenceById(id('remind'))!.item.reminder.enabled,
        isFalse,
      );
      expect(
        controller
            .occurrences(plannerAddDays(clock, 1))
            .single
            .item
            .reminder
            .offsetMinutes,
        10,
      );
      await controller.saveItem(
        series.copyWith(
          reminder: const PlannerReminder(enabled: true, offsetMinutes: 30),
        ),
        occurrenceDay: clock,
      );
      expect(
        controller.occurrenceById(id('remind'))!.item.reminder.offsetMinutes,
        30,
      );
      expect(
        controller
            .occurrences(plannerAddDays(clock, 1))
            .single
            .item
            .reminder
            .offsetMinutes,
        10,
      );
      expect(controller.exportState['overrides'], hasLength(1));
    },
  );

  test(
    'series reminder form saves apply to all dates and preserve challenge preferences',
    () async {
      final series = item(
        'remind',
        recurrence: PlannerRecurrence.daily,
        start: 540,
        end: 600,
      );
      await controller.saveItem(series);
      await controller.setReminder(
        id('remind'),
        const PlannerReminder(enabled: true, offsetMinutes: 10),
        entireSeries: true,
      );
      await controller.setReminder(
        id('remind', plannerAddDays(clock, 1)),
        const PlannerReminder(enabled: true, offsetMinutes: 20),
      );
      await controller.saveItem(
        series.copyWith(
          title: 'Special occurrence',
          reminder: const PlannerReminder(enabled: true, offsetMinutes: 30),
        ),
        occurrenceDay: clock,
      );
      final instance = await controller.startChallenge(package());
      final challengeTask = id('${instance.id}/move');
      await controller.setReminder(
        challengeTask,
        const PlannerReminder(enabled: true, offsetMinutes: 5),
        entireSeries: true,
      );
      await controller.saveItem(
        series.copyWith(reminder: const PlannerReminder()),
      );
      expect(
        controller.occurrenceById(id('remind'))!.item.reminder.enabled,
        isFalse,
      );
      expect(
        controller
            .occurrenceById(id('remind', plannerAddDays(clock, 1)))!
            .item
            .reminder
            .enabled,
        isFalse,
      );
      expect(
        controller.occurrenceById(id('remind'))!.title,
        'Special occurrence',
      );
      expect(
        controller.occurrenceById(challengeTask)!.item.reminder.offsetMinutes,
        5,
      );
      expect(
        (controller.exportState['reminders'] as Map).keys.where(
          (key) => key == 'remind' || (key as String).startsWith('remind@'),
        ),
        isEmpty,
      );
      await controller.saveItem(
        series.copyWith(
          reminder: const PlannerReminder(enabled: true, offsetMinutes: 45),
        ),
      );
      expect(
        controller.occurrenceById(id('remind'))!.item.reminder.offsetMinutes,
        45,
      );
      expect(
        controller
            .occurrenceById(id('remind', plannerAddDays(clock, 1)))!
            .item
            .reminder
            .offsetMinutes,
        45,
      );
      final restarted = PlannerController(
        clock: () => clock,
        initial: saved,
        persist: (_) async {},
      );
      addTearDown(restarted.dispose);
      expect(
        restarted.occurrenceById(id('remind'))!.item.reminder.offsetMinutes,
        45,
      );
      expect(
        restarted.occurrenceById(challengeTask)!.item.reminder.offsetMinutes,
        5,
      );
      expect(
        restarted.instances.single.snapshot.tasks.single.reminder.enabled,
        isFalse,
      );
    },
  );

  test(
    're-editing a moved occurrence preserves one original identity',
    () async {
      final series = item('class', recurrence: PlannerRecurrence.daily);
      await controller.saveItem(series);
      await controller.saveItem(
        series.copyWith(date: DateTime(2026, 10, 27)),
        occurrenceDay: clock,
      );
      await controller.saveItem(
        series.copyWith(title: 'Changed again', date: DateTime(2026, 10, 28)),
        occurrenceDay: clock,
      );
      expect(controller.occurrences(DateTime(2026, 10, 27)).map((o) => o.id), [
        'class@2026-10-27',
      ]);
      final moved = controller
          .occurrences(DateTime(2026, 10, 28))
          .where((o) => o.id == id('class'))
          .toList();
      expect(moved, hasLength(1));
      expect(moved.single.title, 'Changed again');
      expect(controller.exportState['overrides'], hasLength(1));
      await controller.deleteItem('class', occurrenceDay: clock);
      expect(controller.occurrenceById(id('class')), isNull);
      expect(controller.occurrences(DateTime(2026, 10, 28)), hasLength(1));
    },
  );

  test(
    'persistence maps and occurrence models cannot mutate controller state',
    () async {
      await controller.saveItem(
        item(
          'sequence',
          steps: ['First', 'Second'],
          recurrence: PlannerRecurrence.weekdays,
          weekdays: [1, 2],
        ),
      );
      ((saved['items'] as List).single['steps'] as List).clear();
      ((saved['items'] as List).single['weekdays'] as List).clear();
      expect(controller.items.single.steps, hasLength(2));
      expect(controller.occurrences(clock), hasLength(1));
      final occurrence = controller.occurrences(clock).single;
      occurrence.item.steps.clear();
      expect(controller.items.single.steps, hasLength(2));
      await controller.completeStep(id('sequence'), 0);
      (((saved['records'] as Map)[id('sequence')] as Map)['completedSteps']
              as List)
          .add(99);
      expect(controller.occurrenceById(id('sequence'))!.record.completedSteps, [
        0,
      ]);
      final instance = await controller.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(
              id: 'work',
              title: 'Work',
              dayOffsets: [0],
              steps: ['Prepare', 'Work'],
            ),
          ],
        ),
      );
      ((((saved['instances'] as List).single['snapshot'] as Map)['tasks']
                      as List)
                  .single['steps']
              as List)
          .clear();
      expect(
        controller.instances.single.snapshot.tasks.single.steps,
        hasLength(2),
      );
      await controller.completeStep(id('${instance.id}/work'), 0);
      expect(controller.instances.single.status, ChallengeStatus.active);
    },
  );

  test(
    'amount and sequential requirements both apply in either completion order',
    () async {
      await controller.saveItem(
        item('first', steps: ['Prepare', 'Read'], target: 20, unit: 'pages'),
      );
      await controller.recordAmount(id('first'), 20);
      expect(controller.balance, 0);
      await controller.completeStep(id('first'), 0);
      await controller.completeStep(id('first'), 1);
      expect(controller.balance, 0);
      await controller.saveItem(
        item('second', steps: ['Prepare', 'Read'], target: 20, unit: 'pages'),
      );
      await controller.completeStep(id('second'), 0);
      await controller.completeStep(id('second'), 1);
      expect(controller.balance, 0);
      await controller.recordAmount(id('second'), 20);
      expect(controller.balance, 0);
    },
  );

  test(
    'loaded active snapshots reject changed rules and missing or invalid records',
    () async {
      final instance = await controller.startChallenge(package());
      final negativeReward = controller.exportState;
      ((((negativeReward['instances'] as List).single['snapshot']
                          as Map)['tasks']
                      as List)
                  .single
              as Map)['rewardXp'] =
          -20;
      expect(() => PlannerState.fromMap(negativeReward), throwsStateError);
      final missingRecord = controller.exportState;
      (missingRecord['records'] as Map).remove(id('${instance.id}/move'));
      expect(() => PlannerState.fromMap(missingRecord), throwsStateError);
      final invalidAmount = controller.exportState;
      ((invalidAmount['records'] as Map)[id('${instance.id}/move')]
              as Map)['amount'] =
          -1;
      expect(() => PlannerState.fromMap(invalidAmount), throwsStateError);
      final invalidSteps = controller.exportState;
      ((invalidSteps['records'] as Map)[id('${instance.id}/move')]
          as Map)['completedSteps'] = [
        0,
      ];
      expect(() => PlannerState.fromMap(invalidSteps), throwsStateError);
      final lifecycle = controller.exportState;
      ((lifecycle['instances'] as List).single as Map)['status'] = 'completed';
      expect(() => PlannerState.fromMap(lifecycle), throwsStateError);
      expect(controller.instances.single.status, ChallengeStatus.active);
      expect(controller.balance, 0);
    },
  );

  test(
    'unchanged lifecycle evaluation avoids writes and notification side effects',
    () async {
      var writes = 0;
      var sideEffects = 0;
      final idle = PlannerController(
        clock: () => clock,
        initial: {},
        persist: (_) async {
          writes++;
        },
        afterCommit: () async {
          sideEffects++;
        },
      );
      addTearDown(idle.dispose);
      await idle.evaluate();
      await idle.evaluate();
      expect(writes, 1); // First evaluation enrolls tomorrow's selection.
      expect(sideEffects, 1);
      await idle.startChallenge(package());
      expect(writes, 2);
      clock = DateTime(2026, 10, 28);
      await idle.evaluate();
      await idle.evaluate();
      expect(writes, 3);
      expect(sideEffects, 3);
      expect(idle.instances.single.status, ChallengeStatus.failed);
    },
  );

  test(
    'one transaction uses one clock instant at the challenge deadline',
    () async {
      var time = DateTime(2026, 10, 26, 12);
      var reads = 0;
      final timed = PlannerController(
        clock: () {
          reads++;
          return time;
        },
        initial: {},
        persist: (_) async {},
      );
      addTearDown(timed.dispose);
      final instance = await timed.startChallenge(
        package(
          tasks: const [
            ChallengeTaskDefinition(id: 'work', title: 'Work', dayOffsets: [0]),
          ],
        ),
      );
      reads = 0;
      time = DateTime(2026, 10, 27, 23, 59, 59);
      await timed.complete('${instance.id}/work@2026-10-26');
      expect(reads, 1);
      expect(timed.instances.single.status, ChallengeStatus.completed);
      expect(timed.ledger.map((event) => event.at).toSet(), {time});
    },
  );
}
