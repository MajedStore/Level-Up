import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/home_shell.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_timeline.dart';
import 'package:streak/features/planner/pages/planner_challenges_page.dart';
import 'package:streak/features/planner/pages/planner_editor_page.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';
import 'package:streak/features/planner/pages/planner_settings_page.dart';
import 'package:streak/services/planner_sync.dart';
import 'package:streak/services/cloud_sync_controller.dart';
import 'package:streak/features/planner/pages/cloud_account_page.dart';

class LevelUpShell extends StatefulWidget {
  const LevelUpShell({super.key, this.refresh});
  final Future<void> Function(PlannerController)? refresh;
  @override
  State<LevelUpShell> createState() => _LevelUpShellState();
}

class _LevelUpShellState extends State<LevelUpShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  final _timelineNavigation = PlannerTimelineNavigation();
  Timer? _minute;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    final c = context.read<PlannerController>();
    await plannerAction(context, () => (widget.refresh ?? refreshPlanner)(c));
    if (mounted) unawaited(context.read<CloudSyncController?>()?.synchronize());
    if (!mounted) return;
    setState(() {});
    if (c.unacknowledgedMisses.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(dialog.plannerText('selectionMissed')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dialog.plannerText('selectionMissedNotice')),
                const SizedBox(height: 12),
                for (final selection in c.unacknowledgedMisses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${plannerLocalDate(dialog, selection.targetDate)} · ${dialog.plannerText('selectionPenaltyApplied', {'xp': plannerNumber(dialog, -c.ledger.where((e) => e.idempotencyKey == 'missed_selection:${selection.dateKey}').fold<int>(0, (n, e) => n + e.change))})}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.plannerText('acknowledged')),
            ),
          ],
        ),
      );
      if (mounted) await plannerAction(context, c.acknowledgeMissedSelections);
    }
    _refreshing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['schedule', 'challenges', 'profile'];
    return Scaffold(
      appBar: _tab == 0
          ? null
          : AppBar(title: Text(context.plannerText(keys[_tab]))),
      body: SafeArea(
        top: _tab == 0,
        child: IndexedStack(
          index: _tab,
          children: [
            _PlannerTimelinePage(
              key: PageStorageKey('schedule'),
              navigation: _timelineNavigation,
            ),
            const PlannerChallengesPage(),
            const _ProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          if (value == 0 && _tab == 0) {
            unawaited(_timelineNavigation.returnToNow());
          } else if (value != _tab) {
            setState(() => _tab = value);
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.calendar_view_week_outlined),
            label: context.plannerText('schedule'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            label: context.plannerText('challenges'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            label: context.plannerText('profile'),
          ),
        ],
      ),
    );
  }
}

Future<void> addRoutine(BuildContext context, {DateTime? date}) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PlannerEditorPage(date: date)),
    );
void openPlannerTask(BuildContext context, PlannerOccurrence occurrence) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PlannerTaskPage(occurrence: occurrence),
      ),
    );

class _PlannerTimelinePage extends StatelessWidget {
  const _PlannerTimelinePage({super.key, required this.navigation});
  final PlannerTimelineNavigation navigation;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    return PlannerTimeline(
      controller: c,
      navigation: navigation,
      onOpen: (occurrence) => openPlannerTask(context, occurrence),
      onAdd: (day) => addRoutine(context, date: day),
      header: _LevelSummary(controller: c),
      todayFooter: const _TodayChallenge(),
    );
  }
}

class _LevelSummary extends StatelessWidget {
  const _LevelSummary({required this.controller});
  final PlannerController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 12),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 21,
            color: context.colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.plannerText('levelXp', {
                'level': plannerNumber(context, c.level),
                'xp': plannerNumber(context, c.balance),
              }),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: context.plannerText('nextLevelXp', {
              'xp': plannerNumber(context, c.nextLevelXp - c.balance),
            }),
            child: SizedBox(
              width: 72,
              child: LinearProgressIndicator(
                value: c.levelProgress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayChallenge extends StatelessWidget {
  const _TodayChallenge();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final today = plannerDay(c.now);
    final challenges = c
        .occurrences(today)
        .where((o) => o.isChallenge)
        .toList();
    final ids = challenges.map((o) => o.challengeId).toSet();
    final assignment = c.selectionFor(today);
    if (assignment?.instanceId != null) ids.add(assignment!.instanceId);
    final packages = c.instances.where((i) => ids.contains(i.id));
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlannerSection(context.plannerText('todaysChallenge')),
          if (packages.isEmpty)
            Text(
              context.plannerText('noChallenge'),
              style: TextStyle(color: context.tokens.muted),
            ),
          for (final package in packages) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.emoji_events_outlined),
              title: Text(plannerTemplateName(context, package.snapshot)),
              subtitle: Text(context.plannerText(package.status.name)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChallengeInstancePage(instanceId: package.id),
                ),
              ),
            ),
            if (package.status == ChallengeStatus.active)
              for (final task in package.snapshot.rootTasks)
                ChallengeTaskNode(
                  instance: package,
                  task: task,
                  occurrences: challenges
                      .where((o) => o.challengeId == package.id)
                      .toList(),
                  day: today,
                  pendingOnly: true,
                ),
          ],
          const SizedBox(height: 12),
          const TomorrowAssignmentTile(),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final cloud = context.watch<CloudSyncController?>();
    return ListView(
      key: const PageStorageKey('profile'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        Text(
          context.plannerText('levelXp', {
            'level': plannerNumber(context, c.level),
            'xp': plannerNumber(context, c.balance),
          }),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        if (cloud != null) CloudAccountTile(controller: cloud),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.plannerText('settings')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const PlannerSettingsPage(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(context.plannerText('xpHistory')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const PlannerXpHistoryPage(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: Text(context.plannerText('achievements')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const _AchievementsPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.local_fire_department_outlined),
          title: Text(context.plannerText('habitFocusTools')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: Text(context.plannerText('habitFocusTools')),
                ),
                body: const HomeShell(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'Level Up',
            applicationLegalese: 'Based on Streak by InlitX\nGPL-3.0-only',
          ),
          child: Text(context.plannerText('about')),
        ),
        Text(
          'Based on Streak by InlitX',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.tokens.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class PlannerXpHistoryPage extends StatelessWidget {
  const PlannerXpHistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('xpHistory'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.ledger.isEmpty) Text(context.plannerText('noXpHistory')),
          for (final event in c.ledger.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(plannerTransactionReason(context, event)),
              subtitle: Text(plannerLocalDate(context, event.at)),
              trailing: Text(
                '${event.change > 0 ? '+' : ''}${plannerNumber(context, event.change)} XP',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: event.change < 0
                      ? context.tokens.warning
                      : context.tokens.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AchievementsPage extends StatelessWidget {
  const _AchievementsPage();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('achievements'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.achievements.isEmpty)
            Text(context.plannerText('noAchievements')),
          for (final achievement in c.achievements)
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(plannerAchievementTitle(context, achievement)),
              subtitle: Text(plannerLocalDate(context, achievement.unlockedAt)),
            ),
        ],
      ),
    );
  }
}
