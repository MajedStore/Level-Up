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
          const SizedBox(height: 24),
          PlannerGroup(
            children: [
              PlannerMenuRow(
                icon: Icons.tune_rounded,
                label: context.plannerText('moreSettings'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                  if (context.mounted) await plannerAction(context, c.reload);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
