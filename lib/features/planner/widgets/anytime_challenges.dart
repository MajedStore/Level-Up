import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';

/// Today's challenge tasks that have no set time. Timed ones sit on the
/// schedule; these get a swipeable row with a one-tap complete button.
List<PlannerOccurrence> anytimeChallengesToday(PlannerController c) => c
    .occurrences(plannerDay(c.now))
    .where((o) => o.isChallenge && o.start == null)
    .toList();

class AnytimeChallengeStrip extends StatelessWidget {
  const AnytimeChallengeStrip({super.key, required this.onOpen});
  final ValueChanged<PlannerOccurrence> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final tasks = anytimeChallengesToday(c);
    if (tasks.isEmpty) return const SizedBox.shrink();
    final done = tasks
        .where((o) => o.record.status != CompletionStatus.pending)
        .length;
    final text = Theme.of(context).textTheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      key: const ValueKey('anytime-challenges'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.plannerText('anytimeToday'),
                  style: text.labelLarge?.copyWith(
                    color: context.tokens.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${plannerNumber(context, done)}/${plannerNumber(context, tasks.length)}',
                style: text.labelLarge?.copyWith(color: context.tokens.muted),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 72 * scale.clamp(1, 1.6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) =>
                _AnytimeCard(occurrence: tasks[i], onOpen: onOpen),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _AnytimeCard extends StatelessWidget {
  const _AnytimeCard({required this.occurrence, required this.onOpen});
  final PlannerOccurrence occurrence;
  final ValueChanged<PlannerOccurrence> onOpen;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final c = context.read<PlannerController>();
    final status = o.record.status;
    final pending = status == CompletionStatus.pending;
    final package = c.instances.where((i) => i.id == o.challengeId).firstOrNull;
    final title = plannerOccurrenceTitle(context, o);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 240,
      child: Material(
        key: ValueKey('anytime-${o.id}'),
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onOpen(o),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: status == CompletionStatus.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (package != null)
                        Text(
                          plannerTemplateName(context, package.snapshot),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: context.tokens.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('anytime-complete-${o.id}'),
                  tooltip: context.plannerText('markComplete'),
                  // A measured task needs its amount, so it opens instead.
                  onPressed: !pending
                      ? null
                      : o.item.target != null
                      ? () => onOpen(o)
                      : () => plannerAction(context, () => c.complete(o.id)),
                  icon: Icon(
                    status == CompletionStatus.completed
                        ? Icons.check_circle_rounded
                        : status == CompletionStatus.skipped
                        ? Icons.do_not_disturb_on_outlined
                        : Icons.radio_button_unchecked_rounded,
                    size: 28,
                    color: status == CompletionStatus.completed
                        ? context.tokens.success
                        : status == CompletionStatus.skipped
                        ? context.tokens.warning
                        : context.colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
