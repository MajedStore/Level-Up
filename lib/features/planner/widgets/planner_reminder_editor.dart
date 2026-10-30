import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:flutter/material.dart';
import 'package:streak/features/habits/widgets/reminder_sound_picker.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/services/notification_service.dart';

Future<bool> requestPlannerReminderAccess(BuildContext context) async {
  final granted = await NotificationService().requestNotifications();
  if (!granted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.plannerText('notificationsBlocked'),
        ),
      ),
    );
  }
  return granted;
}

class PlannerReminderEdit {
  const PlannerReminderEdit(this.reminder, this.entireSeries);
  final PlannerReminder reminder;
  final bool entireSeries;
}

Future<PlannerReminderEdit?> editPlannerReminder(
  BuildContext context,
  PlannerOccurrence occurrence,
) => showDialog<PlannerReminderEdit>(
  context: context,
  builder: (_) => _ReminderDialog(occurrence: occurrence),
);

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.occurrence});
  final PlannerOccurrence occurrence;
  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late bool _enabled = widget.occurrence.item.reminder.enabled;
  late int _minute =
      widget.occurrence.item.reminder.minute ??
      widget.occurrence.item.startMinute ??
      9 * 60;
  late String _sound = widget.occurrence.item.reminder.sound;
  late bool _vibrate = widget.occurrence.item.reminder.vibrate;
  bool _entireSeries = false;
  String _soundName = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.plannerText('taskReminder')),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.plannerText('enableReminder')),
              value: _enabled,
              onChanged: (v) async {
                setState(() => _enabled = v);
                if (v) await requestPlannerReminderAccess(context);
              },
            ),
            if (_enabled) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.plannerText('reminderTime')),
                subtitle: Text(
                  TimeOfDay(
                    hour: _minute ~/ 60,
                    minute: _minute % 60,
                  ).format(context),
                ),
                trailing: const Icon(Icons.schedule_rounded),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: _minute ~/ 60,
                      minute: _minute % 60,
                    ),
                  );
                  if (time != null && mounted) {
                    setState(() => _minute = time.hour * 60 + time.minute);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.plannerText('sound')),
                subtitle: Text(
                  _soundName.isEmpty
                      ? context.plannerText('choosePreviewSound')
                      : plannerSoundName(context, _soundName),
                ),
                trailing: const Icon(Icons.volume_up_outlined),
                onTap: () => pickReminderSound(
                  context,
                  uri: _sound == 'default' ? '' : _sound,
                  onChanged: (sound) => setState(() {
                    _sound = sound.uri.isEmpty ? 'default' : sound.uri;
                    _soundName = sound.title;
                  }),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.plannerText('vibrate')),
                value: _vibrate,
                onChanged: (v) => setState(() => _vibrate = v),
              ),
            ],
            if (widget.occurrence.isChallenge ||
                widget.occurrence.item.recurrence != PlannerRecurrence.once)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.plannerText('applyEveryOccurrence')),
                subtitle: Text(context.plannerText('fixedPackageRules')),
                value: _entireSeries,
                onChanged: (v) => setState(() => _entireSeries = v!),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.plannerText('goBack')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          PlannerReminderEdit(
            PlannerReminder(
              enabled: _enabled,
              minute: _minute,
              sound: _sound,
              vibrate: _vibrate,
            ),
            _entireSeries,
          ),
        ),
        child: Text(context.plannerText('saveReminder')),
      ),
    ],
  );
}
