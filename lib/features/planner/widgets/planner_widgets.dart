import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';

String plannerDate(DateTime day, {BuildContext? context}) => context == null
    ? DateFormat('EEEE, d MMMM', 'en').format(day)
    : plannerLocalDate(context, day, weekday: true);
String plannerTime(DateTime? time, {BuildContext? context}) => time == null
    ? (context?.plannerText('anyTime') ?? 'Any time')
    : context == null
    ? DateFormat.Hm('en').format(time)
    : TimeOfDay.fromDateTime(time).format(context);
String plannerInterval(PlannerOccurrence occurrence, {BuildContext? context}) =>
    occurrence.start == null
    ? (context?.plannerText('anyTime') ?? 'Any time')
    : '${plannerTime(occurrence.start, context: context)} – ${plannerTime(occurrence.end, context: context)}${occurrence.item.overnight ? ' ${context?.plannerText('nextDaySuffix') ?? '(+1 day)'}' : ''}';
String capitalized(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

Future<bool> plannerConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.plannerText('goBack')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action ?? context.plannerText('confirm')),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> plannerAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(plannerError(context, error))));
    }
    return false;
  }
}

class PlannerPanel extends StatelessWidget {
  const PlannerPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool accent;
  @override
  Widget build(BuildContext context) => Material(
    color: accent
        ? context.colors.primary.withValues(alpha: .08)
        : context.colors.surfaceContainer,
    borderRadius: BorderRadius.circular(14),
    child: Padding(padding: padding, child: child),
  );
}

class PlannerSection extends StatelessWidget {
  const PlannerSection(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class PlannerTag extends StatelessWidget {
  const PlannerTag(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      if (icon != null)
        Icon(icon, size: 16, color: color ?? context.colors.primary),
      Text(
        label,
        style: TextStyle(color: color ?? context.tokens.muted, fontSize: 13),
      ),
    ],
  );
}

class PlannerOutcomeSummary extends StatelessWidget {
  const PlannerOutcomeSummary({
    super.key,
    required this.completionXp,
    required this.failurePenalty,
    this.skipPenalty,
  });
  final int completionXp;
  final int failurePenalty;
  final int? skipPenalty;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      PlannerTag(
        '${context.plannerText('completionShort')} +${plannerNumber(context, completionXp)} ${context.plannerText('xp')}',
        icon: Icons.check_circle_outline,
      ),
      PlannerTag(
        '${context.plannerText('failureShort')} −${plannerNumber(context, failurePenalty)} ${context.plannerText('xp')}',
        icon: Icons.cancel_outlined,
      ),
      if (skipPenalty != null)
        PlannerTag(
          '${context.plannerText('taskSkipShort')} −${plannerNumber(context, skipPenalty!)} ${context.plannerText('xp')}',
          icon: Icons.skip_next_outlined,
        ),
    ],
  );
}

/// Timeline and challenge list use the same occurrence ID and completion record.
class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({
    super.key,
    required this.occurrence,
    required this.onTap,
  });
  final PlannerOccurrence occurrence;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final done = o.record.status == CompletionStatus.completed;
    final skipped = o.record.status == CompletionStatus.skipped;
    final conflict = context
        .read<PlannerController>()
        .conflictsFor(o)
        .isNotEmpty;
    final identity = context.plannerText(
      o.isChallenge ? 'challengeTask' : 'routineTask',
    );
    return Semantics(
      label: '$identity, ${context.plannerText(o.record.status.name)}',
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        minLeadingWidth: 24,
        leading: Tooltip(
          message: identity,
          child: Icon(
            done
                ? Icons.check_circle_outline_rounded
                : skipped
                ? Icons.do_not_disturb_on_outlined
                : o.isChallenge
                ? Icons.emoji_events_outlined
                : Icons.schedule_rounded,
            color: done
                ? context.tokens.success
                : skipped
                ? context.tokens.warning
                : o.isChallenge
                ? context.colors.primary
                : context.tokens.muted,
          ),
        ),
        title: Text(
          plannerOccurrenceTitle(context, o),
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(plannerInterval(o, context: context)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.isChallenge && o.record.status != CompletionStatus.pending)
              Tooltip(
                message: identity,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Icon(
                    Icons.emoji_events_outlined,
                    size: 18,
                    color: context.colors.primary,
                  ),
                ),
              ),
            if (conflict)
              Tooltip(
                message: context.plannerText('timeConflict'),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 19,
                  color: context.tokens.warning,
                ),
              ),
            if (o.item.reminder.enabled)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Tooltip(
                  message: context.plannerText('remind'),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 19,
                    color: context.tokens.muted,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class PlannerEmpty extends StatelessWidget {
  const PlannerEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.action,
    this.label,
  });
  final String title;
  final String message;
  final VoidCallback action;
  final String? label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(message, style: TextStyle(color: context.tokens.muted)),
          ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: action,
          icon: const Icon(Icons.add_rounded),
          label: Text(label ?? context.plannerText('createActivity')),
        ),
      ],
    ),
  );
}
