import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/utils/app_dirs.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/pages/planner_backup.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';
import 'package:streak/features/settings/settings_actions.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/settings/widgets/minimal_settings_widgets.dart';
import 'package:streak/features/settings/widgets/settings_sheets.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/planner_sync.dart';

class PlannerSettingsPage extends StatefulWidget {
  const PlannerSettingsPage({super.key});
  @override
  State<PlannerSettingsPage> createState() => _PlannerSettingsPageState();
}

class _PlannerSettingsPageState extends State<PlannerSettingsPage> {
  bool _busy = false;
  Future<void> _penalty(PlannerController c) async {
    var input = '${c.missedSelectionPenalty}';
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(dialog.plannerText('missedSelectionPenalty')),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: input,
            onChanged: (value) => input = value,
            keyboardType: TextInputType.number,
            validator: (text) {
              final n = int.tryParse(plannerLatinDigits(text ?? ''));
              return n == null || n < 0 || n > 1000000
                  ? dialog.plannerText('requiredValue')
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(dialog.plannerText('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialog, int.parse(plannerLatinDigits(input)));
              }
            },
            child: Text(dialog.plannerText('save')),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      await plannerAction(
        context,
        () => c.updateSelectionRules(
          deadlineMinute: c.selectionDeadlineMinute,
          missedPenalty: value,
        ),
      );
    }
  }

  Future<void> _access({bool exact = false}) async {
    setState(() => _busy = true);
    await plannerAction(context, () async {
      if (exact) {
        await NotificationService().requestExactAlarmAccess();
      } else {
        await requestPlannerReminderAccess(context);
      }
      if (mounted) await refreshPlanner(context.read<PlannerController>());
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final settings = context.watch<SettingsController>();
    final time = TimeOfDay(
      hour: c.selectionDeadlineMinute ~/ 60,
      minute: c.selectionDeadlineMinute % 60,
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(settings.localeCode),
            initialValue: settings.localeCode.startsWith('ar') ? 'ar' : 'en',
            decoration: InputDecoration(
              labelText: context.plannerText('language'),
              prefixIcon: const Icon(Icons.translate_rounded, size: 20),
            ),
            items: const [
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (value) {
              if (value != null) {
                plannerAction(context, () async {
                  await settings.setLanguage(value);
                  await refreshPlanner(c);
                });
              }
            },
          ),
          PlannerSection(context.l10n.appearance),
          PlannerGroup(
            children: [
              // Label and selector form one setting, so one group row.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.contrast_rounded,
                          color: context.tokens.muted,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            context.l10n.theme,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      key: const ValueKey('settings-theme-mode'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(context.l10n.system),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(context.l10n.light),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(context.l10n.dark),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (mode) =>
                          settings.setThemeMode(mode.first),
                    ),
                  ],
                ),
              ),
              if (settings.colorTheme == null)
                PlannerMenuRow(
                  icon: Icons.palette_outlined,
                  label: context.l10n.accent_color,
                  trailing: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: settings.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  onTap: () => showAccentSheet(context),
                ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                secondary: Icon(
                  Icons.animation_rounded,
                  color: context.tokens.muted,
                ),
                title: Text(context.l10n.animations),
                value: settings.animations,
                onChanged: settings.setAnimations,
              ),
              if (Platform.isAndroid)
                SwitchListTile(
                  key: const ValueKey('settings-hide-navigation'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: Icon(
                    Icons.fullscreen_rounded,
                    color: context.tokens.muted,
                  ),
                  title: Text(context.plannerText('hideNavigation')),
                  subtitle: Text(
                    context.plannerText('hideNavigationInfo'),
                    style: TextStyle(color: context.tokens.muted),
                  ),
                  value: settings.hideSystemNavigation,
                  onChanged: settings.setHideSystemNavigation,
                ),
            ],
          ),
          PlannerSection(context.plannerText('dailySelection')),
          PlannerGroup(
            children: [
              PlannerMenuRow(
                icon: Icons.schedule_rounded,
                label: context.plannerText('selectionDeadline'),
                trailing: Text(time.format(context)),
                chevron: false,
                onTap: () async {
                  final chosen = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (chosen != null && context.mounted) {
                    await plannerAction(
                      context,
                      () => c.updateSelectionRules(
                        deadlineMinute: chosen.hour * 60 + chosen.minute,
                        missedPenalty: c.missedSelectionPenalty,
                      ),
                    );
                  }
                },
              ),
              PlannerMenuRow(
                icon: Icons.remove_circle_outline_rounded,
                label: context.plannerText('missedSelectionPenalty'),
                trailing: Text(
                  plannerNumber(context, c.missedSelectionPenalty),
                ),
                chevron: false,
                onTap: () => _penalty(c),
              ),
            ],
          ),
          PlannerSection(context.plannerText('reminderAccess')),
          PlannerGroup(
            children: [
              PlannerMenuRow(
                icon: Icons.notifications_none_rounded,
                label: context.plannerText('notificationAccess'),
                onTap: _busy ? null : () => _access(),
              ),
              PlannerMenuRow(
                icon: Icons.alarm_rounded,
                label: context.plannerText('preciseReminders'),
                onTap: _busy ? null : () => _access(exact: true),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          // Backups work with or without an account; when signed in, an
          // import syncs to the account like any other change.
          PlannerSection(context.l10n.data),
          PlannerGroup(
            children: [
              PlannerMenuRow(
                key: const ValueKey('settings-export'),
                icon: Icons.ios_share_rounded,
                label: context.plannerText('cloudExportDraft'),
                onTap: () => PlannerBackup.export(context),
              ),
              PlannerMenuRow(
                key: const ValueKey('settings-import'),
                icon: Icons.file_open_outlined,
                label: context.plannerText('importData'),
                onTap: () => PlannerBackup.import(context),
              ),
            ],
          ),
          PlannerSection(context.l10n.prefs_privacy),
          PlannerGroup(
            children: [
              SwitchListTile(
                key: const ValueKey('settings-app-lock'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                secondary: Icon(
                  Icons.fingerprint_rounded,
                  color: context.tokens.muted,
                ),
                title: Text(context.l10n.app_lock),
                value: settings.appLock,
                onChanged: (value) =>
                    SettingsActions.toggleAppLock(context, value),
              ),
              if (settings.appLock) ...[
                PlannerMenuRow(
                  icon: Icons.timer_outlined,
                  label: context.l10n.app_lock_delay,
                  trailing: Text(
                    SettingsActions.appLockDelayLabels(
                      context,
                    )[SettingsActions.appLockDelayIndex(settings.appLockDelay)],
                  ),
                  onTap: () => showOptionSheet(
                    context,
                    title: context.l10n.app_lock_delay,
                    options: SettingsActions.appLockDelayLabels(context),
                    index: SettingsActions.appLockDelayIndex(
                      settings.appLockDelay,
                    ),
                    onSelected: (i) => settings.setAppLockDelay(
                      SettingsActions.appLockDelays[i],
                    ),
                  ),
                ),
                if (hasBiometricLock)
                  PlannerMenuRow(
                    icon: Icons.key_rounded,
                    label: context.l10n.app_lock_method,
                    trailing: Text(
                      settings.appLockMode == 1
                          ? context.l10n.pin_lock
                          : context.l10n.app_lock_biometric,
                    ),
                    onTap: () => SettingsActions.chooseLockMethod(context),
                  ),
                if (settings.appLockMode == 1)
                  PlannerMenuRow(
                    icon: Icons.pin_outlined,
                    label: context.l10n.pin_change,
                    onTap: SettingsActions.changePin,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
