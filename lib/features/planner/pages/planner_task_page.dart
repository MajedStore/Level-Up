import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';
import 'package:streak/features/planner/pages/planner_editor_page.dart';

class PlannerTaskPage extends StatefulWidget {
  const PlannerTaskPage({super.key, required this.occurrence});
  final PlannerOccurrence occurrence;
  @override
  State<PlannerTaskPage> createState() => _PlannerTaskPageState();
}

class _PlannerTaskPageState extends State<PlannerTaskPage> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await plannerAction(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _amount(PlannerOccurrence o) async {
    final text = TextEditingController(
      text: o.record.amount == 0 ? '' : '${o.record.amount}',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => _AmountDialog(
        controller: text,
        unit: plannerUnit(context, o.item.unit),
      ),
    );
    text.dispose();
    if (value != null && mounted) {
      await _run(
        () => context.read<PlannerController>().recordAmount(o.id, value),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlannerController>();
    final occurrence =
        controller.occurrenceById(widget.occurrence.id) ?? widget.occurrence;
    final o = occurrence;
    final pending = o.record.status == CompletionStatus.pending;
    final package = controller.instances
        .where((i) => i.id == o.challengeId)
        .firstOrNull;
    final legacyRewards =
        o.isChallenge &&
        package?.snapshot.rewardMode == ChallengeRewardMode.legacyPerTask;
    final definition = package?.snapshot.tasks
        .where((task) => '${package.id}/${task.id}' == o.itemId)
        .firstOrNull;
    final actionable =
        pending &&
        (!o.isChallenge || package?.status == ChallengeStatus.active) &&
        !plannerDay(o.day).isAfter(plannerDay(controller.now));
    final conflicts = controller.conflictsFor(o);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.plannerText('taskDetails')),
        actions: [
          if (!o.isChallenge)
            IconButton(
              tooltip: context.plannerText('editActivity'),
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PlannerEditorPage(
                            item: o.item,
                            date: o.day,
                            occurrenceDay: DateTime.parse(
                              o.id.substring(o.id.lastIndexOf('@') + 1),
                            ),
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      if (controller.occurrenceById(o.id) == null) {
                        Navigator.pop(context);
                      } else {
                        setState(() {});
                      }
                    },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PlannerPill(
                o.isChallenge
                    ? context.plannerText('challengeTask')
                    : context.plannerText('routineTask'),
                color: o.isChallenge ? context.colors.primary : null,
              ),
              PlannerPill(
                context.plannerText(o.record.status.name),
                color: pending
                    ? context.tokens.muted
                    : o.record.status == CompletionStatus.completed
                    ? context.tokens.success
                    : context.tokens.warning,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            plannerOccurrenceTitle(context, o),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
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
                title: Text(plannerLocalDate(context, o.day, weekday: true)),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  Icons.schedule_rounded,
                  color: context.tokens.muted,
                ),
                title: Text(plannerInterval(o, context: context)),
              ),
            ],
          ),
          if (o.item.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                o.item.description,
                style: const TextStyle(height: 1.6),
              ),
            ),
          const SizedBox(height: 18),
          if (legacyRewards)
            PlannerPanel(
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: context.colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.plannerText('rewardOnce', {
                        'xp': plannerNumber(context, o.item.xp),
                      }),
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            PlannerPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.tokens.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.plannerText('overlapNames', {
                        'names': conflicts
                            .map((x) => plannerOccurrenceTitle(context, x))
                            .join(', '),
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (o.item.dependencies.isNotEmpty) ...[
            PlannerSection(context.plannerText('prerequisites')),
            Text(
              context.plannerText('prerequisitesInfo'),
              style: TextStyle(color: context.tokens.muted, height: 1.5),
            ),
          ],
          PlannerSection(context.plannerText('remind')),
          PlannerGroup(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                leading: Icon(
                  Icons.notifications_none_rounded,
                  color: context.tokens.muted,
                ),
                title: Text(
                  o.item.reminder.enabled
                      ? context.plannerText('reminderEnabled')
                      : context.plannerText('noReminder'),
                ),
                subtitle: Text(
                  o.item.reminder.enabled
                      ? context.plannerText('adjustReminder')
                      : context.plannerText('chooseReminder'),
                  style: TextStyle(color: context.tokens.muted),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: context.tokens.muted,
                ),
                onTap: _busy
                    ? null
                    : () async {
                        final edit = await editPlannerReminder(context, o);
                        if (edit != null && mounted) {
                          await _run(
                            () => controller.setReminder(
                              o.id,
                              edit.reminder,
                              entireSeries: edit.entireSeries,
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
          if (o.item.steps.isNotEmpty) ...[
            PlannerSection(
              context.plannerText('stepsProgress', {
                'done': plannerNumber(context, o.record.completedSteps.length),
                'total': plannerNumber(context, o.item.steps.length),
              }),
            ),
            PlannerPanel(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var index = 0; index < o.item.steps.length; index++)
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      value: o.record.completedSteps.contains(index),
                      onChanged:
                          !actionable ||
                              _busy ||
                              o.record.completedSteps.contains(index)
                          ? null
                          : (_) => _run(
                              () => controller.completeStep(o.id, index),
                            ),
                      title: Text(
                        '${plannerNumber(context, index + 1)}. ${plannerOccurrenceStep(context, o, index)}',
                      ),
                      subtitle:
                          pending &&
                              index > 0 &&
                              !o.record.completedSteps.contains(index - 1)
                          ? Text(context.plannerText('previousStepFirst'))
                          : null,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
          ],
          if (o.item.target != null) ...[
            PlannerSection(context.plannerText('measuredProgress')),
            PlannerPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.plannerText('amountProgress', {
                      'amount': plannerNumber(context, o.record.amount),
                      'target': plannerNumber(context, o.item.target!),
                      'unit': plannerUnit(context, o.item.unit),
                    }),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (o.record.amount / o.item.target!).clamp(0, 1),
                  ),
                  if (actionable)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _amount(o),
                        icon: const Icon(Icons.add_chart_rounded),
                        label: Text(context.plannerText('recordAmount')),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (pending && !actionable)
            Text(
              o.isChallenge && package?.status != ChallengeStatus.active
                  ? context.plannerText('endedPackageInfo')
                  : context.plannerText('availableOn', {
                      'date': plannerLocalDate(context, o.day, weekday: true),
                    }),
              style: TextStyle(color: context.tokens.muted),
            ),
          if (actionable)
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() => controller.complete(o.id)),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(context.plannerText('markComplete')),
            ),
          if (actionable && o.isChallenge)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final configured = controller.skipPenaltyFor(o);
                        final penalty = configured > controller.balance
                            ? controller.balance
                            : configured;
                        final confirmed = await plannerConfirm(
                          context,
                          title: context.plannerText('skipTaskQuestion'),
                          message:
                              '${context.plannerText('skipDeduction', {'xp': plannerNumber(context, penalty)})}\n${context.plannerText(definition != null && !package!.snapshot.isRequired(definition) ? 'skipOptionalPackageTaskInfo' : 'skipPackageTaskInfo')}',
                          action: context.plannerText('skipTask'),
                        );
                        if (confirmed && mounted) {
                          await _run(() => controller.skip(o.id));
                        }
                      },
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(
                  context.plannerText(
                    controller.skipPenaltyFor(o) > 0
                        ? 'skipWithPenalty'
                        : 'skipTask',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.controller, required this.unit});
  final TextEditingController controller;
  final String unit;
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.plannerText('recordTotalAmount')),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: widget.controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: context.plannerText('totalCompleted'),
          suffixText: widget.unit,
          helperText: context.plannerText('totalNotAdditional'),
        ),
        validator: (raw) {
          final amount = plannerParseNumber(raw ?? '');
          return amount == null || !amount.isFinite || amount < 0
              ? context.plannerText('nonnegativeAmount')
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.plannerText('goBack')),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              plannerParseNumber(widget.controller.text)!.toDouble(),
            );
          }
        },
        child: Text(context.plannerText('saveAmount')),
      ),
    ],
  );
}
