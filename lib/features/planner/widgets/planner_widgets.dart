import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';

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
        ? context.colors.primary.withValues(alpha: .12)
        : context.colors.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(plannerRadius),
    child: Padding(padding: padding, child: child),
  );
}

/// Corner radius shared by grouped surfaces, matching the sign-in fields'
/// rounded look at a slightly larger size for multi-row groups.
const plannerRadius = 18.0;

/// A rounded, filled surface that holds related rows: the same surface as
/// the sign-in fields. Rows are separated by thin inset dividers unless
/// [dividers] is false (for rows that may render empty).
class PlannerGroup extends StatelessWidget {
  const PlannerGroup({
    super.key,
    required this.children,
    this.dividers = true,
    this.dividerIndent = 56,
  });
  final List<Widget> children;
  final bool dividers;
  final double dividerIndent;
  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(plannerRadius),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 && dividers)
            Divider(
              height: 1,
              thickness: .5,
              indent: dividerIndent,
              color: context.colors.outlineVariant,
            ),
          children[i],
        ],
      ],
    ),
  );
}

/// A rounded status chip with a coloured dot.
class PlannerPill extends StatelessWidget {
  const PlannerPill(this.label, {super.key, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color ?? context.tokens.muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: context.tokens.muted),
          ),
        ),
      ],
    ),
  );
}

/// A small tinted rounded square holding an icon: the leading mark for
/// package and assignment rows.
class PlannerIconTile extends StatelessWidget {
  const PlannerIconTile(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: tint),
    );
  }
}

/// A navigation/action row: icon, label, optional trailing value. Meant to
/// sit inside a [PlannerGroup].
class PlannerMenuRow extends StatelessWidget {
  const PlannerMenuRow({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.trailing,
    this.color,
    this.chevron = true,
    this.onTap,
  });
  final String label;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final Color? color;
  final bool chevron;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final foreground = color ?? context.colors.onSurface;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child:
                      leading ??
                      Icon(
                        icon,
                        size: 22,
                        color: color ?? context.tokens.muted,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: onTap == null
                        ? foreground.withValues(alpha: .4)
                        : foreground,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                DefaultTextStyle.merge(
                  style: TextStyle(color: context.tokens.muted),
                  child: trailing!,
                ),
              ],
              if (chevron) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.tokens.muted,
                  textDirection: Directionality.of(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PlannerSection extends StatelessWidget {
  const PlannerSection(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.tokens.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
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
    this.tile = true,
  });
  final PlannerOccurrence occurrence;
  final VoidCallback onTap;

  /// Standalone rows draw their own rounded surface; rows inside a
  /// [PlannerGroup] pass false and use the group's surface.
  final bool tile;
  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final done = o.record.status == CompletionStatus.completed;
    final skipped = o.record.status == CompletionStatus.skipped;
    final identity = context.plannerText(
      o.isChallenge ? 'challengeTask' : 'routineTask',
    );
    final row = Semantics(
      label: '$identity, ${context.plannerText(o.record.status.name)}',
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.tokens.muted,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
    if (!tile) return row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: row,
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
