import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/services/backup_archive.dart';
import 'package:streak/services/backup_service.dart';

import 'support/app_harness.dart';

final _now = DateTime(2026, 10, 29, 12);

ChallengeTemplate _package() => const ChallengeTemplate(
  id: 'test-package',
  name: 'A measured day',
  description: 'Two required tasks',
  difficulty: ChallengeDifficulty.medium,
  durationDays: 1,
  completionXp: 40,
  tasks: [
    ChallengeTaskDefinition(
      id: 'a',
      title: 'Focus',
      dayOffsets: [0],
      startMinute: 13 * 60,
      durationMinutes: 30,
      rewardXp: 20,
      steps: ['Prepare', 'Focus'],
    ),
    ChallengeTaskDefinition(
      id: 'b',
      title: 'Review',
      dayOffsets: [0],
      startMinute: 14 * 60,
      durationMinutes: 15,
      skipPenalty: 5,
    ),
  ],
);

Future<PlannerController> _seedPlanner() async {
  final planner = PlannerController(clock: () => _now);
  await planner.saveItem(
    PlannerItem(
      id: 'university',
      title: 'University',
      date: plannerDay(_now),
      startMinute: 8 * 60,
      endMinute: 14 * 60,
      recurrence: PlannerRecurrence.weekdays,
      weekdays: [1, 2, 4],
      reminder: const PlannerReminder(enabled: true, minute: 7 * 60 + 45),
    ),
  );
  await planner.saveItem(
    PlannerItem(id: 'notes', title: 'Read notes', date: plannerDay(_now)),
  );
  await planner.complete('notes@2026-10-29');
  final package = await planner.startChallenge(_package());
  await planner.completeStep('${package.id}/a@2026-10-29', 0);
  await planner.completeStep('${package.id}/a@2026-10-29', 1);
  await planner.skip('${package.id}/b@2026-10-29');
  return planner;
}

void main() {
  useEmptyStore();

  test(
    'additive planner initialization preserves existing Streak data',
    () async {
      final habit = testHabit(
        id: 'legacy',
        name: 'Existing habit',
        done: lastDays(4),
      );
      await LocalStore.writeHabit(habit);
      await LocalStore.writeTodo(
        Todo(id: 'legacy-todo', text: 'Existing task', createdAt: _now),
      );
      await LocalStore.writeSetting('profileName', 'Existing profile');
      final planner = PlannerController(clock: () => _now);
      await planner.evaluate();
      expect(planner.items, isEmpty);
      expect(planner.ledger, isEmpty);
      expect(LocalStore.readHabits()['legacy']!.toMap(), habit.toMap());
      expect(LocalStore.readTodos().single.title, 'Existing task');
      expect(LocalStore.setting('profileName', ''), 'Existing profile');
      planner.dispose();
    },
  );

  test(
    'schedule, snapshots, records and ledger survive an actual Hive restart',
    () async {
      final original = await _seedPlanner();
      final before = jsonEncode(original.exportState);
      original.dispose();
      await coldStart();
      final restored = PlannerController(clock: () => _now);
      expect(jsonEncode(restored.exportState), before);
      expect(restored.balance, 15);
      expect(restored.instances.single.status, ChallengeStatus.active);
      expect(restored.occurrences(_now).where((o) => o.isChallenge).length, 2);
      expect(restored.items.first.reminder.minute, 465);
      await restored.complete('notes@2026-10-29');
      final skipped = restored
          .occurrences(_now)
          .firstWhere((o) => o.record.status == CompletionStatus.skipped);
      await restored.skip(skipped.id);
      expect(restored.balance, 15);
      expect(restored.ledger.length, 2);
      restored.dispose();
    },
  );

  test(
    'nested package categories, order and derived progress survive Hive restart',
    () async {
      final planner = PlannerController(clock: () => _now);
      final category = await planner.saveCategory(name: 'Health');
      final template = ChallengeTemplate(
        id: 'nested',
        name: 'Movement',
        categoryId: category.id,
        completionXp: 70,
        failurePenalty: 10,
        rewardMode: ChallengeRewardMode.packageOnly,
        tasks: const [
          ChallengeTaskDefinition(
            id: 'group',
            title: 'Strength',
            type: ChallengeTaskType.group,
          ),
          ChallengeTaskDefinition(
            id: 'pull',
            title: 'Pull-ups',
            parentId: 'group',
          ),
          ChallengeTaskDefinition(
            id: 'push',
            title: 'Push-ups',
            parentId: 'group',
          ),
        ],
      );
      await planner.saveTemplate(template);
      final instance = await planner.startChallenge(template);
      await planner.complete('${instance.id}/pull@2026-10-29');
      final before = jsonEncode(planner.exportState);
      planner.dispose();
      await coldStart();
      final restored = PlannerController(clock: () => _now);
      expect(jsonEncode(restored.exportState), before);
      expect(restored.categories.single.toMap(), category.toMap());
      final restoredTemplate = restored.templates.firstWhere(
        (t) => t.id == 'nested',
      );
      expect(restoredTemplate.childrenOf('group').map((t) => t.id), [
        'pull',
        'push',
      ]);
      expect(restored.groupProgress(restored.instances.single, 'group'), .5);
      expect(restored.ledger, isEmpty);
      await restored.complete('${instance.id}/push@2026-10-29');
      expect(restored.balance, 70);
      expect(restored.instances.single.status, ChallengeStatus.completed);
      expect(restored.ledger.single.type, 'challenge_completion');
      restored.dispose();
    },
  );

  test(
    'production ZIP backup and restore preserve complete planner history',
    () async {
      final planner = await _seedPlanner();
      final expected = jsonEncode(planner.exportState);
      final dir = await Directory.systemTemp.createTemp('levelup_backup_test_');
      try {
        final zip = '${dir.path}/backup.zip';
        await BackupArchive.pack(BackupService.snapshot([]), zip);
        final raw = await BackupArchive.unpack(zip, dir.path);
        expect(raw, isNotNull);
        final data = BackupService.parse(raw!);
        expect(data.hasPlanner, isTrue);
        expect(data.isEmpty, isFalse);
        await LocalStore.wipeEverything();
        final habits = HabitsController();
        await habits.restoreBackup(data, replace: true);
        habits.dispose();
        await coldStart();
        final restored = PlannerController(clock: () => _now);
        expect(jsonEncode(restored.exportState), expected);
        expect(restored.balance, 15);
        expect(restored.ledger.map((e) => e.idempotencyKey).toSet().length, 2);
        restored.dispose();
      } finally {
        planner.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  test('legacy backup restore preserves a newer planner aggregate', () async {
    final planner = await _seedPlanner();
    final before = jsonEncode(planner.exportState);
    final legacy = BackupService.parse(
      jsonEncode({
        'habits': [testHabit(id: 'old', name: 'Old backup').toMap()],
      }),
    );
    final habits = HabitsController();
    await habits.restoreBackup(legacy, replace: true);
    expect(jsonEncode(LocalStore.settingMap('levelUpState')), before);
    expect(LocalStore.readHabits().containsKey('old'), isTrue);
    habits.dispose();
    planner.dispose();
  });

  test(
    'unsafe planner merge is rejected before changing any content',
    () async {
      final planner = await _seedPlanner();
      final payload = BackupService.snapshot([]);
      payload['todos'] = [
        Todo(
          id: 'incoming',
          text: 'Must not be imported',
          createdAt: _now,
        ).toMap(),
      ];
      final data = BackupService.parse(jsonEncode(payload));
      final before = jsonEncode(planner.exportState);
      final habits = HabitsController();
      await expectLater(habits.restoreBackup(data), throwsStateError);
      expect(LocalStore.readTodos(), isEmpty);
      expect(jsonEncode(LocalStore.settingMap('levelUpState')), before);
      habits.dispose();
      planner.dispose();
    },
  );

  test(
    'unknown planner schema is reported without overwriting saved data',
    () async {
      final unsupported = {'schemaVersion': 999, 'future': 'keep this'};
      await LocalStore.writeSetting('levelUpState', unsupported);
      expect(() => PlannerController(), throwsStateError);
      expect(LocalStore.settingMap('levelUpState'), unsupported);
      expect(
        () => BackupService.parse(
          jsonEncode({
            'habits': [],
            'settings': {'levelUpState': unsupported},
          }),
        ),
        throwsStateError,
      );
      expect(LocalStore.settingMap('levelUpState'), unsupported);
    },
  );
}
