import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/home_shell.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/database/local_store.dart';
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
  Timer? _deadline;
  PlannerController? _planner;
  bool _refreshing = false;

  /// The user chose to use the app without an account. Kept as a device
  /// setting (never synced); signing in clears it, and sign-out resets device
  /// settings, so the sign-in screen returns after an account session ends.
  static const _withoutAccountKey = 'levelUpContinueWithoutAccount';
  late bool _withoutAccount = LocalStore.setting(_withoutAccountKey, false);

  void _setWithoutAccount(bool value) {
    if (!mounted || _withoutAccount == value) return;
    setState(() => _withoutAccount = value);
    unawaited(LocalStore.writeSetting(_withoutAccountKey, value));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _planner = context.read<PlannerController>()
      ..addListener(_scheduleDeadlineRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleDeadlineRefresh();
      unawaited(_refresh());
    });
  }

  void _scheduleDeadlineRefresh() {
    _deadline?.cancel();
    _deadline = null;
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final deadline = _planner?.nextSelectionDeadline;
    if (deadline == null) return;
    final remaining = deadline.difference(DateTime.now());
    _deadline = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _refreshAtDeadline,
    );
  }

  void _refreshAtDeadline() {
    if (!mounted) return;
    if (_refreshing) {
      _deadline = Timer(const Duration(seconds: 1), _refreshAtDeadline);
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    try {
      final c = _planner ?? context.read<PlannerController>();
      await plannerAction(context, () => (widget.refresh ?? refreshPlanner)(c));
      if (!mounted) return;
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
        if (mounted) {
          await plannerAction(context, c.acknowledgeMissedSelections);
        }
      }
    } finally {
      _refreshing = false;
      _scheduleDeadlineRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timelineNavigation.setVisible(_tab == 0);
      _timelineNavigation.refreshClock();
      unawaited(_refresh());
      _resumeCloudSync();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timelineNavigation.setVisible(false);
      _deadline?.cancel();
      _deadline = null;
    }
  }

  /// Synchronisation is automatic: returning to the app starts a fresh
  /// attempt for work that the bounded background retries left behind.
  void _resumeCloudSync() {
    final cloud = context.read<CloudSyncController?>();
    if (cloud == null || cloud.user == null || cloud.busy) return;
    if (const {
      CloudSyncStatus.pending,
      CloudSyncStatus.offline,
      CloudSyncStatus.conflict,
      CloudSyncStatus.rejected,
    }.contains(cloud.status)) {
      unawaited(cloud.retryNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    _planner?.removeListener(_scheduleDeadlineRefresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.read<CloudSyncController?>();
    final shell = _plannerShell(context);
    if (cloud == null) return shell;
    return ListenableBuilder(
      listenable: cloud,
      child: shell,
      builder: (context, child) {
        final signedOut = cloud.user == null;
        if (!signedOut && _withoutAccount) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _setWithoutAccount(false),
          );
        }
        // An expired session still owns cached account data, so it always
        // re-authenticates; only a fully signed-out device may skip sign-in.
        final needsAuthentication =
            (signedOut && !_withoutAccount) ||
            cloud.status == CloudSyncStatus.sessionExpired;
        if (needsAuthentication) {
          return CloudAccountPage(
            controller: cloud,
            requiredAuthentication: true,
            onContinueWithoutAccount: signedOut
                ? () => _setWithoutAccount(true)
                : null,
          );
        }
        return child!;
      },
    );
  }

  Widget _plannerShell(BuildContext context) {
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
            _ProfilePage(onSignIn: () => _setWithoutAccount(false)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          _timelineNavigation.setVisible(value == 0);
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
    );
  }
}

/// Compact level indicator for the schedule header: a progress ring around
/// the level number. The full breakdown lives on Profile.
class _LevelSummary extends StatelessWidget {
  const _LevelSummary({required this.controller});
  final PlannerController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final label = context.plannerText('levelXp', {
      'level': plannerNumber(context, c.level),
      'xp': plannerNumber(context, c.balance),
    });
    return Tooltip(
      message:
          '$label\n${context.plannerText('nextLevelXp', {'xp': plannerNumber(context, c.nextLevelXp - c.balance)})}',
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: c.levelProgress,
                strokeWidth: 3,
                backgroundColor: context.colors.surfaceContainerHigh,
              ),
              Text(
                plannerNumber(context, c.level),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.onSignIn});

  /// Leaves no-account mode and shows the sign-in screen.
  final VoidCallback onSignIn;

  void _open(BuildContext context, WidgetBuilder builder) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: builder));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final cloud = context.read<CloudSyncController?>();
    return ListView(
      key: const PageStorageKey('profile'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (cloud != null) ...[
          CloudIdentityHeader(controller: cloud),
          ListenableBuilder(
            listenable: cloud,
            builder: (context, _) => cloud.user != null || !cloud.configured
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton.icon(
                      key: const ValueKey('profile-sign-in'),
                      onPressed: onSignIn,
                      icon: const Icon(Icons.login_rounded, size: 20),
                      label: Text(context.plannerText('cloudSignIn')),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
        ],
        _ProfileProgress(controller: c),
        const SizedBox(height: 16),
        PlannerGroup(
          children: [
            PlannerMenuRow(
              icon: Icons.history_rounded,
              label: context.plannerText('xpHistory'),
              onTap: () => _open(context, (_) => const PlannerXpHistoryPage()),
            ),
            PlannerMenuRow(
              icon: Icons.workspace_premium_outlined,
              label: context.plannerText('achievements'),
              trailing: c.achievements.isEmpty
                  ? null
                  : Text(plannerNumber(context, c.achievements.length)),
              onTap: () => _open(context, (_) => const _AchievementsPage()),
            ),
            PlannerMenuRow(
              icon: Icons.local_fire_department_outlined,
              label: context.plannerText('habitFocusTools'),
              onTap: () => _open(
                context,
                (_) => Scaffold(
                  appBar: AppBar(
                    title: Text(context.plannerText('habitFocusTools')),
                  ),
                  body: const HomeShell(),
                ),
              ),
            ),
            PlannerMenuRow(
              icon: Icons.tune_rounded,
              label: context.plannerText('settings'),
              onTap: () => _open(context, (_) => const PlannerSettingsPage()),
            ),
          ],
        ),
        if (cloud != null) ...[
          const SizedBox(height: 16),
          CloudAccountActions(controller: cloud),
        ],
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Level Up',
              applicationLegalese: 'Based on Streak by InlitX\nGPL-3.0-only',
            ),
            style: TextButton.styleFrom(
              foregroundColor: context.tokens.muted,
              textStyle: Theme.of(context).textTheme.bodySmall,
            ),
            child: Text(
              '${context.plannerText('about')} · Based on Streak by InlitX',
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileProgress extends StatelessWidget {
  const _ProfileProgress({required this.controller});
  final PlannerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    return PlannerPanel(
      key: const ValueKey('profile-progress-card'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  context.plannerText('levelShort', {
                    'level': plannerNumber(context, c.level),
                  }),
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${plannerNumber(context, c.balance)} ${context.plannerText('xp')}',
                style: text.titleMedium?.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: c.levelProgress,
              minHeight: 6,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.plannerText('nextLevelXp', {
              'xp': plannerNumber(context, c.nextLevelXp - c.balance),
            }),
            style: text.bodySmall?.copyWith(color: context.tokens.muted),
          ),
        ],
      ),
    );
  }
}

/// Centred icon and message for lists with nothing in them yet.
class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(icon, size: 40, color: context.tokens.muted),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.tokens.muted),
        ),
      ],
    ),
  );
}

class PlannerXpHistoryPage extends StatelessWidget {
  const PlannerXpHistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('xpHistory'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (c.ledger.isEmpty)
            _EmptyList(
              icon: Icons.history_rounded,
              message: context.plannerText('noXpHistory'),
            )
          else
            PlannerGroup(
              dividerIndent: 16,
              children: [
                for (final event in c.ledger.reversed)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    title: Text(plannerTransactionReason(context, event)),
                    subtitle: Text(
                      plannerLocalDate(context, event.at),
                      style: TextStyle(color: context.tokens.muted),
                    ),
                    trailing: Text(
                      '${event.change > 0 ? '+' : ''}${plannerNumber(context, event.change)} XP',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: event.change < 0
                            ? context.tokens.warning
                            : context.tokens.success,
                      ),
                    ),
                  ),
              ],
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (c.achievements.isEmpty)
            _EmptyList(
              icon: Icons.workspace_premium_outlined,
              message: context.plannerText('noAchievements'),
            )
          else
            PlannerGroup(
              children: [
                for (final achievement in c.achievements)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: Icon(
                      Icons.workspace_premium_outlined,
                      color: context.colors.primary,
                    ),
                    title: Text(plannerAchievementTitle(context, achievement)),
                    subtitle: Text(
                      plannerLocalDate(context, achievement.unlockedAt),
                      style: TextStyle(color: context.tokens.muted),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
