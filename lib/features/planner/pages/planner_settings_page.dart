import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';
import 'package:streak/features/settings/pages/settings_page.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
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
          PlannerSection(context.plannerText('dailySelection')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(context.plannerText('selectionDeadline')),
            trailing: Text(time.format(context)),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(context.plannerText('missedSelectionPenalty')),
            trailing: Text(plannerNumber(context, c.missedSelectionPenalty)),
            onTap: () => _penalty(c),
          ),
          const SizedBox(height: 12),
          Text(
            context.plannerText('selectionRulesInfo', {
              'time': time.format(context),
              'xp': plannerNumber(context, c.missedSelectionPenalty),
            }),
          ),
          PlannerSection(context.plannerText('reminderAccess')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(context.plannerText('notificationAccess')),
            onTap: _busy ? null : () => _access(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm),
            title: Text(context.plannerText('preciseReminders')),
            onTap: _busy ? null : () => _access(exact: true),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: Text(context.plannerText('moreSettings')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
              if (context.mounted) await plannerAction(context, c.reload);
            },
          ),
        ],
      ),
    );
  }
}
