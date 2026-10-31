import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/habits/widgets/reminder_sound_picker.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';

class PlannerEditorPage extends StatefulWidget {
  const PlannerEditorPage({
    super.key,
    this.item,
    this.date,
    this.occurrenceDay,
    this.scheduled = true,
  });
  final PlannerItem? item;
  final DateTime? date;
  final DateTime? occurrenceDay;
  final bool scheduled;
  @override
  State<PlannerEditorPage> createState() => _PlannerEditorPageState();
}

class _PlannerEditorPageState extends State<PlannerEditorPage> {
  final _form = GlobalKey<FormState>();
  final _advanced = ExpansibleController();
  late final PlannerItem? _baseItem =
      context
          .read<PlannerController>()
          .items
          .where((i) => i.id == widget.item?.id)
          .firstOrNull ??
      widget.item;
  bool get _hasRecurringSeries =>
      _baseItem != null && _baseItem.recurrence != PlannerRecurrence.once;
  late final TextEditingController _title = TextEditingController(
    text: widget.item?.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item?.description,
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.item?.target?.toString() ?? '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.item?.unit,
  );
  late final TextEditingController _interval = TextEditingController(
    text: '${_baseItem?.everyWeeks ?? 1}',
  );
  late DateTime _date =
      widget.date ?? widget.item?.date ?? context.read<PlannerController>().now;
  late String _category = widget.item?.category ?? 'Personal';
  late bool _scheduled = widget.item == null
      ? widget.scheduled
      : widget.item!.startMinute != null;
  late int _start = widget.item?.startMinute ?? 9 * 60;
  late int _end = widget.item?.endMinute ?? 10 * 60;

  /// An end time earlier than the start always means the next day.
  bool get _overnight => _end < _start;
  late PlannerRecurrence _recurrence =
      _baseItem?.recurrence ?? PlannerRecurrence.once;
  late final Set<int> _weekdays = {...?_baseItem?.weekdays};
  late final Set<String> _dependencies = {...?widget.item?.dependencies};
  late bool _reminder = widget.item?.reminder.enabled ?? false;
  late int _reminderMinute =
      widget.item?.reminder.minute ?? (_scheduled ? _start : 9 * 60);
  late String _sound = widget.item?.reminder.sound ?? 'default';
  String _soundName = '';
  late bool _vibrate = widget.item?.reminder.vibrate ?? true;
  late bool _oneOccurrence =
      widget.occurrenceDay != null && _hasRecurringSeries;
  bool _busy = false;
  String? _timeError;

  @override
  void dispose() {
    _advanced.dispose();
    for (final c in [_title, _description, _target, _unit, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Asks for a custom category name and selects it.
  Future<void> _newCategory() async {
    var input = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(dialog.plannerText('newCategory')),
        content: TextField(
          key: const ValueKey('editor-category-name'),
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: dialog.plannerText('categoryName'),
            counterText: '',
          ),
          onChanged: (value) => input = value,
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(dialog.plannerText('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input),
            child: Text(dialog.plannerText('save')),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty && mounted) setState(() => _category = trimmed);
  }

  String _time(int value) =>
      TimeOfDay(hour: value ~/ 60, minute: value % 60).format(context);
  Future<void> _chooseTime(int value, ValueChanged<int> onChanged) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (picked != null && mounted) {
      setState(() {
        onChanged(picked.hour * 60 + picked.minute);
        _timeError = null;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      _advanced.expand();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await Scrollable.ensureVisible(
        invalid.first.context,
        duration: const Duration(milliseconds: 200),
        alignment: .2,
      );
      return;
    }
    if (_scheduled && _end == _start) {
      setState(() => _timeError = context.plannerText('invalidEndTime'));
      return;
    }
    if ((_recurrence == PlannerRecurrence.weekdays ||
            _recurrence == PlannerRecurrence.weekly) &&
        _weekdays.isEmpty) {
      setState(() => _timeError = context.plannerText('selectRepeatDay'));
      return;
    }
    final item = PlannerItem(
      id: widget.item?.id ?? const Uuid().v4(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category,
      date: DateTime(_date.year, _date.month, _date.day),
      startMinute: _scheduled ? _start : null,
      endMinute: _scheduled ? _end : null,
      overnight: _scheduled && _overnight,
      recurrence: _recurrence,
      weekdays: _weekdays.toList()..sort(),
      everyWeeks: plannerParseNumber(_interval.text)?.toInt() ?? 1,
      reminder: PlannerReminder(
        enabled: _reminder,
        minute: _reminder ? _reminderMinute : null,
        sound: _sound,
        vibrate: _vibrate,
      ),
      steps: const [],
      target: _target.text.trim().isEmpty
          ? null
          : plannerParseNumber(_target.text)!.toDouble(),
      unit: _unit.text.trim(),
      dependencies: _dependencies.toList(),
      xp: 0,
    );
    final controller = context.read<PlannerController>();
    if (!mounted) return;
    setState(() => _busy = true);
    final success = await plannerAction(
      context,
      () => controller.saveItem(
        item,
        occurrenceDay: _oneOccurrence ? widget.occurrenceDay : null,
      ),
      success: widget.item == null
          ? context.plannerText('addedPlanner')
          : context.plannerText('activityUpdated'),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await plannerConfirm(
      context,
      title: context.plannerText('deleteActivityQuestion'),
      message: _oneOccurrence
          ? context.plannerText('deleteOccurrenceInfo')
          : context.plannerText('deleteSeriesInfo'),
      action: context.plannerText('delete'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final success = await plannerAction(
      context,
      () => context.read<PlannerController>().deleteItem(
        widget.item!.id,
        occurrenceDay: _oneOccurrence ? widget.occurrenceDay : null,
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = context
        .watch<PlannerController>()
        .items
        .where((i) => i.id != widget.item?.id)
        .toList();
    // Defaults first, then names the user typed for other routines.
    final categories = {
      'Personal',
      'Study',
      'Work',
      'Fitness',
      'Rest',
      ...others.map((i) => i.category).where((c) => c.trim().isNotEmpty),
      _category,
    }.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item == null
              ? context.plannerText(
                  _scheduled ? 'createActivity' : 'createTask',
                )
              : context.plannerText('editActivity'),
        ),
        actions: [
          if (widget.item != null)
            IconButton(
              tooltip: context.plannerText('deleteActivity'),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.edit_outlined),
                  labelText: context.plannerText('title'),
                  hintText: context.plannerText('titleHint'),
                  counterText: '',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.plannerText('invalidActivityTitle')
                    : null,
              ),
              const SizedBox(height: 16),
              PlannerGroup(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.calendar_today_rounded,
                      color: context.tokens.muted,
                    ),
                    title: Text(
                      plannerLocalDate(context, _date, weekday: true),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.tokens.muted,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: Icon(
                      Icons.schedule_rounded,
                      color: context.tokens.muted,
                    ),
                    title: Text(context.plannerText('scheduledBlock')),
                    value: _scheduled,
                    onChanged: (v) => setState(() => _scheduled = v),
                  ),
                ],
              ),
              if (_scheduled) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _chooseTime(_start, (v) => _start = v),
                        child: Text(
                          context.plannerText('startTime', {
                            'time': _time(_start),
                          }),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _chooseTime(_end, (v) => _end = v),
                        child: Text(
                          '${context.plannerText('endTime', {'time': _time(_end)})}'
                          '${_overnight ? ' ${context.plannerText('nextDaySuffix')}' : ''}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_end != _start)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ActivityTimelinePreview(
                      startMinute: _start,
                      endMinute: _end,
                      overnight: _overnight,
                      title: _title.text,
                    ),
                  ),
              ],
              if (widget.occurrenceDay != null && _hasRecurringSeries) ...[
                DropdownButtonFormField<bool>(
                  isExpanded: true,
                  initialValue: _oneOccurrence,
                  decoration: InputDecoration(
                    labelText: context.plannerText('applyChangesTo'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: false,
                      child: Text(context.plannerText('entireSeries')),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(context.plannerText('onlyOccurrence')),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _oneOccurrence = v!;
                    _date = _oneOccurrence
                        ? widget.date ?? widget.item!.date
                        : _baseItem!.date;
                  }),
                ),
                const SizedBox(height: 18),
              ],
              if (!_oneOccurrence) ...[
                DropdownButtonFormField<PlannerRecurrence>(
                  isExpanded: true,
                  initialValue: _recurrence,
                  decoration: InputDecoration(
                    labelText: context.plannerText('repeat'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: PlannerRecurrence.once,
                      child: Text(context.plannerText('onceOnly')),
                    ),
                    DropdownMenuItem(
                      value: PlannerRecurrence.daily,
                      child: Text(context.plannerText('everyDay')),
                    ),
                    DropdownMenuItem(
                      value: PlannerRecurrence.weekdays,
                      child: Text(context.plannerText('selectedWeekdays')),
                    ),
                    DropdownMenuItem(
                      value: PlannerRecurrence.weekly,
                      child: Text(context.plannerText('everyNWeeks')),
                    ),
                  ],
                  onChanged: (v) => setState(() => _recurrence = v!),
                ),
                if (_recurrence == PlannerRecurrence.weekdays ||
                    _recurrence == PlannerRecurrence.weekly)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 1; i <= 7; i++)
                          FilterChip(
                            label: Text(
                              plannerWeekday(context, i),
                            ),
                            selected: _weekdays.contains(i),
                            onSelected: (v) => setState(() {
                              v ? _weekdays.add(i) : _weekdays.remove(i);
                            }),
                          ),
                      ],
                    ),
                  ),
                if (_recurrence == PlannerRecurrence.weekly)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.plannerText('repeatWeeks'),
                      ),
                      validator: (v) =>
                          (plannerParseNumber(v ?? '')?.toInt() ?? 0) < 1 ||
                              (plannerParseNumber(v ?? '')?.toInt() ?? 0) > 52
                          ? context.plannerText('invalidWeeks')
                          : null,
                    ),
                  ),
              ],
              if (_timeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _timeError!,
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              const SizedBox(height: 16),
              PlannerGroup(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: Icon(
                      Icons.notifications_none_rounded,
                      color: context.tokens.muted,
                    ),
                    title: Text(context.plannerText('remindMe')),
                    value: _reminder,
                    onChanged: (v) async {
                      setState(() => _reminder = v);
                      if (v) await requestPlannerReminderAccess(context);
                    },
                  ),
                  if (_reminder) ...[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      leading: Icon(
                        Icons.alarm_rounded,
                        color: context.tokens.muted,
                      ),
                      title: Text(
                        context.plannerText('reminderTimeAt', {
                          'time': _time(_reminderMinute),
                        }),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: context.tokens.muted,
                      ),
                      onTap: () => _chooseTime(
                        _reminderMinute,
                        (v) => _reminderMinute = v,
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      leading: Icon(
                        Icons.volume_up_outlined,
                        color: context.tokens.muted,
                      ),
                      title: Text(context.plannerText('reminderSound')),
                      subtitle: Text(
                        _soundName.isNotEmpty
                            ? plannerSoundName(context, _soundName)
                            : _sound == 'default' || _sound.isEmpty
                            ? context.plannerText('defaultSoundPreview')
                            : context.plannerText('selectedSystemTone'),
                        style: TextStyle(color: context.tokens.muted),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: context.tokens.muted,
                      ),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      secondary: Icon(
                        Icons.vibration_outlined,
                        color: context.tokens.muted,
                      ),
                      title: Text(context.plannerText('vibrate')),
                      value: _vibrate,
                      onChanged: (v) => setState(() => _vibrate = v),
                    ),
                  ],
                ],
              ),
              if (_reminder) ...[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: context.plannerText('androidReminderInfo'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        content: Text(
                          dialog.plannerText('androidReminderInfo'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: Text(dialog.plannerText('acknowledged')),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.info_outline, size: 20),
                  ),
                ),
              ],
              ExpansionTile(
                controller: _advanced,
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                maintainState: true,
                title: Text(context.plannerText('advanced')),
                children: [
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.plannerText('descriptionOptional'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  PlannerSection(context.plannerText('category')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in categories)
                        ChoiceChip(
                          label: Text(plannerCategory(context, name)),
                          selected: _category == name,
                          onSelected: (_) => setState(() => _category = name),
                        ),
                      ActionChip(
                        key: const ValueKey('editor-new-category'),
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: Text(context.plannerText('newCategory')),
                        onPressed: _newCategory,
                      ),
                    ],
                  ),
                  PlannerSection(context.plannerText('measuredProgress')),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _target,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: context.plannerText('optionalTarget'),
                            hintText: context.plannerText('targetExample'),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final number = plannerParseNumber(v);
                            return number == null ||
                                    !number.isFinite ||
                                    number <= 0
                                ? context.plannerText('positiveTarget')
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _unit,
                          decoration: InputDecoration(
                            labelText: context.plannerText('unit'),
                            hintText: context.plannerText('unitHint'),
                          ),
                          validator: (v) =>
                              _target.text.isNotEmpty &&
                                  (v == null || v.trim().isEmpty)
                              ? context.plannerText('addUnit')
                              : null,
                        ),
                      ),
                    ],
                  ),
                  if (others.isNotEmpty) ...[
                    PlannerSection(
                      context.plannerText('prerequisitesOptional'),
                    ),
                    Text(
                      context.plannerText('prerequisiteInfo'),
                      style: TextStyle(
                        color: context.tokens.muted,
                        fontSize: 13,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: others
                          .map(
                            (i) => FilterChip(
                              label: Text(i.title),
                              selected: _dependencies.contains(i.id),
                              onSelected: (v) => setState(() {
                                v
                                    ? _dependencies.add(i.id)
                                    : _dependencies.remove(i.id);
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _busy
                      ? context.plannerText('saving')
                      : context.plannerText(
                          _scheduled ? 'saveActivity' : 'saveTask',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small, non-interactive view of the same civil-time interval being edited.
/// It does not create an occurrence or change the user's schedule.
class ActivityTimelinePreview extends StatelessWidget {
  const ActivityTimelinePreview({
    super.key,
    required this.startMinute,
    required this.endMinute,
    required this.overnight,
    required this.title,
  });
  final int startMinute;
  final int endMinute;
  final bool overnight;
  final String title;

  @override
  Widget build(BuildContext context) {
    final finish = endMinute + (overnight ? 1440 : 0);
    final duration = finish - startMinute;
    if (duration <= 0) return const SizedBox.shrink();
    final from = ((startMinute ~/ 60 - 1) * 60).clamp(0, 1440);
    final until = ((finish / 60).ceil() + 1) * 60;
    final span = until - from;
    final step = span > 720
        ? 360
        : span > 360
        ? 180
        : 60;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = 144.0 * scale.clamp(1, 1.5);
    final rail = 84.0 * scale.clamp(1, 1.4);
    String time(int minute) => TimeOfDay(
      hour: (minute ~/ 60) % 24,
      minute: minute % 60,
    ).format(context);
    final interval = '${time(startMinute)} – ${time(endMinute)}';
    return Semantics(
      label:
          '$title, $interval, ${plannerNumber(context, duration)} ${context.plannerText('minutes')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height + 18,
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: rail,
                    top: 8,
                    bottom: 8,
                    child: SizedBox(
                      width: 1,
                      child: ColoredBox(color: context.colors.outlineVariant),
                    ),
                  ),
                  for (var minute = from; minute <= until; minute += step)
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      top: (minute - from) / span * height,
                      child: Row(
                        children: [
                          SizedBox(
                            width: rail - 8,
                            child: Text(
                              time(minute),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.tokens.muted),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 8,
                            height: 1,
                            child: ColoredBox(
                              color: context.colors.outlineVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  PositionedDirectional(
                    start: rail + 12,
                    end: 0,
                    top: 8 + (startMinute - from) / span * height,
                    height: (duration / span * height).clamp(8, height),
                    child: Container(
                      key: const ValueKey('activity-preview-event'),
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.primary.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(10),
                        border: BorderDirectional(
                          start: BorderSide(
                            color: context.colors.primary,
                            width: 3,
                          ),
                        ),
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      child: duration / span * height > 32
                          ? Text(
                              title.isEmpty
                                  ? context.plannerText('scheduledBlock')
                                  : title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.timelapse_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${plannerNumber(context, duration)} ${context.plannerText('minutes')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
