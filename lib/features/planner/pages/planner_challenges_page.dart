import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/pages/planner_package_editor_page.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';

/// A package presents the user's saved task order within each occurrence day.
/// The chronological Schedule remains a separate derived view of these IDs.
List<PlannerOccurrence> packageOccurrencesInOrder(
  ChallengeInstance instance,
  Iterable<PlannerOccurrence> occurrences,
) {
  final order = {
    for (var i = 0; i < instance.snapshot.tasks.length; i++)
      '${instance.id}/${instance.snapshot.tasks[i].id}': i,
  };
  return occurrences.toList()..sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0
        ? byDay
        : (order[a.itemId] ?? 0).compareTo(order[b.itemId] ?? 0);
  });
}

class TomorrowAssignmentTile extends StatelessWidget {
  const TomorrowAssignmentTile({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final tomorrow = plannerAddDays(plannerDay(c.now), 1);
    final selection = c.selectionFor(tomorrow);
    final instance = c.instances
        .where((i) => i.id == selection?.instanceId)
        .firstOrNull;
    final deducted = -c.ledger
        .where(
          (e) => e.idempotencyKey == 'missed_selection:${selection?.dateKey}',
        )
        .fold<int>(0, (n, e) => n + e.change);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        instance == null ? Icons.flag_outlined : Icons.emoji_events_outlined,
      ),
      title: Text(
        context.plannerText(
          instance != null
              ? 'selectedForTomorrow'
              : selection?.isMissed == true
              ? 'selectionMissed'
              : 'chooseTomorrow',
        ),
      ),
      subtitle: Text(
        instance == null
            ? selection?.isMissed == true
                  ? '${plannerLocalDate(context, tomorrow)} · ${context.plannerText('selectionPenaltyApplied', {'xp': plannerNumber(context, deducted)})}'
                  : plannerLocalDate(context, tomorrow, weekday: true)
            : plannerTemplateName(context, instance.snapshot),
      ),
      trailing: selection?.isMissed == true
          ? null
          : const Icon(Icons.chevron_right),
      onTap: instance != null
          ? () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ChallengeInstancePage(instanceId: instance.id),
              ),
            )
          : selection?.isMissed == true
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const PackageSelectionPage(),
              ),
            ),
    );
  }
}

class PlannerChallengesPage extends StatefulWidget {
  const PlannerChallengesPage({super.key});
  @override
  State<PlannerChallengesPage> createState() => _PlannerChallengesPageState();
}

class _PlannerChallengesPageState extends State<PlannerChallengesPage> {
  bool _history = false;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    return ListView(
      key: const PageStorageKey('challenges'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        const TomorrowAssignmentTile(),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(context.plannerText('templates')),
            ),
            ButtonSegment(
              value: true,
              label: Text(context.plannerText('history')),
            ),
          ],
          selected: {_history},
          onSelectionChanged: (v) => setState(() => _history = v.first),
        ),
        const SizedBox(height: 16),
        if (!_history) ...[
          for (final t in c.templates) _TemplateRow(template: t),
          if (c.templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(context.plannerText('emptyTemplates')),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const PlannerPackageEditorPage(),
              ),
            ),
            icon: const Icon(Icons.add),
            label: Text(context.plannerText('createPackage')),
          ),
        ] else ...[
          if (c.instances.isEmpty) Text(context.plannerText('noHistory')),
          for (final i in c.instances.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(plannerTemplateName(context, i.snapshot)),
              subtitle: Text(
                '${plannerLocalDate(context, i.startDate)} · ${context.plannerText(i.status.name)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChallengeInstancePage(instanceId: i.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String packageSummary(BuildContext context, ChallengeTemplate template) =>
    context.plannerText('packageSummaryShort', {
      'count': plannerNumber(
        context,
        template.tasks.where((t) => !t.isGroup).length,
      ),
      'xp': plannerNumber(context, template.totalPossibleXp),
    });

String _packageCategory(BuildContext context, ChallengeTemplate template) =>
    template.categoryName.trim().isEmpty
    ? context.plannerText('noCategory')
    : template.categoryName;

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, this.selection = false});
  final ChallengeTemplate template;
  final bool selection;
  @override
  Widget build(BuildContext context) {
    final t = template;
    final c = context.read<PlannerController>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(plannerTemplateName(context, t)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_packageCategory(context, t)} · ${context.plannerText('packageTaskCount', {'count': plannerNumber(context, t.leafTasks.length)})}',
          ),
          const SizedBox(height: 8),
          PlannerOutcomeSummary(
            completionXp: t.totalPossibleXp,
            failurePenalty: t.failurePenalty,
            skipPenalty: t.skipPenalty,
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChallengePreviewPage(template: t),
        ),
      ),
      trailing: selection
          ? const Icon(Icons.chevron_right)
          : PopupMenuButton<String>(
              tooltip: context.plannerText('editPackage'),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.plannerText('edit')),
                ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(context.plannerText('duplicate')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.plannerText('delete')),
                ),
              ],
              onSelected: (value) async {
                if (value == 'edit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlannerPackageEditorPage(template: t),
                    ),
                  );
                } else if (value == 'duplicate') {
                  await plannerAction(context, () async {
                    await c.duplicateTemplate(
                      t.id,
                      name: '${t.name} (${context.plannerText('duplicate')})',
                    );
                  });
                } else if (await plannerConfirm(
                  context,
                  title: context.plannerText('confirmDelete'),
                  message: context.plannerText('deleteTemplateInfo'),
                  action: context.plannerText('delete'),
                )) {
                  if (context.mounted) {
                    await plannerAction(context, () => c.deleteTemplate(t.id));
                  }
                }
              },
            ),
    );
  }
}

class PackageSelectionPage extends StatelessWidget {
  const PackageSelectionPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final target = plannerAddDays(plannerDay(c.now), 1);
    final selected = c.selectionFor(target);
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('choosePackage'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.plannerText('selectForDate', {
              'date': plannerLocalDate(context, target, weekday: true),
            }),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            context.plannerText('selectionRulesInfo', {
              'time': selected == null
                  ? TimeOfDay(
                      hour: c.selectionDeadlineMinute ~/ 60,
                      minute: c.selectionDeadlineMinute % 60,
                    ).format(context)
                  : TimeOfDay.fromDateTime(
                      selected.deadline.toLocal(),
                    ).format(context),
              'xp': plannerNumber(
                context,
                selected?.penalty ?? c.missedSelectionPenalty,
              ),
            }),
          ),
          const SizedBox(height: 16),
          if (selected?.isSelected == true)
            const TomorrowAssignmentTile()
          else if (selected?.isMissed == true)
            Text(context.plannerText('selectionMissed'))
          else ...[
            for (final t in c.templates)
              _TemplateRow(template: t, selection: true),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const PlannerPackageEditorPage(),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(context.plannerText('createPackage')),
            ),
          ],
        ],
      ),
    );
  }
}

class ChallengePreviewPage extends StatefulWidget {
  const ChallengePreviewPage({super.key, required this.template});
  final ChallengeTemplate template;
  @override
  State<ChallengePreviewPage> createState() => _ChallengePreviewPageState();
}

class _ChallengePreviewPageState extends State<ChallengePreviewPage> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final t = widget.template;
    final tomorrow = plannerAddDays(plannerDay(c.now), 1);
    final deadline = plannerAddDays(tomorrow, t.durationDays);
    final selection = c.selectionFor(tomorrow);
    final locked = selection?.isSelected == true || selection?.isMissed == true;
    return Scaffold(
      appBar: AppBar(title: Text(context.plannerText('previewPackage'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            plannerTemplateName(context, t),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(_packageCategory(context, t)),
          const SizedBox(height: 8),
          Text(
            context.plannerText('packageTaskCount', {
              'count': plannerNumber(
                context,
                t.tasks.where((task) => !task.isGroup).length,
              ),
            }),
          ),
          if (t.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(plannerTemplateDescription(context, t)),
            ),
          const SizedBox(height: 16),
          Text(
            context.plannerText('selectForDate', {
              'date': plannerLocalDate(context, tomorrow, weekday: true),
            }),
          ),
          PlannerSection(context.plannerText('tasks')),
          for (final task in t.rootTasks)
            _DefinitionRow(task: task, template: t),
          PlannerSection(context.plannerText('commitment')),
          PlannerOutcomeSummary(
            completionXp: t.completionXp,
            failurePenalty: t.failurePenalty,
            skipPenalty: t.skipPenalty,
          ),
          const SizedBox(height: 8),
          Text(
            '${context.plannerText('deadline')}: ${plannerLocalDate(context, deadline)} ${TimeOfDay.fromDateTime(deadline).format(context)}',
          ),
          const SizedBox(height: 12),
          if (t.rewardMode == ChallengeRewardMode.legacyPerTask)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(context.plannerText('legacyRewardRules')),
            ),
          Text(context.plannerText('requiredTasksRule')),
          const SizedBox(height: 8),
          Text(context.plannerText('assignmentLocked')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || locked
                ? null
                : () async {
                    setState(() => _busy = true);
                    final confirmed = await plannerConfirm(
                      context,
                      title: context.plannerText('confirmAssignment'),
                      message: context.plannerText('assignmentLocked'),
                      action: context.plannerText('confirmAssignment'),
                    );
                    if (!confirmed || !context.mounted) {
                      if (mounted) setState(() => _busy = false);
                      return;
                    }
                    ChallengeInstance? instance;
                    final success = await plannerAction(context, () async {
                      instance = await c.assignTomorrow(t.id);
                    });
                    if (!context.mounted) return;
                    if (success && instance != null) {
                      await Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ChallengeInstancePage(instanceId: instance!.id),
                        ),
                      );
                    } else {
                      setState(() => _busy = false);
                    }
                  },
            child: Text(
              context.plannerText(
                locked
                    ? selection?.isMissed == true
                          ? 'selectionMissed'
                          : 'selectedForTomorrow'
                    : 'confirmAssignment',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({
    required this.task,
    required this.template,
    this.depth = 0,
  });
  final ChallengeTaskDefinition task;
  final ChallengeTemplate template;
  final int depth;
  @override
  Widget build(BuildContext context) {
    final children = template.childrenOf(task.id);
    final legacy = template.rewardMode == ChallengeRewardMode.legacyPerTask;
    final hasSavedConditions =
        task.steps.isNotEmpty ||
        task.target != null ||
        task.dependencies.isNotEmpty ||
        template.durationDays > 1;
    return ExpansionTile(
      key: PageStorageKey('preview-task-${task.id}'),
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        task.isGroup
            ? Icons.folder_outlined
            : task.startMinute == null
            ? Icons.check_circle_outline
            : Icons.schedule,
      ),
      title: Text(plannerDefinitionTitle(context, task)),
      subtitle: Text(
        task.isGroup
            ? context.plannerText('groupChildren', {
                'count': plannerNumber(context, children.length),
              })
            : task.startMinute == null
            ? context.plannerText('flexibleTask')
            : '${TimeOfDay(hour: task.startMinute! ~/ 60, minute: task.startMinute! % 60).format(context)} – ${TimeOfDay(hour: (task.startMinute! + task.durationMinutes) ~/ 60 % 24, minute: (task.startMinute! + task.durationMinutes) % 60).format(context)}',
      ),
      children: [
        if (task.isGroup) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.plannerText('groupCompletionRule')),
          ),
          for (final child in children)
            Padding(
              padding: EdgeInsetsDirectional.only(start: depth < 3 ? 12 : 0),
              child: _DefinitionRow(
                task: child,
                template: template,
                depth: depth + 1,
              ),
            ),
        ] else ...[
          if (task.description.isNotEmpty)
            ListTile(title: Text(task.description)),
          if (legacy)
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: Text(
                context.plannerText('taskRewardSummary', {
                  'xp': plannerNumber(context, task.rewardXp),
                }),
              ),
              subtitle: Text(
                context.plannerText('skipPenaltySummary', {
                  'xp': plannerNumber(context, task.skipPenalty),
                }),
              ),
            ),
          if (hasSavedConditions && !legacy)
            ListTile(title: Text(context.plannerText('preservedConditions'))),
          if (template.durationDays > 1)
            ListTile(
              title: Text(
                '${context.plannerText('taskDays')}: ${task.dayOffsets.map((d) => plannerNumber(context, d + 1)).join(', ')}',
              ),
            ),
          if (task.target != null)
            ListTile(
              title: Text(
                '${context.plannerText('target')}: ${plannerNumber(context, task.target!)} ${plannerUnit(context, task.unit)}',
              ),
            ),
          if (task.dependencies.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(context.plannerText('prerequisites')),
              subtitle: Text(
                template.tasks
                    .where((t) => task.dependencies.contains(t.id))
                    .map((t) => plannerDefinitionTitle(context, t))
                    .join(', '),
              ),
            ),
          for (var i = 0; i < task.steps.length; i++)
            ListTile(
              leading: Text(plannerNumber(context, i + 1)),
              title: Text(plannerDefinitionSteps(context, task)[i]),
            ),
        ],
        ListTile(
          title: Text(
            context.plannerText(task.mandatory ? 'mandatory' : 'optional'),
          ),
        ),
      ],
    );
  }
}

class ChallengeInstancePage extends StatelessWidget {
  const ChallengeInstancePage({super.key, required this.instanceId});
  final String instanceId;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlannerController>();
    final instance = c.instances.where((i) => i.id == instanceId).firstOrNull;
    if (instance == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.plannerText('challenges'))),
        body: const SizedBox(),
      );
    }
    final tasks = <String, PlannerOccurrence>{};
    for (var day = 0; day < instance.snapshot.durationDays; day++) {
      for (final o in c.occurrences(plannerAddDays(instance.startDate, day))) {
        if (o.challengeId == instanceId) tasks[o.id] = o;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(plannerTemplateName(context, instance.snapshot)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.plannerText(instance.status.name),
            style: TextStyle(color: context.colors.primary),
          ),
          const SizedBox(height: 8),
          Text(_packageCategory(context, instance.snapshot)),
          const SizedBox(height: 12),
          Text(
            context.plannerText('completedTasks', {
              'done': plannerNumber(
                context,
                c.challengeCompletedCount(instance),
              ),
              'total': plannerNumber(context, c.challengeTotalCount(instance)),
            }),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: c.challengeProgress(instance)),
          const SizedBox(height: 12),
          Text(
            '${context.plannerText('deadline')}: ${plannerLocalDate(context, instance.deadline)} ${TimeOfDay.fromDateTime(instance.deadline).format(context)}',
          ),
          PlannerSection(context.plannerText('tasks')),
          for (final task in instance.snapshot.rootTasks)
            ChallengeTaskNode(
              instance: instance,
              task: task,
              occurrences: tasks.values.toList(),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(context.plannerText('commitment')),
            children: [
              Text(context.plannerText('requiredTasksRule')),
              if (instance.snapshot.rewardMode ==
                  ChallengeRewardMode.legacyPerTask)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.plannerText('legacyRewardRules')),
                ),
              PlannerOutcomeSummary(
                completionXp: instance.snapshot.completionXp,
                failurePenalty: instance.snapshot.failurePenalty,
                skipPenalty: instance.snapshot.skipPenalty,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tree is a view of the instance snapshot. Only leaf rows open actionable
/// occurrences, so expanding a group never changes completion records.
class ChallengeTaskNode extends StatelessWidget {
  const ChallengeTaskNode({
    super.key,
    required this.instance,
    required this.task,
    required this.occurrences,
    this.day,
    this.pendingOnly = false,
    this.depth = 0,
  });
  final ChallengeInstance instance;
  final ChallengeTaskDefinition task;
  final List<PlannerOccurrence> occurrences;
  final DateTime? day;
  final bool pendingOnly;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final visibleOccurrences = occurrences
        .where(
          (o) =>
              (day == null || plannerDateKey(o.day) == plannerDateKey(day!)) &&
              (!pendingOnly || o.record.status == CompletionStatus.pending),
        )
        .toList();
    if (!task.isGroup) {
      final leaves = packageOccurrencesInOrder(
        instance,
        visibleOccurrences,
      ).where((o) => o.itemId == '${instance.id}/${task.id}').toList();
      if (leaves.isEmpty) return const SizedBox.shrink();
      return Column(
        children: [
          for (final o in leaves)
            OccurrenceTile(
              key: ValueKey('package-occurrence-${o.id}'),
              occurrence: o,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlannerTaskPage(occurrence: o),
                ),
              ),
            ),
        ],
      );
    }
    final descendantIds = <String>{};
    void collectLeaves(ChallengeTaskDefinition node) {
      if (!node.isGroup) {
        descendantIds.add('${instance.id}/${node.id}');
      } else {
        for (final child in instance.snapshot.childrenOf(node.id)) {
          collectLeaves(child);
        }
      }
    }

    collectLeaves(task);
    if (!visibleOccurrences.any((o) => descendantIds.contains(o.itemId))) {
      return const SizedBox.shrink();
    }
    final c = context.watch<PlannerController>();
    final children = instance.snapshot.childrenOf(task.id);
    final total = c.groupTotalCount(instance, task.id, day: day);
    final done = c.groupCompletedCount(instance, task.id, day: day);
    final status = c.taskNodeStatus(instance, task.id, day: day);
    return ExpansionTile(
      key: PageStorageKey('instance-${instance.id}-group-${task.id}'),
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        status == CompletionStatus.completed
            ? Icons.task_alt
            : Icons.folder_outlined,
        color: status == CompletionStatus.completed
            ? context.tokens.success
            : null,
      ),
      title: Text(plannerDefinitionTitle(context, task)),
      subtitle: Text(
        context.plannerText('groupProgress', {
          'done': plannerNumber(context, done),
          'total': plannerNumber(context, total),
        }),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.plannerText('groupCompletionRule'),
            style: TextStyle(color: context.tokens.muted),
          ),
        ),
        for (final child in children)
          Padding(
            padding: EdgeInsetsDirectional.only(start: depth < 3 ? 12 : 0),
            child: ChallengeTaskNode(
              instance: instance,
              task: child,
              occurrences: occurrences,
              day: day,
              pendingOnly: pendingOnly,
              depth: depth + 1,
            ),
          ),
      ],
    );
  }
}
