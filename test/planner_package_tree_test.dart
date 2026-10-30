import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';

ChallengeTemplate _package(List<ChallengeTaskDefinition> tasks) =>
    ChallengeTemplate(
      id: 'morning',
      name: 'Morning routine',
      rewardMode: ChallengeRewardMode.packageOnly,
      completionXp: 80,
      failurePenalty: 15,
      tasks: tasks,
    );

const _tree = [
  ChallengeTaskDefinition(id: 'wake', title: 'Wake up'),
  ChallengeTaskDefinition(
    id: 'exercise',
    title: 'Exercise',
    type: ChallengeTaskType.group,
  ),
  ChallengeTaskDefinition(
    id: 'push',
    title: 'Push-ups',
    parentId: 'exercise',
  ),
  ChallengeTaskDefinition(
    id: 'strength',
    title: 'Strength',
    parentId: 'exercise',
    type: ChallengeTaskType.group,
  ),
  ChallengeTaskDefinition(
    id: 'pull',
    title: 'Pull-ups',
    parentId: 'strength',
  ),
];

void main() {
  late DateTime now;
  late PlannerController controller;

  setUp(() {
    now = DateTime(2026, 10, 29, 12);
    controller = PlannerController(
      clock: () => now,
      initial: {},
      persist: (_) async {},
      catalog: [],
    );
  });
  tearDown(() => controller.dispose());

  String occurrence(ChallengeInstance instance, String task) =>
      '${instance.id}/$task@2026-10-29';

  test('flexible type needs no time and scheduled type validates its time', () {
    final flexible = _package([
      const ChallengeTaskDefinition(id: 'read', title: 'Read'),
    ]);
    expect(flexible.difficulty, isNull);
    expect(flexible.durationDays, 1);
    expect(flexible.tasks.single.type, ChallengeTaskType.flexible);
    expect(flexible.validate, returnsNormally);
    expect(
      _package([
        const ChallengeTaskDefinition(
          id: 'study',
          title: 'Study',
          type: ChallengeTaskType.scheduled,
        ),
      ]).validate,
      throwsArgumentError,
    );
    expect(
      _package([
        const ChallengeTaskDefinition(
          id: 'study',
          title: 'Study',
          type: ChallengeTaskType.scheduled,
          startMinute: 960,
          durationMinutes: 120,
        ),
      ]).validate,
      returnsNormally,
    );
  });

  test('parents derive nested progress and cannot complete children', () async {
    final instance = await controller.startChallenge(_package(_tree));
    expect(controller.occurrences(now).length, 3);
    expect(controller.groupTotalCount(instance, 'exercise'), 2);
    expect(controller.groupProgress(instance, 'exercise'), 0);
    expect(controller.challengeTotalCount(instance), 3);
    expect(
      () => controller.complete(occurrence(instance, 'exercise')),
      throwsStateError,
    );
    await controller.complete(occurrence(instance, 'push'));
    expect(controller.groupProgress(instance, 'exercise'), .5);
    expect(
      controller.groupStatus(instance, 'strength'),
      CompletionStatus.pending,
    );
    expect(controller.balance, 0);
    expect(controller.ledger, isEmpty);
    await controller.complete(occurrence(instance, 'pull'));
    expect(
      controller.groupStatus(instance, 'exercise'),
      CompletionStatus.completed,
    );
    expect(controller.instances.single.status, ChallengeStatus.active);
    await controller.complete(occurrence(instance, 'wake'));
    expect(controller.instances.single.status, ChallengeStatus.completed);
    expect(controller.balance, 80);
    expect(controller.ledger.single.type, 'challenge_completion');
    final records = controller.exportState['records'] as Map;
    expect(records.containsKey(occurrence(instance, 'exercise')), isFalse);
    expect(records.containsKey(occurrence(instance, 'strength')), isFalse);
    await Future.wait([
      controller.complete(occurrence(instance, 'wake')),
      controller.complete(occurrence(instance, 'pull')),
      controller.evaluate(),
    ]);
    expect(controller.balance, 80);
    expect(controller.ledger.length, 1);
    expect(
      PlannerState.fromMap(controller.exportState).instances.single.status,
      ChallengeStatus.completed,
    );
  });

  test(
    'optional group does not make its descendants package requirements',
    () async {
      final instance = await controller.startChallenge(
        _package([
          const ChallengeTaskDefinition(id: 'required', title: 'Required'),
          const ChallengeTaskDefinition(
            id: 'optional',
            title: 'Extra',
            type: ChallengeTaskType.group,
            mandatory: false,
          ),
          const ChallengeTaskDefinition(
            id: 'child',
            title: 'Extra child',
            parentId: 'optional',
          ),
        ]),
      );
      expect(controller.challengeTotalCount(instance), 1);
      await controller.complete(occurrence(instance, 'required'));
      expect(controller.instances.single.status, ChallengeStatus.completed);
      expect(
        controller.groupStatus(instance, 'optional'),
        CompletionStatus.pending,
      );
      expect(controller.balance, 80);
    },
  );

  test(
    'skipped required child prevents completion and fails once at deadline',
    () async {
      final instance = await controller.startChallenge(_package(_tree));
      await controller.skip(occurrence(instance, 'push'));
      await controller.complete(occurrence(instance, 'pull'));
      await controller.complete(occurrence(instance, 'wake'));
      expect(
        controller.groupStatus(instance, 'exercise'),
        CompletionStatus.skipped,
      );
      expect(controller.instances.single.status, ChallengeStatus.active);
      expect(
        controller.skipPenaltyFor(
          controller.occurrenceById(occurrence(instance, 'push'))!,
        ),
        0,
      );
      expect(controller.ledger, isEmpty);
      now = instance.deadline;
      await controller.evaluate();
      await controller.evaluate();
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(
        controller.ledger.where((e) => e.type == 'challenge_failure').length,
        1,
      );
      expect(
        controller.ledger.where((e) => e.type == 'challenge_completion'),
        isEmpty,
      );
      expect(controller.balance, 0);
      expect(
        () => PlannerState.fromMap(controller.exportState),
        returnsNormally,
      );
    },
  );

  test('deadline wins against the final nested completion', () async {
    final instance = await controller.startChallenge(_package(_tree));
    await controller.complete(occurrence(instance, 'push'));
    await controller.complete(occurrence(instance, 'wake'));
    now = instance.deadline;
    await expectLater(
      controller.complete(occurrence(instance, 'pull')),
      throwsStateError,
    );
    expect(controller.instances.single.status, ChallengeStatus.failed);
    expect(controller.groupCompletedCount(instance, 'exercise'), 1);
    expect(
      controller.ledger.where((e) => e.type == 'challenge_completion'),
      isEmpty,
    );
  });

  test(
    'hierarchy validates missing parents, leaf parents, cycles and empty groups',
    () {
      for (final tasks in <List<ChallengeTaskDefinition>>[
        [
          const ChallengeTaskDefinition(
            id: 'a',
            title: 'A',
            parentId: 'missing',
          ),
        ],
        [
          const ChallengeTaskDefinition(id: 'a', title: 'A'),
          const ChallengeTaskDefinition(id: 'b', title: 'B', parentId: 'a'),
        ],
        [
          const ChallengeTaskDefinition(
            id: 'a',
            title: 'A',
            type: ChallengeTaskType.group,
          ),
        ],
        [
          const ChallengeTaskDefinition(
            id: 'a',
            title: 'A',
            type: ChallengeTaskType.group,
            parentId: 'b',
          ),
          const ChallengeTaskDefinition(
            id: 'b',
            title: 'B',
            type: ChallengeTaskType.group,
            parentId: 'a',
          ),
        ],
        [
          const ChallengeTaskDefinition(
            id: 'a',
            title: 'A',
            type: ChallengeTaskType.group,
          ),
          const ChallengeTaskDefinition(
            id: 'b',
            title: 'B',
            mandatory: false,
            parentId: 'a',
          ),
        ],
      ]) {
        expect(_package(tasks).validate, throwsArgumentError);
      }
    },
  );

  test(
    'templates preserve nested relationships and sibling order through restart',
    () async {
      final original = _package(_tree);
      await controller.saveTemplate(original);
      final reordered = original.copyWith(
        tasks: [
          _tree[0],
          _tree[1],
          _tree[3],
          _tree[4],
          _tree[2],
        ],
      );
      await controller.saveTemplate(reordered);
      final instance = await controller.startChallenge(reordered);
      await controller.complete(occurrence(instance, 'pull'));
      final state =
          jsonDecode(jsonEncode(controller.exportState))
              as Map<String, dynamic>;
      controller.dispose();
      controller = PlannerController(
        clock: () => now,
        initial: state,
        persist: (_) async {},
      );
      expect(
        controller.templates.single.childrenOf('exercise').map((t) => t.id),
        ['strength', 'push'],
      );
      expect(
        controller.templates.single.childrenOf('strength').single.id,
        'pull',
      );
      expect(
        controller.groupProgress(controller.instances.single, 'exercise'),
        .5,
      );
      await controller.saveTemplate(
        original.copyWith(
          tasks: [const ChallengeTaskDefinition(id: 'new', title: 'Changed')],
        ),
      );
      expect(
        controller.instances.single.snapshot
            .childrenOf('exercise')
            .map((t) => t.id),
        ['strength', 'push'],
      );
    },
  );

  test(
    'dependencies cannot target groups or give groups task prerequisites',
    () {
      final group = const ChallengeTaskDefinition(
        id: 'group',
        title: 'Group',
        type: ChallengeTaskType.group,
      );
      final child = const ChallengeTaskDefinition(
        id: 'child',
        title: 'Child',
        parentId: 'group',
      );
      expect(
        _package([
          group,
          child.copyWith(dependencies: ['group']),
        ]).validate,
        throwsArgumentError,
      );
      expect(
        _package([
          group.copyWith(dependencies: ['child']),
          child,
        ]).validate,
        throwsArgumentError,
      );
    },
  );

  test(
    'custom category reuse, rename and deletion keep templates and snapshots safe',
    () async {
      final category = await controller.saveCategory(name: '  Health  ');
      final template = _package(_tree).copyWith(categoryId: category.id);
      await controller.saveTemplate(template);
      final instance = await controller.startChallenge(
        controller.templates.single,
      );
      await controller.saveCategory(id: category.id, name: 'Movement');
      expect(controller.categories.single.id, category.id);
      expect(controller.templates.single.categoryName, 'Movement');
      expect(controller.instances.single.snapshot.categoryName, 'Health');
      expect(instance.snapshot.categoryName, 'Health');
      await expectLater(
        controller.saveCategory(name: 'movement'),
        throwsArgumentError,
      );
      await controller.deleteCategory(category.id);
      expect(controller.categories, isEmpty);
      expect(controller.templates.single.categoryId, isNull);
      expect(controller.templates.single.categoryName, 'Movement');
      expect(controller.instances.single.snapshot.categoryId, category.id);
      expect(
        () => PlannerState.fromMap(controller.exportState),
        returnsNormally,
      );
    },
  );

  test(
    'schema 2 migration preserves history and captured economics while normalizing templates',
    () async {
      final legacy = ChallengeTemplate(
        id: 'legacy',
        name: 'Legacy',
        difficulty: ChallengeDifficulty.hard,
        durationDays: 2,
        completionXp: 50,
        tasks: const [
          ChallengeTaskDefinition(
            id: 'a',
            title: 'A',
            dayOffsets: [0, 1],
            rewardXp: 12,
            skipPenalty: 3,
          ),
        ],
      );
      await controller.saveItem(
        PlannerItem(id: 'routine', title: 'Routine', date: now),
      );
      await controller.complete('routine@2026-10-29');
      await controller.saveTemplate(legacy);
      final instance = await controller.startChallenge(legacy);
      await controller.complete(occurrence(instance, 'a'));
      final old = controller.exportState;
      old['schemaVersion'] = 2;
      old.remove('categories');
      for (final template in [
        ...(old['templates'] as List).cast<Map>(),
        ...(old['instances'] as List).map((i) => (i as Map)['snapshot'] as Map),
      ]) {
        template.remove('rewardMode');
        template.remove('categoryId');
        template.remove('categoryName');
        for (final task in template['tasks'] as List) {
          (task as Map).remove('type');
          task.remove('parentId');
        }
      }
      final ledgerBefore = jsonEncode(old['ledger']);
      final recordsBefore = jsonEncode(old['records']);
      final migrated = PlannerState.fromMap(old);
      expect(
        migrated.templates.single.rewardMode,
        ChallengeRewardMode.packageOnly,
      );
      expect(migrated.templates.single.completionXp, 74);
      expect(migrated.templates.single.durationDays, 2);
      expect(migrated.templates.single.tasks.single.dayOffsets, [0, 1]);
      expect(
        migrated.instances.single.snapshot.rewardMode,
        ChallengeRewardMode.legacyPerTask,
      );
      expect(migrated.instances.single.snapshot.completionXp, 50);
      expect(migrated.instances.single.snapshot.tasks.single.rewardXp, 12);
      expect(jsonEncode(migrated.toMap()['ledger']), ledgerBefore);
      expect(jsonEncode(migrated.toMap()['records']), recordsBefore);
      expect(migrated.items.single.id, 'routine');
      final once = jsonEncode(migrated.toMap());
      expect(jsonEncode(PlannerState.fromMap(migrated.toMap()).toMap()), once);
    },
  );

  test('built-in seeded templates use package rewards for new commitments', () {
    final seeded = PlannerController(
      clock: () => now,
      initial: {},
      persist: (_) async {},
    );
    expect(seeded.templates, isNotEmpty);
    expect(
      seeded.templates.every(
        (t) => t.rewardMode == ChallengeRewardMode.packageOnly,
      ),
      isTrue,
    );
    seeded.dispose();
  });

  test(
    'package skip cost is captured, floored and recorded once per leaf',
    () async {
      controller.dispose();
      controller = PlannerController(
        clock: () => now,
        initial: PlannerState(
          templatesInitialized: true,
          ledger: [
            XpTransaction(
              id: 'old',
              reason: 'Preserved XP',
              change: 10,
              type: 'legacy_balance',
              at: now,
              idempotencyKey: 'old',
            ),
          ],
        ).toMap(),
        persist: (_) async {},
      );
      final template = _package(_tree).copyWith(skipPenalty: 7);
      await controller.saveTemplate(template);
      final instance = await controller.startChallenge(template);
      await controller.saveTemplate(template.copyWith(skipPenalty: 99));
      expect(controller.instances.single.snapshot.skipPenalty, 7);
      expect(
        controller.skipPenaltyFor(
          controller.occurrenceById(occurrence(instance, 'push'))!,
        ),
        7,
      );
      await Future.wait([
        controller.skip(occurrence(instance, 'push')),
        controller.skip(occurrence(instance, 'push')),
      ]);
      expect(controller.balance, 3);
      expect(controller.instances.single.status, ChallengeStatus.active);
      final saved = controller.exportState;
      controller.dispose();
      controller = PlannerController(
        clock: () => now,
        initial: saved,
        persist: (_) async {},
      );
      await controller.skip(occurrence(instance, 'push'));
      await controller.skip(occurrence(instance, 'pull'));
      expect(controller.balance, 0);
      expect(
        controller.ledger
            .where((e) => e.type == 'task_skip')
            .map((e) => e.change),
        [-7, -3],
      );
      expect(
        controller.groupStatus(instance, 'exercise'),
        CompletionStatus.skipped,
      );
      expect(controller.instances.single.status, ChallengeStatus.active);
      await expectLater(
        controller.skip(occurrence(instance, 'exercise')),
        throwsStateError,
      );
      await controller.complete(occurrence(instance, 'wake'));
      now = instance.deadline;
      await controller.evaluate();
      await controller.evaluate();
      expect(controller.instances.single.status, ChallengeStatus.failed);
      expect(
        controller.ledger
            .where((e) => e.type == 'challenge_failure')
            .single
            .change,
        0,
      );
      expect(
        controller.ledger.where((e) => e.type == 'challenge_completion'),
        isEmpty,
      );
      expect(
        () => PlannerState.fromMap(controller.exportState),
        returnsNormally,
      );
    },
  );

  test(
    'explicit zero skip cost still creates an idempotent audit transaction',
    () async {
      final instance = await controller.startChallenge(
        _package(_tree).copyWith(skipPenalty: 0),
      );
      await controller.skip(occurrence(instance, 'push'));
      await controller.skip(occurrence(instance, 'push'));
      expect(controller.ledger.single.change, 0);
      expect(
        controller.ledger.single.idempotencyKey,
        'skip:${occurrence(instance, 'push')}',
      );
      final invalid = controller.exportState;
      invalid['ledger'] = [];
      expect(() => PlannerState.fromMap(invalid), throwsStateError);
    },
  );

  test(
    'schema 3 package-only skips retain their original absent accounting',
    () async {
      await controller.saveTemplate(_package(_tree));
      final instance = await controller.startChallenge(_package(_tree));
      await controller.skip(occurrence(instance, 'push'));
      final old = controller.exportState;
      old['schemaVersion'] = 3;
      for (final template in [
        ...(old['templates'] as List).cast<Map>(),
        ...(old['instances'] as List).map((i) => (i as Map)['snapshot'] as Map),
      ]) {
        template.remove('skipPenalty');
      }
      final migrated = PlannerState.fromMap(old);
      expect(migrated.templates.single.skipPenalty, 0);
      expect(migrated.instances.single.snapshot.skipPenalty, isNull);
      expect(
        migrated.records[occurrence(instance, 'push')]!.status,
        CompletionStatus.skipped,
      );
      expect(migrated.ledger, isEmpty);
      controller.dispose();
      controller = PlannerController(
        clock: () => now,
        initial: migrated.toMap(),
        persist: (_) async {},
      );
      await controller.skip(occurrence(instance, 'pull'));
      expect(controller.ledger, isEmpty);
      expect(controller.instances.single.status, ChallengeStatus.active);
    },
  );

  test(
    'new skip accounting does not change future availability or routines',
    () async {
      final instance = await controller.startChallenge(
        _package(_tree).copyWith(skipPenalty: 8),
        startDate: plannerAddDays(now, 1),
      );
      await expectLater(
        controller.skip('${instance.id}/push@2026-10-30'),
        throwsStateError,
      );
      await controller.saveItem(
        PlannerItem(id: 'routine', title: 'Routine', date: now),
      );
      await controller.skip('routine@2026-10-29');
      expect(controller.ledger, isEmpty);
      expect(
        _package(_tree).copyWith(skipPenalty: -1).validate,
        throwsArgumentError,
      );
    },
  );
}
