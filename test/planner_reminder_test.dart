import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/planner_reminder_schedule.dart';

void main() {
  final day = DateTime(2026, 10, 29);
  final now = DateTime(2026, 10, 29, 8);

  PlannerOccurrence occurrence({
    String id = 'activity@2026-10-29',
    DateTime? date,
    int? start = 10 * 60,
    PlannerReminder reminder = const PlannerReminder(enabled: true),
    CompletionStatus status = CompletionStatus.pending,
    String? challenge,
    DateTime? validUntil,
  }) => PlannerOccurrence(
    id: id,
    day: date ?? day,
    item: PlannerItem(
      id: 'activity',
      title: 'Study',
      description: 'Review lecture notes',
      date: date ?? day,
      startMinute: start,
      endMinute: start == null ? null : start + 60,
      reminder: reminder,
    ),
    record: CompletionRecord(status: status),
    challengeId: challenge,
    validUntil: validUntil,
  );

  PlannerReminderRequest request(String id, {DateTime? at}) =>
      PlannerReminderRequest(
        occurrenceId: id,
        title: 'Study',
        body: '',
        fireAt: at ?? DateTime(2026, 10, 29, 10),
      );

  group('concrete planner reminder generation', () {
    test('ended challenge tasks cannot be revived by a stored snooze', () {
      final ended = occurrence(
        challenge: 'ended-package',
        start: 7 * 60,
        validUntil: now,
      );
      final planned = PlannerReminderSchedule.build(
        [ended],
        now: now,
        snoozes: {ended.id: now.add(const Duration(minutes: 10))},
      );
      expect(planned, isEmpty);
    });

    test('challenge reminders and snoozes must precede the deadline', () {
      final deadline = DateTime(2026, 10, 29, 10);
      final active = occurrence(
        challenge: 'active-package',
        validUntil: deadline,
      );
      expect(PlannerReminderSchedule.build([active], now: now), isEmpty);
      expect(
        PlannerReminderSchedule.build(
          [active],
          now: now,
          snoozes: {active.id: deadline.add(const Duration(minutes: 1))},
        ),
        isEmpty,
      );
      final before = PlannerReminderSchedule.build(
        [active],
        now: now,
        snoozes: {active.id: deadline.subtract(const Duration(minutes: 1))},
      );
      expect(
        before.single.fireAt,
        deadline.subtract(const Duration(minutes: 1)),
      );
    });

    test('only pending enabled reminders in the future are scheduled', () {
      final planned = PlannerReminderSchedule.build([
        occurrence(id: 'pending'),
        occurrence(id: 'done', status: CompletionStatus.completed),
        occurrence(id: 'skipped', status: CompletionStatus.skipped),
        occurrence(id: 'past', start: 7 * 60),
        occurrence(id: 'disabled', reminder: const PlannerReminder()),
        occurrence(id: 'unscheduled', start: null),
      ], now: now);
      expect(planned.map((r) => r.occurrenceId), ['pending']);
      expect(planned.single.fireAt, DateTime(2026, 10, 29, 10));
    });

    test(
      'standalone tasks use their independently configured reminder time',
      () {
        final planned = PlannerReminderSchedule.build([
          occurrence(
            start: null,
            reminder: const PlannerReminder(
              enabled: true,
              minute: 18 * 60 + 30,
            ),
          ),
        ], now: now);
        expect(planned.single.fireAt, DateTime(2026, 10, 29, 18, 30));
      },
    );

    test('scheduled activities honor an explicitly selected reminder time', () {
      final planned = PlannerReminderSchedule.build([
        occurrence(
          start: 10 * 60,
          reminder: const PlannerReminder(enabled: true, minute: 9 * 60 + 45),
        ),
      ], now: now);
      expect(planned.single.fireAt, DateTime(2026, 10, 29, 9, 45));
    });

    test('lead time can cross midnight into the preceding date', () {
      final planned = PlannerReminderSchedule.build([
        occurrence(
          date: DateTime(2026, 10, 30),
          start: 15,
          reminder: const PlannerReminder(enabled: true, offsetMinutes: 30),
        ),
      ], now: now);
      expect(planned.single.fireAt, DateTime(2026, 10, 29, 23, 45));
    });

    test(
      'recurring days get distinct notifications; repeated input is deduplicated',
      () {
        final monday = occurrence(
          id: 'university@2026-11-02',
          date: DateTime(2026, 11, 2),
        );
        final thursday = occurrence(
          id: 'university@2026-11-05',
          date: DateTime(2026, 11, 5),
        );
        final planned = PlannerReminderSchedule.build([
          monday,
          thursday,
          monday,
          thursday,
        ], now: now);
        expect(planned.length, 2);
        expect(planned.map((r) => r.occurrenceId).toSet().length, 2);
        expect(planned.first.fireAt.weekday, DateTime.monday);
        expect(planned.last.fireAt.weekday, DateTime.thursday);
      },
    );

    test('challenge tasks retain their provenance and configured sound', () {
      final planned = PlannerReminderSchedule.build([
        occurrence(
          challenge: 'instance-1',
          reminder: const PlannerReminder(
            enabled: true,
            sound: 'android.resource://com.streak.app/raw/levelup_soft',
            vibrate: false,
          ),
        ),
      ], now: now);
      expect(planned.single.body, startsWith('Challenge task'));
      final restored = PlannerReminderRequest.fromMap(planned.single.toMap());
      expect(restored.sound, planned.single.sound);
      expect(restored.vibrate, false);
      expect(restored.fireAt, planned.single.fireAt);
    });

    test(
      'persisted snoozes survive rebuilding an already-fired occurrence',
      () {
        final fired = occurrence(start: 7 * 60);
        final planned = PlannerReminderSchedule.build(
          [fired],
          now: now,
          snoozes: {
            fired.id: DateTime(2026, 10, 29, 8, 10),
          },
        );
        expect(planned.single.fireAt, DateTime(2026, 10, 29, 8, 10));
        expect(
          PlannerReminderSchedule.build(
            [
              occurrence(start: 7 * 60, status: CompletionStatus.completed),
            ],
            now: now,
            snoozes: {fired.id: DateTime(2026, 10, 29, 8, 10)},
          ),
          isEmpty,
        );
      },
    );
  });

  test(
    'serialized delivery moments retain the instant across timezone offsets',
    () {
      final instant = DateTime.parse('2026-10-29T10:00:00+03:00');
      final original = request('a', at: instant);
      final restored = PlannerReminderRequest.fromMap(original.toMap());
      expect(restored.fireAt.isAtSameMomentAs(instant), isTrue);
      expect(original.toMap()['fireAt'], '2026-10-29T07:00:00.000Z');
    },
  );

  group('notification identifiers', () {
    test(
      'identifiers are deterministic, bounded, and stable after adding another task',
      () {
        final first = PlannerReminderSchedule.allocateIds(['a', 'b']);
        expect(PlannerReminderSchedule.allocateIds(['b', 'a', 'a']), first);
        final next = PlannerReminderSchedule.allocateIds([
          'a',
          'b',
          'c',
        ], previous: first);
        expect(next['a'], first['a']);
        expect(next['b'], first['b']);
        for (final id in next.values) {
          expect(id, inInclusiveRange(1200000000, 1999999999));
        }
        expect(next.values.toSet().length, next.length);
      },
    );

    test(
      'a corrupted duplicate registry is repaired without duplicate IDs',
      () {
        final ids = PlannerReminderSchedule.allocateIds(
          ['a', 'b'],
          previous: {
            'a': 1200000001,
            'b': 1200000001,
          },
        );
        expect(ids['a'], 1200000001);
        expect(ids.values.toSet().length, 2);
      },
    );
  });

  group('platform reconciliation', () {
    test(
      'refresh replaces the same platform slots; editing and deleting cancel obsolete reminders',
      () async {
        final pending = <int, PlannerReminderRequest>{};
        var ids = <String, int>{};
        Future<PlannerReminderSyncResult> sync(
          List<PlannerReminderRequest> requests,
        ) async {
          final result = await PlannerReminderSync.apply(
            requests: requests,
            previousIds: ids,
            permissionGranted: true,
            exact: true,
            cancel: (id) async {
              pending.remove(id);
            },
            schedule: (id, request, _) async {
              pending[id] = request;
            },
          );
          ids = result.ids;
          return result;
        }

        await sync([request('a'), request('b')]);
        final originalA = ids['a'];
        await sync([request('a'), request('b'), request('a')]);
        expect(pending.length, 2);
        final changed = DateTime(2026, 10, 29, 15);
        await sync([request('a', at: changed)]);
        expect(pending.length, 1);
        expect(ids['a'], originalA);
        expect(pending.values.single.fireAt, changed);
        await sync([]);
        expect(pending, isEmpty);
      },
    );

    test(
      'denied notification permission cancels old slots and never schedules',
      () async {
        final cancelled = <int>[];
        final result = await PlannerReminderSync.apply(
          requests: [request('a')],
          previousIds: {'a': 1200000001},
          pendingIds: {1200000001, 1200000002},
          permissionGranted: false,
          exact: false,
          cancel: (id) async {
            cancelled.add(id);
          },
          schedule: (_, _, _) async {
            fail('Denied notifications cannot schedule');
          },
        );
        expect(cancelled.toSet(), {1200000001, 1200000002});
        expect(result.scheduled, 0);
        expect(result.ids, isEmpty);
        expect(result.message, contains('disabled'));
      },
    );

    test(
      'exact access denial uses approximate scheduling and exposes the limitation',
      () async {
        final modes = <bool>[];
        final result = await PlannerReminderSync.apply(
          requests: [request('a')],
          previousIds: {},
          permissionGranted: true,
          exact: false,
          cancel: (_) async {},
          schedule: (_, _, exact) async {
            modes.add(exact);
          },
        );
        expect(modes, [false]);
        expect(result.scheduled, 1);
        expect(result.message, contains('approximate timing'));
      },
    );

    test(
      'backend failures are reported without claiming successful scheduling',
      () async {
        final result = await PlannerReminderSync.apply(
          requests: [request('a')],
          previousIds: {},
          permissionGranted: true,
          exact: true,
          cancel: (_) async {},
          schedule: (_, _, _) async {
            throw StateError('Alarm service unavailable');
          },
        );
        expect(result.scheduled, 0);
        expect(result.errors, hasLength(1));
        expect(result.message, contains('Alarm service unavailable'));
      },
    );
  });
}
