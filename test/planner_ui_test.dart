import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/pages/level_up_shell.dart';
import 'package:streak/features/planner/pages/planner_challenges_page.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';
import 'package:streak/features/planner/pages/planner_backup.dart';
import 'package:streak/features/planner/pages/planner_settings_page.dart';
import 'package:streak/features/planner/pages/cloud_account_page.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'package:streak/features/planner/widgets/google_logo.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_sync_controller.dart';
import 'package:streak/services/planner_import.dart';
import 'support/app_harness.dart';
import 'cloud_sync_controller_test.dart'
    show FakeCloudApi, MemoryCloudCache, MemorySessions;

final _now = DateTime(2026, 10, 29, 12);
PlannerController _controller() => PlannerController(
  initial: {},
  clock: () => _now,
  persist: (_) async {},
  catalog: [],
);
Future<void> _refresh(PlannerController c) => c.evaluate();

/// The schedule's vertical day list; each day also has a sideways lane view.
final _timelineScroll = find
    .descendant(
      of: find.byKey(const PageStorageKey('timeline-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300, maxScrolls: 30);
  }
  await tester.ensureVisible(finder);
  // The scroll applies on the next frame; tap after it lands.
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ChallengeTemplate _package() => const ChallengeTemplate(
  id: 'hard-workout',
  name: 'Hard Workout',
  description: '',
  difficulty: ChallengeDifficulty.hard,
  durationDays: 1,
  completionXp: 30,
  tasks: [
    ChallengeTaskDefinition(
      id: 'warmup',
      title: 'Warm-up',
      dayOffsets: [0],
      rewardXp: 10,
      skipPenalty: 5,
      steps: ['Prepare', 'Move'],
    ),
    ChallengeTaskDefinition(
      id: 'run',
      title: 'Running',
      dayOffsets: [0],
      startMinute: 17 * 60,
      durationMinutes: 60,
      rewardXp: 20,
      skipPenalty: 7,
    ),
    ChallengeTaskDefinition(
      id: 'stretch',
      title: 'Stretching',
      dayOffsets: [0],
      rewardXp: 5,
      skipPenalty: 3,
    ),
  ],
);

void main() {
  useEmptyStore();
  testWidgets(
    'Schedule lands on one continuous timeline with three destinations',
    (tester) async {
      final c = _controller();
      await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
      expect(find.byType(PlannerTimeline), findsOneWidget);
      expect(
        find.byKey(const PageStorageKey('timeline-scroll')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-return-today')),
        findsNothing,
      );
      expect(find.text('Daily progress'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      final fourthDay = find.byKey(const ValueKey('timeline-day-2026-11-02'));
      await tester.scrollUntilVisible(
        fourthDay,
        500,
        maxScrolls: 40,
        scrollable: _timelineScroll,
      );
      await tester.ensureVisible(fourthDay);
      await tester.pumpAndSettle();
      expect(fourthDay, findsOneWidget);
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      expect(
        find.byKey(const ValueKey('timeline-day-2026-10-29')),
        findsOneWidget,
      );
      await _tap(tester, find.byIcon(Icons.bolt_outlined));
      expect(find.text('Create package'), findsOneWidget);
      await _tap(tester, find.byIcon(Icons.person_outline_rounded));
      expect(find.text('XP history'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('mandatory sign-in hides the app until Firebase auth succeeds', (
    tester,
  ) async {
    final cloud = CloudSyncController(
      api: FakeCloudApi(),
      cache: MemoryCloudCache(),
      sessionStore: MemorySessions(),
    );
    await cloud.initialize();
    final planner = _controller();
    await pumpScreen(
      tester,
      LevelUpShell(refresh: _refresh),
      planner: planner,
      cloud: cloud,
    );

    expect(find.byType(CloudAccountPage), findsOneWidget);
    expect(find.byType(PlannerTimeline), findsNothing);
    expect(find.byKey(const ValueKey('cloud-google-submit')), findsOneWidget);
    expect(find.text('Continue offline'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('cloud-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cloud-password')),
      'A-long-password-123',
    );
    await _tap(tester, find.byKey(const ValueKey('cloud-submit')));

    expect(cloud.user?.id, 'a');
    expect(find.byType(CloudAccountPage), findsNothing);
    expect(find.byType(PlannerTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    cloud.dispose();
    planner.dispose();
  });

  testWidgets(
    'continuing without an account opens the app, persists, and can sign in later',
    (tester) async {
      final cloud = CloudSyncController(
        api: FakeCloudApi(),
        cache: MemoryCloudCache(),
        sessionStore: MemorySessions(),
      );
      await cloud.initialize();
      final planner = _controller();
      Future<void> open() => pumpScreen(
        tester,
        LevelUpShell(refresh: _refresh),
        planner: planner,
        cloud: cloud,
      );
      await open();
      expect(find.byType(PlannerTimeline), findsNothing);
      await _tap(
        tester,
        find.byKey(const ValueKey('cloud-continue-without-account')),
      );
      expect(cloud.user, isNull);
      expect(find.byType(CloudAccountPage), findsNothing);
      expect(find.byType(PlannerTimeline), findsOneWidget);
      expect(LocalStore.setting('levelUpContinueWithoutAccount', false), true);

      // The choice survives an app restart. Let the saved setting reach
      // storage first; the shell writes it without awaiting.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpWidget(const SizedBox());
      await open();
      expect(find.byType(PlannerTimeline), findsOneWidget);

      await _tap(tester, find.byType(NavigationDestination).at(2));
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Stored on this device'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('profile-sign-in')));
      expect(find.byType(CloudAccountPage), findsOneWidget);
      expect(find.byType(PlannerTimeline), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('cloud-email')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloud-password')),
        'A-long-password-123',
      );
      await _tap(tester, find.byKey(const ValueKey('cloud-submit')));
      expect(cloud.user?.id, 'a');
      // Back in the app on the Profile tab the user came from.
      expect(find.byType(CloudAccountPage), findsNothing);
      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.text('Not signed in'), findsNothing);
      expect(LocalStore.setting('levelUpContinueWithoutAccount', true), false);

      // After an account session ends, the sign-in screen returns.
      await tester.runAsync(cloud.signOut);
      await tester.pumpAndSettle();
      expect(find.byType(CloudAccountPage), findsOneWidget);
      expect(find.byType(PlannerTimeline), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      cloud.dispose();
      planner.dispose();
    },
  );

  testWidgets('mandatory sign-in cannot be dismissed with Back', (
    tester,
  ) async {
    final cloud = CloudSyncController(
      api: FakeCloudApi(),
      cache: MemoryCloudCache(),
      sessionStore: MemorySessions(),
    );
    await cloud.initialize();
    final planner = _controller();
    await pumpScreen(
      tester,
      LevelUpShell(refresh: _refresh),
      planner: planner,
      cloud: cloud,
    );
    final google = find.byKey(const ValueKey('cloud-google-submit'));
    expect(
      find.descendant(of: google, matching: find.byType(GoogleLogo)),
      findsOneWidget,
    );
    final pop = tester.widget<PopScope>(
      find
          .descendant(
            of: find.byType(CloudAccountPage),
            matching: find.byType(PopScope),
          )
          .first,
    );
    expect(pop.canPop, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CloudAccountPage), findsOneWidget);
    expect(find.byType(PlannerTimeline), findsNothing);
    await tester.pumpWidget(const SizedBox());
    cloud.dispose();
    planner.dispose();
  });

  testWidgets(
    'profile offers account actions without manual sync and resume retries',
    (tester) async {
      final api = FakeCloudApi()
        ..getError = const CloudApiException('network_error');
      final cloud = CloudSyncController(
        api: api,
        cache: MemoryCloudCache(),
        sessionStore: MemorySessions(),
        exportDraft: () async => '{}',
        retryDelays: const [],
      );
      await tester.runAsync(() async {
        await cloud.initialize();
        await cloud.signIn('a@example.com', 'A-long-password-123');
      });
      expect(cloud.status, CloudSyncStatus.offline);
      final planner = _controller();
      await pumpScreen(
        tester,
        LevelUpShell(refresh: _refresh),
        planner: planner,
        cloud: cloud,
      );
      await _tap(tester, find.byIcon(Icons.person_outline_rounded));
      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.text('Sync now'), findsNothing);
      // Backups live in Settings > Data, not on Profile.
      expect(find.text('Export data'), findsNothing);
      expect(find.text('Import data'), findsNothing);
      // The habit/focus tools are gone; the footer names only the app.
      expect(find.text('Habit & focus tools'), findsNothing);
      expect(find.textContaining('Based on Streak'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-about')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Level Up'), findsOneWidget);
      // Streak's GPL section 7(b) term requires the attribution in the
      // About screen, where the app's legal notices live.
      await _tap(tester, find.byKey(const ValueKey('profile-about')));
      expect(find.textContaining('Based on Streak by InlitX'), findsOneWidget);
      await _tap(tester, find.text('Close'));
      expect(find.text('Sign out'), findsOneWidget);

      api.getError = null;
      final before = api.events.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(api.events.length, greaterThan(before));
      expect(cloud.status, isNot(CloudSyncStatus.offline));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      cloud.dispose();
      planner.dispose();
    },
  );

  testWidgets(
    'Settings backup exports, rejects bad files, and restores after confirmation',
    (tester) async {
      // No account: backups work on this device alone.
      final planner = _controller();
      await planner.saveItem(
        PlannerItem(id: 'old', title: 'Old task', date: _now),
      );
      File? shared;
      var file = '{}';
      final originalPick = PlannerBackup.pickFile;
      final originalShare = PlannerBackup.shareFile;
      PlannerBackup.pickFile = () async => file;
      PlannerBackup.shareFile = (_, written) async => shared = written;
      addTearDown(() {
        PlannerBackup.pickFile = originalPick;
        PlannerBackup.shareFile = originalShare;
      });
      await pumpScreen(tester, const PlannerSettingsPage(), planner: planner);

      // Export writes a planner backup that the import accepts.
      await tester.runAsync(() async {
        await PlannerBackup.export(
          tester.element(find.byType(PlannerSettingsPage)),
        );
      });
      final exported = await tester.runAsync(() => shared!.readAsString());
      expect(
        PlannerState.fromMap(
          plannerStateFromImport(exported!),
        ).items.single.title,
        'Old task',
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-import')),
        300,
      );
      // A file that is not a Level Up backup changes nothing.
      await _tap(tester, find.byKey(const ValueKey('settings-import')));
      expect(find.text("This file isn't a valid Level Up export."), findsOne);
      expect(find.byType(AlertDialog), findsNothing);
      expect(planner.items.single.id, 'old');

      // A valid backup still asks first; going back keeps the data.
      file = encodePlannerBackup(
        PlannerState(
          items: [PlannerItem(id: 'new', title: 'Imported task', date: _now)],
        ).toMap(),
        _now,
      );
      await _tap(tester, find.byKey(const ValueKey('settings-import')));
      expect(find.text('Replace your data?'), findsOneWidget);
      await _tap(tester, find.text('Go back'));
      expect(planner.items.single.id, 'old');

      await _tap(tester, find.byKey(const ValueKey('settings-import')));
      await _tap(tester, find.text('Replace'));
      expect(planner.items.single.title, 'Imported task');
      expect(find.text('Data imported'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      planner.dispose();
    },
  );

  testWidgets('settings holds appearance and privacy with no separate app', (
    tester,
  ) async {
    final planner = _controller();
    await pumpScreen(tester, const PlannerSettingsPage(), planner: planner);
    expect(find.byKey(const ValueKey('settings-theme-mode')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-app-lock')),
      300,
    );
    expect(find.byKey(const ValueKey('settings-app-lock')), findsOneWidget);
    expect(find.text('More settings'), findsNothing);
    await _tap(tester, find.text('Dark'));
    expect(
      tester
          .widget<SegmentedButton<ThemeMode>>(
            find.byKey(const ValueKey('settings-theme-mode')),
          )
          .selected,
      {ThemeMode.dark},
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    planner.dispose();
  });

  testWidgets(
    'today challenge controls are on Challenges, tasks stay on Schedule',
    (
      tester,
    ) async {
      final c = _controller();
      await c.startChallenge(_package());
      await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);

      expect(find.byType(PlannerTimeline), findsOneWidget);
      expect(find.text("Today's challenge"), findsNothing);
      expect(find.text("Choose tomorrow's package"), findsNothing);
      expect(find.byType(TodayChallengeSection), findsNothing);
      expect(find.byType(TomorrowAssignmentTile), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Warm-up'),
        300,
        maxScrolls: 30,
        scrollable: _timelineScroll,
      );
      await _tap(tester, find.byIcon(Icons.bolt_outlined));
      expect(find.text("Today's challenge"), findsOneWidget);
      expect(find.text('Hard Workout'), findsOneWidget);
      expect(find.text("Choose tomorrow's package"), findsOneWidget);
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      expect(find.text("Today's challenge"), findsNothing);
      expect(find.text('Warm-up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('routine completion updates its record without challenge XP', (
    tester,
  ) async {
    final c = _controller();
    await c.saveItem(
      PlannerItem(
        id: 'uni',
        title: 'University',
        date: _now,
        startMinute: 8 * 60,
        endMinute: 14 * 60,
        recurrence: PlannerRecurrence.weekdays,
        weekdays: [1, 2, 4],
      ),
    );
    await c.saveItem(
      PlannerItem(id: 'read', title: 'Read lecture notes', date: _now),
    );
    await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
    expect(find.text('University'), findsOneWidget);
    await _tap(tester, find.text('Read lecture notes'));
    await _tap(tester, find.text('Mark complete'));
    expect(c.balance, 0);
    expect(c.ledger, isEmpty);
    expect(
      c.occurrenceById('read@2026-10-29')!.record.status,
      CompletionStatus.completed,
    );
    expect(find.text('Mark complete'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PlannerTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('tomorrow selection commits once and preserves the routine', (
    tester,
  ) async {
    final c = _controller();
    await c.saveTemplate(_package());
    final tomorrow = plannerAddDays(_now, 1);
    await c.saveItem(
      PlannerItem(
        id: 'uni',
        title: 'University',
        date: tomorrow,
        startMinute: 8 * 60,
        endMinute: 14 * 60,
      ),
    );
    final routine = c.items.single.toMap();
    await pumpScreen(
      tester,
      ChallengePreviewPage(template: c.templates.single),
      planner: c,
    );
    expect(c.instances, isEmpty);
    expect(find.text('Failure −0 XP'), findsOneWidget);
    await _tap(tester, find.text('Confirm commitment'));
    expect(c.instances, isEmpty);
    await _tap(tester, find.text('Confirm commitment').last);
    expect(c.instances.length, 1);
    expect(c.tomorrowSelection!.instanceId, c.instances.single.id);
    expect(c.items.single.toMap(), routine);
    expect(c.occurrences(tomorrow).where((o) => o.isChallenge).length, 3);
    expect(
      c.occurrences(tomorrow).where((o) => !o.isChallenge).single.title,
      'University',
    );
    await c.evaluate();
    expect(c.instances.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets("tomorrow's package can be cancelled from its page", (
    tester,
  ) async {
    final c = _controller();
    await c.saveTemplate(_package());
    final instance = await c.assignTomorrow(c.templates.single.id);
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ChallengeInstancePage(instanceId: instance.id),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      planner: c,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('cancel-tomorrow')));
    expect(find.textContaining('choose another package'), findsOneWidget);
    await _tap(tester, find.text("Cancel tomorrow's package").last);
    expect(c.instances, isEmpty);
    expect(c.tomorrowSelection!.isPending, isTrue);
    expect(find.byType(ChallengeInstancePage), findsNothing);
    expect(find.text("Tomorrow's package was cancelled"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('steps no longer gate completion or show a checklist', (
    tester,
  ) async {
    final c = _controller();
    await c.startChallenge(_package());
    final occurrence = c
        .occurrences(_now)
        .firstWhere((o) => o.item.title == 'Warm-up');
    // The package's saved steps are still stored, only no longer used.
    expect(occurrence.item.steps, ['Prepare', 'Move']);
    await pumpScreen(
      tester,
      PlannerTaskPage(occurrence: occurrence),
      planner: c,
    );
    expect(find.text('1. Prepare'), findsNothing);
    await _tap(tester, find.text('Mark complete'));
    expect(c.balance, 10);
    expect(c.ledger.length, 1);
    expect(find.text('Mark complete'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('anytime challenge tasks get a box on the schedule', (
    tester,
  ) async {
    final c = _controller();
    await c.startChallenge(_package());
    await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
    final strip = find.byKey(const ValueKey('anytime-challenges'));
    expect(strip, findsOneWidget);
    // Untimed tasks (Warm-up, Stretching) are in the box, not the day list;
    // the timed Running block stays on the timeline.
    expect(
      find.descendant(of: strip, matching: find.text('Warm-up')),
      findsOneWidget,
    );
    expect(find.text('Warm-up'), findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.text('Running')),
      findsNothing,
    );
    final warmup = c
        .occurrences(_now)
        .firstWhere((o) => o.item.title == 'Warm-up');
    await _tap(tester, find.byKey(ValueKey('anytime-complete-${warmup.id}')));
    expect(
      c.occurrenceById(warmup.id)!.record.status,
      CompletionStatus.completed,
    );
    expect(c.balance, 10);
    expect(find.byType(PlannerTaskPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'overdue selection notice shows the actual charge and stays acknowledged',
    (tester) async {
      var now = _now;
      final c = PlannerController(
        initial: {},
        clock: () => now,
        persist: (_) async {},
        catalog: [],
      );
      await c.evaluate();
      now = DateTime(2026, 10, 30, 1);
      await c.evaluate();
      await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Penalty recorded: 0 XP'), findsOneWidget);
      expect(c.ledger.length, 1);
      await _tap(tester, find.text('OK'));
      expect(c.unacknowledgedMisses, isEmpty);
      final reopened = PlannerController(
        initial: c.exportState,
        clock: () => now,
        persist: (_) async {},
        catalog: [],
      );
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        LevelUpShell(refresh: _refresh),
        planner: reopened,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(reopened.ledger.length, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      reopened.dispose();
    },
  );

  testWidgets(
    'Arabic RTL and English LTR preserve identities and XP on all main screens',
    (tester) async {
      final c = _controller();
      await c.saveTemplate(_package());
      await c.saveItem(
        PlannerItem(
          id: 'uni',
          title: 'University الجامعة',
          date: _now,
          startMinute: 8 * 60,
          endMinute: 14 * 60,
        ),
      );
      final state = c.exportState;
      final locale = ValueNotifier(const Locale('en'));
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (context, value, _) => Localizations.override(
              context: context,
              locale: value,
              child: LevelUpShell(refresh: _refresh),
            ),
          ),
        ),
        planner: c,
      );
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.ltr,
      );
      locale.value = const Locale('ar');
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.rtl,
      );
      expect(find.text('University الجامعة'), findsOneWidget);
      for (final icon in [
        Icons.calendar_view_week_outlined,
        Icons.bolt_outlined,
        Icons.person_outline_rounded,
      ]) {
        await _tap(tester, find.byIcon(icon));
        expect(tester.takeException(), isNull);
      }
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LevelUpShell))),
        TextDirection.ltr,
      );
      expect(c.exportState, state);
      expect(find.text('XP history'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
      c.dispose();
    },
  );

  testWidgets('main screens remain usable at double system text size', (
    tester,
  ) async {
    final c = _controller();
    await pumpScreen(
      tester,
      LevelUpShell(refresh: _refresh),
      planner: c,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    for (final icon in [
      Icons.calendar_view_week_outlined,
      Icons.bolt_outlined,
      Icons.person_outline_rounded,
    ]) {
      await _tap(tester, find.byIcon(icon));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'scrolled date survives language orientation tabs and routine edits',
    (tester) async {
      final c = _controller();
      await c.saveItem(
        PlannerItem(
          id: 'daily',
          title: 'University الجامعة',
          date: plannerDay(_now),
          startMinute: 8 * 60,
          endMinute: 14 * 60,
          recurrence: PlannerRecurrence.daily,
        ),
      );
      final before = c.exportState;
      final locale = ValueNotifier(const Locale('en'));
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (context, value, _) => Localizations.override(
              context: context,
              locale: value,
              child: LevelUpShell(refresh: _refresh),
            ),
          ),
        ),
        planner: c,
      );
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      final target = find.byKey(const ValueKey('timeline-day-2026-11-02'));
      final scroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('timeline-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        target,
        500,
        maxScrolls: 40,
        scrollable: scroll,
      );
      await tester.ensureVisible(target);
      await tester.drag(
        find.byKey(const PageStorageKey('timeline-scroll')),
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      Finder focus() => find.byKey(const ValueKey('timeline-focus-2026-11-02'));
      expect(focus(), findsOneWidget);

      locale.value = const Locale('ar');
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(PlannerTimeline))),
        TextDirection.rtl,
      );
      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      await _tap(tester, find.byIcon(Icons.bolt_outlined));
      await _tap(tester, find.byIcon(Icons.calendar_view_week_outlined));
      expect(focus(), findsOneWidget);
      expect(c.exportState, before);

      await c.saveItem(
        c.items.single.copyWith(title: 'University lab الجامعة'),
      );
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(c.occurrenceById('daily@2026-11-02')!.item.id, 'daily');
      expect(c.balance, 0);
      expect(c.instances, isEmpty);
      expect(c.ledger, isEmpty);
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(focus(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
      c.dispose();
    },
  );

  testWidgets('current-time marker advances without changing task records', (
    tester,
  ) async {
    var now = _now;
    final c = PlannerController(
      initial: {},
      persist: (_) async {},
      catalog: [],
      clock: () => now,
    );
    await c.evaluate();
    await pumpScreen(tester, LevelUpShell(refresh: _refresh), planner: c);
    final marker = find.byKey(const ValueKey('timeline-now'));
    final before = tester.widget<PositionedDirectional>(marker).top!;
    final state = c.exportState;
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PositionedDirectional>(marker).top!,
      greaterThan(before),
    );
    expect(c.exportState, state);
    expect(c.ledger, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
