import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';

/// Edits a reusable template. Active instances retain their own snapshots.
class PlannerPackageEditorPage extends StatefulWidget {
  const PlannerPackageEditorPage({super.key, this.template});
  final ChallengeTemplate? template;

  @override
  State<PlannerPackageEditorPage> createState() =>
      _PlannerPackageEditorPageState();
}

class _PlannerPackageEditorPageState extends State<PlannerPackageEditorPage> {
  final _identityForm = GlobalKey<FormState>();
  final _rewardForm = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.template?.name);
  late final _reward = TextEditingController(
    text: '${widget.template?.totalPossibleXp ?? 30}',
  );
  late final _failure = TextEditingController(
    text: '${widget.template?.failurePenalty ?? 0}',
  );
  late final _skip = TextEditingController(
    text: '${widget.template?.skipPenalty ?? 0}',
  );
  late final List<ChallengeTaskDefinition> _tasks = [
    ...?widget.template?.tasks,
  ];
  late String? _categoryId = widget.template?.categoryId;
  late String _categoryName = widget.template?.categoryName ?? '';
  final List<String> _groupPath = [];
  int _step = 0;
  bool _busy = false;

  String? get _parentId => _groupPath.lastOrNull;
  List<ChallengeTaskDefinition> _children(String? parentId) =>
      _tasks.where((task) => task.parentId == parentId).toList();
  ChallengeTaskDefinition _task(String id) =>
      _tasks.firstWhere((task) => task.id == id);

  @override
  void dispose() {
    _name.dispose();
    _reward.dispose();
    _failure.dispose();
    _skip.dispose();
    super.dispose();
  }

  void _back() {
    if (_busy) return;
    if (_groupPath.isNotEmpty) {
      setState(_groupPath.removeLast);
    } else if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.maybePop(context);
    }
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step == 0 && !_identityForm.currentState!.validate()) return;
    if (_step == 1) {
      if (_tasks.isEmpty) {
        _message('packageNeedsTask');
        return;
      }
      final empty = _tasks.where(
        (task) =>
            task.isGroup && !_children(task.id).any((child) => child.mandatory),
      );
      if (empty.isNotEmpty) {
        _message('emptyGroup');
        _openGroup(empty.first.id);
        return;
      }
    }
    setState(() {
      _groupPath.clear();
      _step++;
    });
  }

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.plannerText(key))),
  );

  void _openGroup(String id) {
    final path = <String>[id];
    var parent = _task(id).parentId;
    while (parent != null) {
      path.insert(0, parent);
      parent = _task(parent).parentId;
    }
    setState(() {
      _groupPath
        ..clear()
        ..addAll(path);
    });
  }

  Future<void> _editTask([ChallengeTaskDefinition? task]) async {
    final result = await Navigator.push<ChallengeTaskDefinition>(
      context,
      MaterialPageRoute(
        builder: (_) => _PackageTaskEditorPage(
          task: task,
          parentId: task?.parentId ?? _parentId,
          otherTasks: _tasks.where((t) => t.id != task?.id).toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == result.id);
      if (index < 0) {
        _tasks.add(result);
      } else {
        _tasks[index] = result;
      }
    });
  }

  Future<void> _editGroup([ChallengeTaskDefinition? group]) async {
    final name = await _nameDialog(
      context,
      title: group == null ? 'addTaskGroup' : 'editGroup',
      label: 'groupName',
      initial: group == null ? '' : plannerDefinitionTitle(context, group),
    );
    if (name == null || !mounted) return;
    final map =
        group?.toMap() ??
        <String, dynamic>{
          'id': const Uuid().v4(),
          'dayOffsets': [0],
          'parentId': _parentId,
          'rewardXp': 0,
          'skipPenalty': 0,
        };
    map['title'] = name;
    map['type'] = ChallengeTaskType.group.name;
    final result = ChallengeTaskDefinition.fromMap(map);
    setState(() {
      if (group == null) {
        _tasks.add(result);
      } else {
        _tasks[_tasks.indexWhere((task) => task.id == group.id)] = result;
      }
    });
    if (group == null) _openGroup(result.id);
  }

  Future<void> _remove(ChallengeTaskDefinition task) async {
    final confirmed = await plannerConfirm(
      context,
      title: context.plannerText('delete'),
      message: context.plannerText(
        task.isGroup ? 'groupDeleteInfo' : 'deleteTaskInfo',
      ),
      action: context.plannerText('delete'),
    );
    if (!confirmed || !mounted) return;
    final removed = <String>{task.id};
    void descendants(String id) {
      for (final child in _children(id)) {
        removed.add(child.id);
        descendants(child.id);
      }
    }

    descendants(task.id);
    setState(() {
      _tasks.removeWhere((task) => removed.contains(task.id));
      // Dependencies are legacy metadata; deleting a branch cannot leave them
      // pointing at missing tasks, including from another branch.
      for (var i = 0; i < _tasks.length; i++) {
        final map = _tasks[i].toMap();
        map['dependencies'] = _tasks[i].dependencies
            .where((id) => !removed.contains(id))
            .toList();
        _tasks[i] = ChallengeTaskDefinition.fromMap(map);
      }
    });
  }

  void _move(ChallengeTaskDefinition task, int offset) {
    final siblings = _children(task.parentId);
    final destination = siblings.indexWhere((t) => t.id == task.id) + offset;
    if (destination < 0 || destination >= siblings.length) return;
    final first = _tasks.indexWhere((t) => t.id == task.id);
    final second = _tasks.indexWhere((t) => t.id == siblings[destination].id);
    setState(() {
      final other = _tasks[second];
      _tasks[second] = task;
      _tasks[first] = other;
    });
  }

  Future<void> _editCategory([ChallengeCategory? category]) async {
    final name = await _nameDialog(
      context,
      title: category == null ? 'newCategory' : 'renameCategory',
      label: 'categoryName',
      initial: category?.name ?? '',
    );
    if (name == null || !mounted) return;
    ChallengeCategory? saved;
    final success = await plannerAction(context, () async {
      saved = await context.read<PlannerController>().saveCategory(
        id: category?.id,
        name: name,
      );
    });
    if (!success || !mounted) return;
    if (category == null || _categoryId == category.id) {
      setState(() {
        _categoryId = saved!.id;
        _categoryName = saved!.name;
      });
    }
  }

  Future<void> _deleteCategory(ChallengeCategory category) async {
    if (!await plannerConfirm(
      context,
      title: context.plannerText('deleteCategory'),
      message: context.plannerText('categoryDeleteInfo'),
      action: context.plannerText('delete'),
    )) {
      return;
    }
    if (!mounted) return;
    final success = await plannerAction(
      context,
      () => context.read<PlannerController>().deleteCategory(category.id),
    );
    if (success && mounted && _categoryId == category.id) {
      setState(() => _categoryId = null);
    }
  }

  Future<void> _manageCategories() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .55,
      minChildSize: .3,
      maxChildSize: .9,
      builder: (_, scrollController) => Consumer<PlannerController>(
        builder: (_, controller, _) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              context.plannerText('manageCategories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final category in controller.categories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline),
                title: Text(category.name),
                onTap: () => _editCategory(category),
                trailing: IconButton(
                  tooltip: context.plannerText('deleteCategory'),
                  onPressed: () => _deleteCategory(category),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            TextButton.icon(
              onPressed: () => _editCategory(),
              icon: const Icon(Icons.add),
              label: Text(context.plannerText('newCategory')),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    if (_busy || !_rewardForm.currentState!.validate()) return;
    setState(() => _busy = true);
    final controller = context.read<PlannerController>();
    final category = controller.categories
        .where((category) => category.id == _categoryId)
        .firstOrNull;
    var durationDays = widget.template?.durationDays ?? 1;
    for (final task in _tasks.where((task) => !task.isGroup)) {
      for (final offset in task.dayOffsets) {
        final endDay =
            offset +
            (task.type == ChallengeTaskType.scheduled
                ? (task.startMinute! + task.durationMinutes) ~/ 1440
                : 0) +
            1;
        if (endDay > durationDays) durationDays = endDay;
      }
    }
    final template = ChallengeTemplate(
      id: widget.template?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      categoryId: category?.id,
      categoryName: category?.name ?? _categoryName,
      description: widget.template?.description ?? '',
      difficulty: widget.template?.difficulty,
      durationDays: durationDays,
      tasks: _tasks,
      completionXp: int.parse(plannerLatinDigits(_reward.text)),
      failurePenalty: int.parse(plannerLatinDigits(_failure.text)),
      skipPenalty: int.parse(plannerLatinDigits(_skip.text)),
      rewardMode: ChallengeRewardMode.packageOnly,
      prerequisiteTemplateIds:
          widget.template?.prerequisiteTemplateIds ?? const [],
      createdAt: widget.template?.createdAt,
    );
    final success = await plannerAction(
      context,
      () => controller.saveTemplate(template),
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
    final headings = ['builderIdentity', 'builderTasks', 'builderRewards'];
    return PopScope(
      canPop: _step == 0 && _groupPath.isEmpty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(
            context.plannerText(
              widget.template == null ? 'createPackage' : 'editPackage',
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.plannerText(headings[_step]),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.plannerText('builderStep', {
                          'current': plannerNumber(context, _step + 1),
                          'total': plannerNumber(context, 3),
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: (_step + 1) / 3),
                ],
              ),
            ),
            Expanded(
              child: switch (_step) {
                0 => _identity(),
                1 => _taskTree(),
                _ => _rewards(),
              },
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: FilledButton.icon(
            key: const ValueKey('package-primary-action'),
            onPressed: _busy ? null : (_step < 2 ? _next : _save),
            icon: Icon(_step < 2 ? Icons.arrow_forward : Icons.check),
            label: Text(
              context.plannerText(_step < 2 ? 'builderNext' : 'savePackage'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity() => Form(
    key: _identityForm,
    child: ListView(
      key: const PageStorageKey('package-identity'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(context.plannerText('builderIdentityHint')),
        const SizedBox(height: 24),
        TextFormField(
          key: const ValueKey('package-name'),
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.plannerText('packageName'),
            prefixIcon: const Icon(Icons.emoji_events_outlined),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? context.plannerText('invalidPackageName')
              : null,
        ),
        PlannerSection(context.plannerText('category')),
        Consumer<PlannerController>(
          builder: (_, controller, _) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.plannerText('noCategory')),
                selected: _categoryId == null && _categoryName.isEmpty,
                onSelected: (_) => setState(() {
                  _categoryId = null;
                  _categoryName = '';
                }),
              ),
              if (_categoryId == null && _categoryName.isNotEmpty)
                ChoiceChip(
                  label: Text(_categoryName),
                  selected: true,
                  onSelected: (_) {},
                ),
              for (final category in controller.categories)
                ChoiceChip(
                  label: Text(category.name),
                  selected: _categoryId == category.id,
                  onSelected: (_) => setState(() {
                    _categoryId = category.id;
                    _categoryName = category.name;
                  }),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(context.plannerText('newCategory')),
                onPressed: () => _editCategory(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _manageCategories,
            icon: const Icon(Icons.tune),
            label: Text(context.plannerText('manageCategories')),
          ),
        ),
      ],
    ),
  );

  Widget _taskTree() {
    final siblings = _children(_parentId);
    return ListView(
      key: ValueKey('package-tasks-${_parentId ?? 'root'}'),
      padding: const EdgeInsets.all(20),
      children: [
        if (_groupPath.isEmpty)
          Text(context.plannerText('builderTasksHint'))
        else ...[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(_groupPath.clear),
                child: Text(context.plannerText('parentPackage')),
              ),
              for (var i = 0; i < _groupPath.length; i++) ...[
                _forwardChevron(context),
                TextButton(
                  onPressed: i == _groupPath.length - 1
                      ? null
                      : () => setState(
                          () =>
                              _groupPath.removeRange(i + 1, _groupPath.length),
                        ),
                  child: Text(
                    plannerDefinitionTitle(context, _task(_groupPath[i])),
                  ),
                ),
              ],
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(plannerDefinitionTitle(context, _task(_parentId!))),
            subtitle: Text(context.plannerText('taskGroup')),
            trailing: IconButton(
              tooltip: context.plannerText('editGroup'),
              onPressed: () => _editGroup(_task(_parentId!)),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _back,
              icon: const BackButtonIcon(),
              label: Text(context.plannerText('returnToParent')),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (siblings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  _parentId == null
                      ? Icons.playlist_add_rounded
                      : Icons.create_new_folder_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  context.plannerText(
                    _parentId == null ? 'noTasksYet' : 'emptyGroup',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        for (var index = 0; index < siblings.length; index++) ...[
          Container(
            decoration: _parentId == null
                ? null
                : BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        width: 2,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .35),
                      ),
                    ),
                  ),
            padding: EdgeInsetsDirectional.only(
              start: _parentId == null ? 0 : 12,
            ),
            child: _taskCard(siblings[index], index, siblings.length),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        _BuilderAction(
          icon: Icons.add_task,
          label: context.plannerText('addTask'),
          onPressed: _editTask,
        ),
        const SizedBox(height: 8),
        _BuilderAction(
          icon: Icons.create_new_folder_outlined,
          label: context.plannerText('addTaskGroup'),
          onPressed: _editGroup,
        ),
      ],
    );
  }

  Widget _taskCard(ChallengeTaskDefinition task, int index, int count) =>
      Material(
        key: ValueKey('builder-task-${task.id}'),
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
          leading: Icon(_taskIcon(task)),
          title: Text(plannerDefinitionTitle(context, task)),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  _taskSummary(context, task, _children(task.id).length),
                ),
              ),
              if (task.isGroup) _forwardChevron(context),
            ],
          ),
          onTap: () => task.isGroup ? _openGroup(task.id) : _editTask(task),
          trailing: PopupMenuButton<String>(
            tooltip: context.plannerText('taskOrder'),
            onSelected: (action) {
              switch (action) {
                case 'up':
                  _move(task, -1);
                case 'down':
                  _move(task, 1);
                case 'edit':
                  task.isGroup ? _editGroup(task) : _editTask(task);
                case 'delete':
                  _remove(task);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  context.plannerText(task.isGroup ? 'editGroup' : 'editTask'),
                ),
              ),
              if (index > 0)
                PopupMenuItem(
                  value: 'up',
                  child: Text(context.plannerText('moveUp')),
                ),
              if (index < count - 1)
                PopupMenuItem(
                  value: 'down',
                  child: Text(context.plannerText('moveDown')),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(context.plannerText('delete')),
              ),
            ],
          ),
        ),
      );

  Widget _rewards() => Form(
    key: _rewardForm,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _xpField(
          context,
          _reward,
          'completionShort',
          Icons.check_circle_outline,
        ),
        const SizedBox(height: 16),
        _xpField(context, _failure, 'failureShort', Icons.cancel_outlined),
        const SizedBox(height: 16),
        _xpField(context, _skip, 'taskSkipShort', Icons.skip_next_outlined),
        PlannerSection(context.plannerText('packagePreview')),
        PlannerPanel(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _name.text.trim(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_categoryName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_categoryName),
              ],
              const SizedBox(height: 12),
              Text(
                context.plannerText('packageTaskCount', {
                  'count': plannerNumber(
                    context,
                    _tasks.where((task) => !task.isGroup).length,
                  ),
                }),
              ),
              const SizedBox(height: 12),
              ..._previewTree(null, 0),
              const Divider(height: 28),
              ListenableBuilder(
                listenable: Listenable.merge([_reward, _failure, _skip]),
                builder: (_, _) => PlannerOutcomeSummary(
                  completionXp:
                      int.tryParse(plannerLatinDigits(_reward.text)) ?? 0,
                  failurePenalty:
                      int.tryParse(plannerLatinDigits(_failure.text)) ?? 0,
                  skipPenalty:
                      int.tryParse(plannerLatinDigits(_skip.text)) ?? 0,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _previewTree(String? parentId, int depth) => [
    for (final task in _children(parentId)) ...[
      Padding(
        padding: EdgeInsetsDirectional.only(
          start: (depth.clamp(0, 3) * 12).toDouble(),
          top: 5,
          bottom: 5,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_taskIcon(task), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(plannerDefinitionTitle(context, task))),
          ],
        ),
      ),
      if (task.isGroup) ..._previewTree(task.id, depth + 1),
    ],
  ];
}

class _PackageTaskEditorPage extends StatefulWidget {
  const _PackageTaskEditorPage({
    this.task,
    this.parentId,
    required this.otherTasks,
  });
  final ChallengeTaskDefinition? task;
  final String? parentId;
  final List<ChallengeTaskDefinition> otherTasks;

  @override
  State<_PackageTaskEditorPage> createState() => _PackageTaskEditorPageState();
}

class _PackageTaskEditorPageState extends State<_PackageTaskEditorPage> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.task?.id ?? const Uuid().v4();
  late final _title = TextEditingController(
    text: widget.task == null
        ? ''
        : plannerDefinitionTitle(context, widget.task!),
  );
  late ChallengeTaskType _type =
      widget.task?.type ?? ChallengeTaskType.flexible;
  late int? _start = widget.task?.startMinute;
  late int? _end = _start == null
      ? null
      : _start! + widget.task!.durationMinutes;
  late PlannerReminder _reminder =
      widget.task?.reminder ?? const PlannerReminder();
  bool _busy = false;
  String? _timeError;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final minute =
        (start ? _start : _end) ?? (start ? 9 * 60 : (_start ?? 9 * 60) + 30);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (start) {
        _start = time.hour * 60 + time.minute;
      } else {
        _end = time.hour * 60 + time.minute;
      }
      _timeError = null;
    });
  }

  Future<void> _editReminder() async {
    final result = await editPlannerReminder(
      context,
      PlannerOccurrence(
        id: 'preview',
        item: PlannerItem(
          id: _id,
          title: _title.text,
          date: DateTime.now(),
          startMinute: _type == ChallengeTaskType.scheduled ? _start : null,
          reminder: _reminder,
        ),
        day: DateTime.now(),
      ),
    );
    if (result != null && mounted) setState(() => _reminder = result.reminder);
  }

  void _selectType(ChallengeTaskType type) => setState(() {
    if (type == ChallengeTaskType.flexible &&
        _reminder.enabled &&
        _reminder.minute == null &&
        _start != null) {
      // A scheduled reminder can inherit its time from the start. A flexible
      // task needs an explicit wall-clock time after that start is removed.
      _reminder = PlannerReminder.fromMap(
        _reminder.toMap()
          ..['minute'] = (_start! - _reminder.offsetMinutes) % 1440,
      );
    }
    _type = type;
    _timeError = null;
  });

  int? get _intervalDuration {
    if (_start == null || _end == null) return null;
    return _end! > _start! ? _end! - _start! : _end! + 1440 - _start!;
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_type == ChallengeTaskType.scheduled) {
      final original = widget.task;
      final unchangedLegacyInterval =
          original != null &&
          original.type == ChallengeTaskType.scheduled &&
          _start == original.startMinute &&
          _end == original.startMinute! + original.durationMinutes;
      if (_start == null ||
          _end == null ||
          _intervalDuration! <= 0 ||
          _intervalDuration! > 1440 ||
          (_intervalDuration == 1440 && !unchangedLegacyInterval)) {
        setState(() => _timeError = context.plannerText('invalidTaskInterval'));
        return;
      }
      final days = widget.task?.dayOffsets ?? const [0];
      final conflict = widget.otherTasks.any(
        (task) =>
            task.type == ChallengeTaskType.scheduled &&
            task.startMinute != null &&
            days.any(
              (day) => task.dayOffsets.any(
                (otherDay) =>
                    day * 1440 + _start! <
                        otherDay * 1440 +
                            task.startMinute! +
                            task.durationMinutes &&
                    day * 1440 + _start! + _intervalDuration! >
                        otherDay * 1440 + task.startMinute!,
              ),
            ),
      );
      setState(() => _busy = true);
      if (conflict &&
          !await plannerConfirm(
            context,
            title: context.plannerText('scheduledTask'),
            message: context.plannerText('taskTimeConflict'),
            action: context.plannerText('save'),
          )) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
    }
    final map =
        widget.task?.toMap() ??
        <String, dynamic>{
          'id': _id,
          'dayOffsets': [0],
          'rewardXp': 0,
          'skipPenalty': 0,
          'mandatory': true,
        };
    // Only controls exposed in this focused editor change. Existing quantity,
    // steps, dates, prerequisites and historical IDs stay intact.
    map.addAll({
      'title':
          widget.task != null &&
              _title.text.trim() ==
                  plannerDefinitionTitle(context, widget.task!)
          ? widget.task!.title
          : _title.text.trim(),
      'type': _type.name,
      'parentId': widget.parentId,
      'startMinute': _type == ChallengeTaskType.scheduled ? _start : null,
      'durationMinutes': _type == ChallengeTaskType.scheduled
          ? _intervalDuration!
          : (widget.task?.durationMinutes ?? 30),
      'reminder': _reminder.toMap(),
    });
    Navigator.pop(context, ChallengeTaskDefinition.fromMap(map));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        context.plannerText(widget.task == null ? 'addTask' : 'editTask'),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            key: const ValueKey('package-task-name'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.plannerText('taskTitle'),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? context.plannerText('invalidTaskTitle')
                : null,
          ),
          PlannerSection(context.plannerText('taskType')),
          _TaskTypeTile(
            type: ChallengeTaskType.flexible,
            selected: _type == ChallengeTaskType.flexible,
            onPressed: () => _selectType(ChallengeTaskType.flexible),
          ),
          const SizedBox(height: 10),
          _TaskTypeTile(
            type: ChallengeTaskType.scheduled,
            selected: _type == ChallengeTaskType.scheduled,
            onPressed: () => _selectType(ChallengeTaskType.scheduled),
          ),
          if (_type == ChallengeTaskType.scheduled) ...[
            const SizedBox(height: 20),
            _BuilderAction(
              key: const ValueKey('task-start-time'),
              icon: Icons.schedule,
              label: _start == null
                  ? context.plannerText('chooseStartTime')
                  : context.plannerText('startTime', {
                      'time': _time(context, _start!),
                    }),
              onPressed: () => _pickTime(true),
            ),
            const SizedBox(height: 8),
            _BuilderAction(
              key: const ValueKey('task-end-time'),
              icon: Icons.timelapse,
              label: _end == null
                  ? context.plannerText('chooseEndTime')
                  : context.plannerText('endTime', {
                      'time':
                          '${_time(context, _end!)}${_end! >= 1440 || (_start != null && _end! < _start!) ? ' ${context.plannerText('nextDaySuffix')}' : ''}',
                    }),
              onPressed: () => _pickTime(false),
            ),
            if (_timeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _timeError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _reminder.enabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none,
              color: _reminder.enabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(context.plannerText('optionalReminder')),
            subtitle: Text(
              _reminder.enabled && _reminder.minute != null
                  ? _time(context, _reminder.minute!)
                  : context.plannerText(
                      _reminder.enabled ? 'enabled' : 'disabled',
                    ),
            ),
            trailing: _forwardChevron(context),
            onTap: _editReminder,
          ),
          if (_hasPreservedConditions) _preservedConditions(),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: FilledButton.icon(
        key: const ValueKey('save-package-task'),
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.check),
        label: Text(context.plannerText('save')),
      ),
    ),
  );

  bool get _hasPreservedConditions {
    final task = widget.task;
    return task != null &&
        (task.description.isNotEmpty ||
            task.target != null ||
            task.dependencies.isNotEmpty ||
            !task.mandatory ||
            task.dayOffsets.length != 1 ||
            task.dayOffsets.single != 0);
  }

  Widget _preservedConditions() {
    final task = widget.task!;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.plannerText('preservedConditions')),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.plannerText('preservedConditionsInfo')),
        if (task.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(task.description),
        ],
        if (task.target != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.plannerText('target')),
            subtitle: Text(
              '${plannerNumber(context, task.target!)} ${plannerUnit(context, task.unit)}',
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.plannerText('taskDays')),
          subtitle: Text(
            task.dayOffsets
                .map((day) => plannerNumber(context, day + 1))
                .join(', '),
          ),
        ),
        if (task.dependencies.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.plannerText('prerequisites')),
            subtitle: Text(
              widget.otherTasks
                  .where((other) => task.dependencies.contains(other.id))
                  .map((other) => plannerDefinitionTitle(context, other))
                  .join(', '),
            ),
          ),
        if (!task.mandatory) Text(context.plannerText('optional')),
      ],
    );
  }
}

class _TaskTypeTile extends StatelessWidget {
  const _TaskTypeTile({
    required this.type,
    required this.selected,
    required this.onPressed,
  });
  final ChallengeTaskType type;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheduled = type == ChallengeTaskType.scheduled;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(scheduled ? Icons.schedule : Icons.wb_sunny_outlined),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.plannerText(
                          scheduled ? 'scheduledTask' : 'flexibleTask',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.plannerText(
                          scheduled ? 'scheduledTaskHint' : 'flexibleTaskHint',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BuilderAction extends StatelessWidget {
  const _BuilderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

Widget _xpField(
  BuildContext context,
  TextEditingController controller,
  String label,
  IconData icon,
) => PlannerPanel(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  child: Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(child: Text(context.plannerText(label))),
      const SizedBox(width: 12),
      SizedBox(
        width: 112,
        child: Semantics(
          label: context.plannerText(label),
          child: TextFormField(
            key: ValueKey('package-xp-$label'),
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(suffixText: context.plannerText('xp')),
            validator: (text) {
              final value = int.tryParse(plannerLatinDigits(text ?? ''));
              return value == null || value < 0 || value > 1000000
                  ? context.plannerText('requiredValue')
                  : null;
            },
          ),
        ),
      ),
    ],
  ),
);

Future<String?> _nameDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _BuilderNameDialog(title: title, label: label, initial: initial),
);

class _BuilderNameDialog extends StatefulWidget {
  const _BuilderNameDialog({
    required this.title,
    required this.label,
    required this.initial,
  });
  final String title;
  final String label;
  final String initial;

  @override
  State<_BuilderNameDialog> createState() => _BuilderNameDialogState();
}

class _BuilderNameDialogState extends State<_BuilderNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.plannerText(widget.title)),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.plannerText(widget.label),
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? context.plannerText('requiredValue')
            : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.plannerText('goBack')),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(context.plannerText('save')),
      ),
    ],
  );
}

IconData _taskIcon(ChallengeTaskDefinition task) => task.isGroup
    ? Icons.account_tree_outlined
    : task.type == ChallengeTaskType.scheduled
    ? Icons.schedule
    : Icons.radio_button_unchecked;

String _taskSummary(
  BuildContext context,
  ChallengeTaskDefinition task,
  int children,
) => task.isGroup
    ? context.plannerText('groupChildren', {
        'count': plannerNumber(context, children),
      })
    : task.type == ChallengeTaskType.scheduled && task.startMinute != null
    ? '${_time(context, task.startMinute!)} – ${_time(context, task.startMinute! + task.durationMinutes)}${task.startMinute! + task.durationMinutes >= 1440 ? ' ${context.plannerText('nextDaySuffix')}' : ''}'
    : context.plannerText('flexibleTask');

String _time(BuildContext context, int minute) =>
    TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60).format(context);

Widget _forwardChevron(BuildContext context) => Icon(
  Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left
      : Icons.chevron_right,
  size: 18,
);
