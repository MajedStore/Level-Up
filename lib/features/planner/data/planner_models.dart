// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:math' as math;

enum PlannerRecurrence { once, daily, weekdays, weekly }

enum CompletionStatus { pending, completed, skipped }

enum ChallengeDifficulty { easy, medium, hard }

enum ChallengeStatus { active, completed, failed }

/// Explicit persisted behavior; old records without a type are migrated by time.
enum ChallengeTaskType { flexible, scheduled, group }

/// Legacy instance snapshots retain their captured task-level accounting.
enum ChallengeRewardMode { legacyPerTask, packageOnly }

class ChallengeCategory {
  const ChallengeCategory({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
  factory ChallengeCategory.fromMap(Map<String, dynamic> m) =>
      ChallengeCategory(id: m['id'] as String, name: m['name'] as String);
}

/// Routine definitions live in PlannerState.items. Challenge occurrences are
/// derived from an immutable package snapshot and carry its instance identity.
enum PlannerTaskKind { routine, challenge }

DateTime plannerDay(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime plannerAddDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
String plannerDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
int plannerDayDistance(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
Map<String, dynamic> plannerMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);

class PlannerReminder {
  const PlannerReminder({
    this.enabled = false,
    this.minute,
    this.offsetMinutes = 0,
    this.sound = 'default',
    this.vibrate = true,
  });
  final bool enabled;
  final int? minute;
  final int offsetMinutes;
  final String sound;
  final bool vibrate;
  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'minute': minute,
    'offsetMinutes': offsetMinutes,
    'sound': sound,
    'vibrate': vibrate,
  };
  factory PlannerReminder.fromMap(Map<String, dynamic> map) => PlannerReminder(
    enabled: map['enabled'] as bool? ?? false,
    minute: map['minute'] as int?,
    offsetMinutes: map['offsetMinutes'] as int? ?? 0,
    sound: map['sound'] as String? ?? 'default',
    vibrate: map['vibrate'] as bool? ?? true,
  );
}

class PlannerItem {
  const PlannerItem({
    required this.id,
    required this.title,
    required this.date,
    this.description = '',
    this.category = 'Personal',
    this.startMinute,
    this.endMinute,
    this.overnight = false,
    this.recurrence = PlannerRecurrence.once,
    this.weekdays = const [],
    this.everyWeeks = 1,
    this.reminder = const PlannerReminder(),
    this.steps = const [],
    this.target,
    this.unit = '',
    this.dependencies = const [],
    this.xp = 10,
  });
  final String id;
  final String title;
  final DateTime date;
  final String description;
  final String category;
  final int? startMinute;
  final int? endMinute;
  final bool overnight;
  final PlannerRecurrence recurrence;
  final List<int> weekdays;
  final int everyWeeks;
  final PlannerReminder reminder;
  final List<String> steps;
  final double? target;
  final String unit;
  final List<String> dependencies;
  final int xp;
  bool get isScheduled => startMinute != null && endMinute != null;
  bool occursOn(DateTime day) {
    final gap = plannerDayDistance(date, day);
    if (gap < 0) return false;
    return switch (recurrence) {
      PlannerRecurrence.once => gap == 0,
      PlannerRecurrence.daily => true,
      PlannerRecurrence.weekdays => weekdays.contains(day.weekday),
      PlannerRecurrence.weekly =>
        weekdays.contains(day.weekday) &&
            (plannerDayDistance(
                          plannerAddDays(date, 1 - date.weekday),
                          plannerAddDays(day, 1 - day.weekday),
                        ) ~/
                        7) %
                    everyWeeks ==
                0,
    };
  }

  void validate() {
    if (id.isEmpty || id.contains('@') || title.trim().isEmpty) {
      throw ArgumentError('A title and a valid identifier are required.');
    }
    if ((startMinute == null) != (endMinute == null)) {
      throw ArgumentError('Set both start and end times.');
    }
    if (isScheduled &&
        (startMinute! < 0 ||
            startMinute! >= 1440 ||
            endMinute! < 0 ||
            endMinute! >= 1440)) {
      throw ArgumentError('Times must be within a day.');
    }
    if (isScheduled &&
        ((!overnight && endMinute! <= startMinute!) ||
            (overnight && endMinute! > startMinute!))) {
      throw ArgumentError(
        'End time must follow start time; enable overnight for a next-day finish.',
      );
    }
    if ((recurrence == PlannerRecurrence.weekdays ||
            recurrence == PlannerRecurrence.weekly) &&
        (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7))) {
      throw ArgumentError('Select at least one valid weekday.');
    }
    if (everyWeeks < 1 || everyWeeks > 52) {
      throw ArgumentError('Weekly interval must be between 1 and 52.');
    }
    if (target != null &&
        (!target!.isFinite || target! <= 0 || unit.trim().isEmpty)) {
      throw ArgumentError('Enter a positive target and a unit.');
    }
    if (xp < 0 || steps.any((s) => s.trim().isEmpty)) {
      throw ArgumentError('Task rules are invalid.');
    }
    if (reminder.enabled && !isScheduled && reminder.minute == null) {
      throw ArgumentError('Choose a reminder time.');
    }
    if (reminder.minute != null &&
        (reminder.minute! < 0 || reminder.minute! >= 1440)) {
      throw ArgumentError('Reminder time is invalid.');
    }
    if (reminder.offsetMinutes < 0 || reminder.offsetMinutes > 10080) {
      throw ArgumentError('Reminder lead time is invalid.');
    }
    if (dependencies.contains(id)) {
      throw ArgumentError('A task cannot depend on itself.');
    }
  }

  PlannerItem copyWith({
    String? id,
    String? title,
    DateTime? date,
    String? description,
    String? category,
    int? startMinute,
    int? endMinute,
    bool? overnight,
    PlannerRecurrence? recurrence,
    List<int>? weekdays,
    int? everyWeeks,
    PlannerReminder? reminder,
    List<String>? steps,
    double? target,
    String? unit,
    List<String>? dependencies,
    int? xp,
    bool clearTime = false,
    bool clearTarget = false,
  }) => PlannerItem(
    id: id ?? this.id,
    title: title ?? this.title,
    date: date ?? this.date,
    description: description ?? this.description,
    category: category ?? this.category,
    startMinute: clearTime ? null : startMinute ?? this.startMinute,
    endMinute: clearTime ? null : endMinute ?? this.endMinute,
    overnight: overnight ?? this.overnight,
    recurrence: recurrence ?? this.recurrence,
    weekdays: weekdays ?? this.weekdays,
    everyWeeks: everyWeeks ?? this.everyWeeks,
    reminder: reminder ?? this.reminder,
    steps: steps ?? this.steps,
    target: clearTarget ? null : target ?? this.target,
    unit: unit ?? this.unit,
    dependencies: dependencies ?? this.dependencies,
    xp: xp ?? this.xp,
  );
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'date': plannerDateKey(date),
    'description': description,
    'category': category,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'overnight': overnight,
    'recurrence': recurrence.name,
    'weekdays': List<int>.of(weekdays),
    'everyWeeks': everyWeeks,
    'reminder': reminder.toMap(),
    'steps': List<String>.of(steps),
    'target': target,
    'unit': unit,
    'dependencies': List<String>.of(dependencies),
    'xp': xp,
  };
  factory PlannerItem.fromMap(Map<String, dynamic> m) => PlannerItem(
    id: m['id'] as String,
    title: m['title'] as String,
    date: DateTime.parse(m['date'] as String),
    description: m['description'] as String? ?? '',
    category: m['category'] as String? ?? 'Personal',
    startMinute: m['startMinute'] as int?,
    endMinute: m['endMinute'] as int?,
    overnight: m['overnight'] as bool? ?? false,
    recurrence: PlannerRecurrence.values.byName(
      m['recurrence'] as String? ?? 'once',
    ),
    weekdays: List<int>.from(m['weekdays'] as List? ?? []),
    everyWeeks: m['everyWeeks'] as int? ?? 1,
    reminder: PlannerReminder.fromMap(plannerMap(m['reminder'] ?? {})),
    steps: List<String>.from(m['steps'] as List? ?? []),
    target: (m['target'] as num?)?.toDouble(),
    unit: m['unit'] as String? ?? '',
    dependencies: List<String>.from(m['dependencies'] as List? ?? []),
    xp: m['xp'] as int? ?? 10,
  );
}

class CompletionRecord {
  const CompletionRecord({
    this.status = CompletionStatus.pending,
    this.completedSteps = const [],
    this.amount = 0,
    this.at,
  });
  final CompletionStatus status;
  final List<int> completedSteps;
  final double amount;
  final DateTime? at;
  Map<String, dynamic> toMap() => {
    'status': status.name,
    'completedSteps': List<int>.of(completedSteps),
    'amount': amount,
    'at': at?.toIso8601String(),
  };
  factory CompletionRecord.fromMap(Map<String, dynamic> m) => CompletionRecord(
    status: CompletionStatus.values.byName(m['status'] as String? ?? 'pending'),
    completedSteps: List<int>.from(m['completedSteps'] as List? ?? []),
    amount: (m['amount'] as num? ?? 0).toDouble(),
    at: m['at'] == null ? null : DateTime.parse(m['at'] as String),
  );
}

class PlannerOccurrence {
  const PlannerOccurrence({
    required this.id,
    required this.item,
    required this.day,
    this.record = const CompletionRecord(),
    this.challengeId,
    this.validUntil,
  });
  final String id;
  final PlannerItem item;
  final DateTime day;
  final CompletionRecord record;
  final String? challengeId;

  /// Derived from the owning challenge instance; never a persisted task rule.
  /// Reminders and snoozes must fire strictly before this instant.
  final DateTime? validUntil;
  String get itemId => item.id;
  String get title => item.title;
  bool get isChallenge => challengeId != null;
  PlannerTaskKind get kind =>
      isChallenge ? PlannerTaskKind.challenge : PlannerTaskKind.routine;
  bool get isScheduled => item.isScheduled;
  DateTime? get start => item.startMinute == null
      ? null
      : DateTime(
          day.year,
          day.month,
          day.day,
          item.startMinute! ~/ 60,
          item.startMinute! % 60,
        );
  DateTime? get end => item.endMinute == null
      ? null
      : DateTime(
          day.year,
          day.month,
          day.day + (item.overnight ? 1 : 0),
          item.endMinute! ~/ 60,
          item.endMinute! % 60,
        );
  bool overlaps(PlannerOccurrence other) =>
      start != null &&
      other.start != null &&
      start!.isBefore(other.end!) &&
      other.start!.isBefore(end!);
}

class ChallengeTaskDefinition {
  const ChallengeTaskDefinition({
    required this.id,
    required this.title,
    this.dayOffsets = const [0],
    ChallengeTaskType? type,
    this.parentId,
    this.description = '',
    this.startMinute,
    this.durationMinutes = 30,
    this.steps = const [],
    this.dependencies = const [],
    this.target,
    this.unit = '',
    this.rewardXp = 10,
    this.skipPenalty = 5,
    this.mandatory = true,
    this.reminder = const PlannerReminder(),
  }) : _type = type;
  final String id;
  final String title;
  final String description;
  final List<int> dayOffsets;
  final ChallengeTaskType? _type;
  ChallengeTaskType get type =>
      _type ??
      (startMinute == null
          ? ChallengeTaskType.flexible
          : ChallengeTaskType.scheduled);
  bool get isGroup => type == ChallengeTaskType.group;
  final String? parentId;
  final int? startMinute;
  final int durationMinutes;
  // Existing sequential steps and numeric targets remain captured legacy rules.
  final List<String> steps;
  final List<String> dependencies;
  final double? target;
  final String unit;
  final int rewardXp;
  final int skipPenalty;
  final bool mandatory;
  final PlannerReminder reminder;
  ChallengeTaskDefinition copyWith({
    String? id,
    String? title,
    List<int>? dayOffsets,
    ChallengeTaskType? type,
    String? parentId,
    String? description,
    int? startMinute,
    int? durationMinutes,
    List<String>? steps,
    List<String>? dependencies,
    double? target,
    String? unit,
    int? rewardXp,
    int? skipPenalty,
    bool? mandatory,
    PlannerReminder? reminder,
    bool clearParent = false,
    bool clearTime = false,
    bool clearTarget = false,
  }) => ChallengeTaskDefinition(
    id: id ?? this.id,
    title: title ?? this.title,
    dayOffsets: dayOffsets ?? this.dayOffsets,
    type: type ?? this.type,
    parentId: clearParent ? null : parentId ?? this.parentId,
    description: description ?? this.description,
    startMinute: clearTime ? null : startMinute ?? this.startMinute,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    steps: steps ?? this.steps,
    dependencies: dependencies ?? this.dependencies,
    target: clearTarget ? null : target ?? this.target,
    unit: unit ?? this.unit,
    rewardXp: rewardXp ?? this.rewardXp,
    skipPenalty: skipPenalty ?? this.skipPenalty,
    mandatory: mandatory ?? this.mandatory,
    reminder: reminder ?? this.reminder,
  );
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'dayOffsets': List<int>.of(dayOffsets),
    'type': type.name,
    'parentId': parentId,
    'startMinute': startMinute,
    'durationMinutes': durationMinutes,
    'steps': List<String>.of(steps),
    'dependencies': List<String>.of(dependencies),
    'target': target,
    'unit': unit,
    'rewardXp': rewardXp,
    'skipPenalty': skipPenalty,
    'mandatory': mandatory,
    'reminder': reminder.toMap(),
  };
  factory ChallengeTaskDefinition.fromMap(Map<String, dynamic> m) =>
      ChallengeTaskDefinition(
        id: m['id'] as String,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        dayOffsets: List<int>.from(m['dayOffsets'] as List? ?? [0]),
        type: m['type'] == null
            ? null
            : ChallengeTaskType.values.byName(m['type'] as String),
        parentId: m['parentId'] as String?,
        startMinute: m['startMinute'] as int?,
        durationMinutes: m['durationMinutes'] as int? ?? 30,
        steps: List<String>.from(m['steps'] as List? ?? []),
        dependencies: List<String>.from(m['dependencies'] as List? ?? []),
        target: (m['target'] as num?)?.toDouble(),
        unit: m['unit'] as String? ?? '',
        rewardXp: m['rewardXp'] as int? ?? 10,
        skipPenalty: m['skipPenalty'] as int? ?? 5,
        mandatory: m['mandatory'] as bool? ?? true,
        reminder: PlannerReminder.fromMap(plannerMap(m['reminder'] ?? {})),
      );
}

class ChallengeTemplate {
  const ChallengeTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.difficulty,
    this.durationDays = 1,
    required this.tasks,
    required this.completionXp,
    this.failurePenalty = 0,
    this.skipPenalty,
    this.prerequisiteTemplateIds = const [],
    this.rewardMode = ChallengeRewardMode.legacyPerTask,
    this.categoryId,
    this.categoryName = '',
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String name;
  final String description;
  final ChallengeDifficulty? difficulty;
  final int durationDays;
  final List<ChallengeTaskDefinition> tasks;
  final int completionXp;
  final int failurePenalty;

  /// Null preserves pre-schema-4 package-only instances without skip events.
  /// New templates store an explicit value, including zero for an audit event.
  final int? skipPenalty;
  bool get recordsTaskSkips =>
      rewardMode == ChallengeRewardMode.legacyPerTask || skipPenalty != null;
  int skipPenaltyForTask(ChallengeTaskDefinition task) =>
      rewardMode == ChallengeRewardMode.legacyPerTask
      ? task.skipPenalty
      : skipPenalty ?? 0;
  final List<String> prerequisiteTemplateIds;
  final ChallengeRewardMode rewardMode;
  final String? categoryId;

  /// Frozen in an instance snapshot, independent of later category changes.
  final String categoryName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  List<ChallengeTaskDefinition> childrenOf(String? parentId) =>
      tasks.where((t) => t.parentId == parentId).toList();
  List<ChallengeTaskDefinition> get rootTasks => childrenOf(null);
  List<ChallengeTaskDefinition> get leafTasks =>
      tasks.where((t) => !t.isGroup).toList();
  bool isRequired(ChallengeTaskDefinition task) {
    final seen = <String>{};
    var current = task;
    while (true) {
      if (!current.mandatory || !seen.add(current.id)) return false;
      if (current.parentId == null) return true;
      final parent = tasks.where((t) => t.id == current.parentId).firstOrNull;
      if (parent == null) return false;
      current = parent;
    }
  }

  List<ChallengeTaskDefinition> get requiredLeafTasks =>
      leafTasks.where(isRequired).toList();
  int get totalPossibleXp =>
      completionXp +
      (rewardMode == ChallengeRewardMode.packageOnly
          ? 0
          : leafTasks.fold(
              0,
              (sum, task) =>
                  sum + task.rewardXp * task.dayOffsets.toSet().length,
            ));
  ChallengeTemplate forNewCommitments() =>
      rewardMode == ChallengeRewardMode.packageOnly
      ? this
      : copyWith(
          rewardMode: ChallengeRewardMode.packageOnly,
          completionXp: totalPossibleXp,
        );
  String get rules =>
      'Complete every mandatory task and every required step before the deadline. Tasks are available on their scheduled day. Skipped tasks never count as completed. Skipping a mandatory task makes completion impossible; the package fails at its deadline. No cancellation after starting. XP cannot fall below zero. Failure penalty: $failurePenalty XP.';
  ChallengeTemplate copyWith({
    String? id,
    String? name,
    String? description,
    ChallengeDifficulty? difficulty,
    int? durationDays,
    List<ChallengeTaskDefinition>? tasks,
    int? completionXp,
    int? failurePenalty,
    int? skipPenalty,
    List<String>? prerequisiteTemplateIds,
    ChallengeRewardMode? rewardMode,
    String? categoryId,
    String? categoryName,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearCategory = false,
    bool clearDifficulty = false,
  }) => ChallengeTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    difficulty: clearDifficulty ? null : difficulty ?? this.difficulty,
    durationDays: durationDays ?? this.durationDays,
    tasks: tasks ?? this.tasks,
    completionXp: completionXp ?? this.completionXp,
    failurePenalty: failurePenalty ?? this.failurePenalty,
    skipPenalty: skipPenalty ?? this.skipPenalty,
    prerequisiteTemplateIds:
        prerequisiteTemplateIds ?? this.prerequisiteTemplateIds,
    rewardMode: rewardMode ?? this.rewardMode,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        durationDays < 1 ||
        durationDays > 366 ||
        tasks.isEmpty ||
        completionXp < 0 ||
        failurePenalty < 0 ||
        skipPenalty != null && skipPenalty! < 0) {
      throw ArgumentError('Package rules are invalid.');
    }
    final byId = {for (final task in tasks) task.id: task};
    if (byId.length != tasks.length) {
      throw ArgumentError('Package task identifiers must be unique.');
    }
    for (final task in tasks) {
      if (task.id.isEmpty ||
          task.id.contains('/') ||
          task.id.contains('@') ||
          task.title.trim().isEmpty ||
          task.dayOffsets.isEmpty ||
          task.dayOffsets.any((d) => d < 0 || d >= durationDays) ||
          task.rewardXp < 0 ||
          task.skipPenalty < 0 ||
          task.durationMinutes < 1 ||
          task.durationMinutes > 1440 ||
          task.dependencies.any(
            (id) => !byId.containsKey(id) || byId[id]!.isGroup,
          ) ||
          task.parentId != null && (byId[task.parentId]?.isGroup != true)) {
        throw ArgumentError('Package task rules are invalid.');
      }
      if (task.isGroup) {
        final children = childrenOf(task.id);
        if (children.isEmpty ||
            !children.any((child) => child.mandatory) ||
            task.startMinute != null ||
            task.reminder.enabled ||
            task.steps.isNotEmpty ||
            task.target != null ||
            task.dependencies.isNotEmpty) {
          throw ArgumentError(
            'A task group needs required children and cannot have task rules.',
          );
        }
      } else {
        if ((task.type == ChallengeTaskType.scheduled) !=
            (task.startMinute != null)) {
          throw ArgumentError('Choose a start time for a scheduled task.');
        }
        PlannerItem(
          id: task.id,
          title: task.title,
          date: DateTime(2000),
          startMinute: task.startMinute,
          endMinute: task.startMinute == null
              ? null
              : (task.startMinute! + task.durationMinutes) % 1440,
          overnight:
              task.startMinute != null &&
              task.startMinute! + task.durationMinutes >= 1440,
          steps: task.steps,
          dependencies: task.dependencies,
          target: task.target,
          unit: task.unit,
          xp: task.rewardXp,
          reminder: task.reminder,
        ).validate();
      }
      final parents = <String>{task.id};
      var parentId = task.parentId;
      while (parentId != null) {
        if (!byId.containsKey(parentId)) {
          throw ArgumentError('A parent task group does not exist.');
        }
        if (!parents.add(parentId)) {
          throw ArgumentError('Task groups cannot form a cycle.');
        }
        parentId = byId[parentId]!.parentId;
      }
      for (final dependency in task.dependencies) {
        if (task.dayOffsets.any(
          (day) => !byId[dependency]!.dayOffsets.contains(day),
        )) {
          throw ArgumentError(
            'Package prerequisites must be scheduled on the same day.',
          );
        }
      }
    }
    if (requiredLeafTasks.isEmpty) {
      throw ArgumentError('A package needs required tasks.');
    }
    final visiting = <String>{}, visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw ArgumentError('Package prerequisites cannot form a cycle.');
      }
      for (final dependency in byId[id]!.dependencies) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in byId.keys) {
      visit(id);
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'difficulty': difficulty?.name,
    'durationDays': durationDays,
    'tasks': tasks.map((t) => t.toMap()).toList(),
    'completionXp': completionXp,
    'failurePenalty': failurePenalty,
    'skipPenalty': skipPenalty,
    'prerequisiteTemplateIds': List<String>.of(prerequisiteTemplateIds),
    'rewardMode': rewardMode.name,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
  factory ChallengeTemplate.fromMap(Map<String, dynamic> m) =>
      ChallengeTemplate(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
        difficulty: m['difficulty'] == null
            ? null
            : ChallengeDifficulty.values.byName(m['difficulty'] as String),
        durationDays: m['durationDays'] as int? ?? 1,
        tasks: (m['tasks'] as List)
            .map((t) => ChallengeTaskDefinition.fromMap(plannerMap(t)))
            .toList(),
        completionXp: m['completionXp'] as int,
        failurePenalty: m['failurePenalty'] as int? ?? 0,
        skipPenalty: m['skipPenalty'] as int?,
        prerequisiteTemplateIds: List<String>.from(
          m['prerequisiteTemplateIds'] as List? ?? [],
        ),
        rewardMode: ChallengeRewardMode.values.byName(
          m['rewardMode'] as String? ?? 'legacyPerTask',
        ),
        categoryId: m['categoryId'] as String?,
        categoryName: m['categoryName'] as String? ?? '',
        createdAt: m['createdAt'] == null
            ? null
            : DateTime.parse(m['createdAt'] as String),
        updatedAt: m['updatedAt'] == null
            ? null
            : DateTime.parse(m['updatedAt'] as String),
      );
}

class ChallengeInstance {
  const ChallengeInstance({
    required this.id,
    required this.snapshot,
    required this.startedAt,
    required this.startDate,
    required this.deadline,
    this.status = ChallengeStatus.active,
    this.endedAt,
  });
  final String id;
  final ChallengeTemplate snapshot;
  final DateTime startedAt;
  final DateTime startDate;
  final DateTime deadline;
  final ChallengeStatus status;
  final DateTime? endedAt;
  ChallengeInstance finish(ChallengeStatus status, DateTime at) =>
      ChallengeInstance(
        id: id,
        snapshot: snapshot,
        startedAt: startedAt,
        startDate: startDate,
        deadline: deadline,
        status: status,
        endedAt: at,
      );
  Map<String, dynamic> toMap() => {
    'id': id,
    'snapshot': snapshot.toMap(),
    'startedAt': startedAt.toIso8601String(),
    'startDate': plannerDateKey(startDate),
    'deadline': deadline.toIso8601String(),
    'status': status.name,
    'endedAt': endedAt?.toIso8601String(),
  };
  factory ChallengeInstance.fromMap(Map<String, dynamic> m) =>
      ChallengeInstance(
        id: m['id'] as String,
        snapshot: ChallengeTemplate.fromMap(plannerMap(m['snapshot'])),
        startedAt: DateTime.parse(m['startedAt'] as String),
        startDate: DateTime.parse(m['startDate'] as String),
        deadline: DateTime.parse(m['deadline'] as String),
        status: ChallengeStatus.values.byName(m['status'] as String),
        endedAt: m['endedAt'] == null
            ? null
            : DateTime.parse(m['endedAt'] as String),
      );
}

class XpTransaction {
  const XpTransaction({
    required this.id,
    required this.reason,
    required this.change,
    required this.type,
    required this.at,
    required this.idempotencyKey,
    this.relatedId,
  });
  final String id;
  final String reason;
  final int change;
  final String type;
  final DateTime at;
  final String idempotencyKey;
  final String? relatedId;
  Map<String, dynamic> toMap() => {
    'id': id,
    'reason': reason,
    'change': change,
    'type': type,
    'at': at.toIso8601String(),
    'idempotencyKey': idempotencyKey,
    'relatedId': relatedId,
  };
  factory XpTransaction.fromMap(Map<String, dynamic> m) => XpTransaction(
    id: m['id'] as String,
    reason: m['reason'] as String,
    change: m['change'] as int,
    type: m['type'] as String,
    at: DateTime.parse(m['at'] as String),
    idempotencyKey: m['idempotencyKey'] as String,
    relatedId: m['relatedId'] as String?,
  );
}

class PlannerAchievement {
  const PlannerAchievement({
    required this.id,
    required this.title,
    required this.unlockedAt,
  });
  final String id;
  final String title;
  final DateTime unlockedAt;
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'unlockedAt': unlockedAt.toIso8601String(),
  };
  factory PlannerAchievement.fromMap(Map<String, dynamic> m) =>
      PlannerAchievement(
        id: m['id'] as String,
        title: m['title'] as String,
        unlockedAt: DateTime.parse(m['unlockedAt'] as String),
      );
}

/// One authoritative commitment/selection outcome for a local target date.
/// The deadline is frozen as an instant so later setting/time-zone changes
/// cannot reopen a date that has already closed.
class DailySelection {
  const DailySelection({
    required this.targetDate,
    required this.deadline,
    required this.penalty,
    this.instanceId,
    this.missedAt,
    this.acknowledged = false,
  });
  final DateTime targetDate;
  final DateTime deadline;
  final int penalty;
  final String? instanceId;
  final DateTime? missedAt;
  final bool acknowledged;

  String get dateKey => plannerDateKey(targetDate);
  bool get isSelected => instanceId != null;
  bool get isMissed => missedAt != null;
  bool get isPending => !isSelected && !isMissed;
  DailySelection copyWith({
    String? instanceId,
    DateTime? missedAt,
    bool? acknowledged,
  }) => DailySelection(
    targetDate: targetDate,
    deadline: deadline,
    penalty: penalty,
    instanceId: instanceId ?? this.instanceId,
    missedAt: missedAt ?? this.missedAt,
    acknowledged: acknowledged ?? this.acknowledged,
  );
  Map<String, dynamic> toMap() => {
    'targetDate': dateKey,
    'deadline': deadline.toUtc().toIso8601String(),
    'penalty': penalty,
    'instanceId': instanceId,
    'missedAt': missedAt?.toUtc().toIso8601String(),
    'acknowledged': acknowledged,
  };
  factory DailySelection.fromMap(Map<String, dynamic> m) => DailySelection(
    targetDate: DateTime.parse(m['targetDate'] as String),
    deadline: DateTime.parse(m['deadline'] as String),
    penalty: m['penalty'] as int,
    instanceId: m['instanceId'] as String?,
    missedAt: m['missedAt'] == null
        ? null
        : DateTime.parse(m['missedAt'] as String),
    acknowledged: m['acknowledged'] as bool? ?? false,
  );
}

/// One aggregate transaction contains routines, commitments, outcomes and XP.
/// The repository commits it atomically; old Streak boxes remain independent.
class PlannerState {
  PlannerState({
    List<PlannerItem>? items,
    Map<String, PlannerItem>? overrides,
    Set<String>? exclusions,
    Map<String, CompletionRecord>? records,
    List<ChallengeInstance>? instances,
    List<XpTransaction>? ledger,
    List<PlannerAchievement>? achievements,
    Map<String, PlannerReminder>? reminders,
    List<ChallengeTemplate>? templates,
    List<DailySelection>? selections,
    List<ChallengeCategory>? categories,
    this.selectionDeadlineMinute = 1439,
    this.missedSelectionPenalty = 5,
    this.lastObservedAt,
    this.templatesInitialized = false,
  }) : items = items ?? [],
       overrides = overrides ?? {},
       exclusions = exclusions ?? {},
       records = records ?? {},
       instances = instances ?? [],
       ledger = ledger ?? [],
       achievements = achievements ?? [],
       reminders = reminders ?? {},
       templates = templates ?? [],
       selections = selections ?? [],
       categories = categories ?? [];
  static const schemaVersion = 4;
  final List<PlannerItem> items;
  final Map<String, PlannerItem> overrides;
  final Set<String> exclusions;
  final Map<String, CompletionRecord> records;
  final List<ChallengeInstance> instances;
  final List<XpTransaction> ledger;
  final List<PlannerAchievement> achievements;
  final Map<String, PlannerReminder> reminders;
  final List<ChallengeTemplate> templates;
  final List<DailySelection> selections;
  final List<ChallengeCategory> categories;
  int selectionDeadlineMinute;
  int missedSelectionPenalty;
  DateTime? lastObservedAt;
  bool templatesInitialized;
  bool get hasData =>
      items.isNotEmpty ||
      instances.isNotEmpty ||
      records.isNotEmpty ||
      ledger.isNotEmpty ||
      overrides.isNotEmpty ||
      achievements.isNotEmpty ||
      templates.isNotEmpty ||
      categories.isNotEmpty ||
      selections.any((s) => !s.isPending);
  int get balance => ledger.fold(0, (value, event) => value + event.change);
  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'items': items.map((i) => i.toMap()).toList(),
    'overrides': overrides.map((k, v) => MapEntry(k, v.toMap())),
    'exclusions': exclusions.toList(),
    'records': records.map((k, v) => MapEntry(k, v.toMap())),
    'instances': instances.map((i) => i.toMap()).toList(),
    'ledger': ledger.map((e) => e.toMap()).toList(),
    'achievements': achievements.map((a) => a.toMap()).toList(),
    'reminders': reminders.map((k, v) => MapEntry(k, v.toMap())),
    'templates': templates.map((t) => t.toMap()).toList(),
    'templatesInitialized': templatesInitialized,
    'categories': categories.map((c) => c.toMap()).toList(),
    'selections': selections.map((s) => s.toMap()).toList(),
    'selectionDeadlineMinute': selectionDeadlineMinute,
    'missedSelectionPenalty': missedSelectionPenalty,
    'lastObservedAt': lastObservedAt?.toUtc().toIso8601String(),
  };
  factory PlannerState.fromMap(Map<String, dynamic> m) {
    if (m.isEmpty) return PlannerState();
    if (m['schemaVersion'] != 1 &&
        m['schemaVersion'] != 2 &&
        m['schemaVersion'] != 3 &&
        m['schemaVersion'] != schemaVersion) {
      throw StateError(
        'Unsupported Level Up data version. Your saved data has not been changed.',
      );
    }
    final state = PlannerState(
      items: (m['items'] as List)
          .map((i) => PlannerItem.fromMap(plannerMap(i)))
          .toList(),
      overrides: plannerMap(
        m['overrides'],
      ).map((k, v) => MapEntry(k, PlannerItem.fromMap(plannerMap(v)))),
      exclusions: Set<String>.from(m['exclusions'] as List),
      records: plannerMap(
        m['records'],
      ).map((k, v) => MapEntry(k, CompletionRecord.fromMap(plannerMap(v)))),
      instances: (m['instances'] as List)
          .map((i) => ChallengeInstance.fromMap(plannerMap(i)))
          .toList(),
      ledger: (m['ledger'] as List)
          .map((e) => XpTransaction.fromMap(plannerMap(e)))
          .toList(),
      achievements: (m['achievements'] as List)
          .map((a) => PlannerAchievement.fromMap(plannerMap(a)))
          .toList(),
      reminders: plannerMap(
        m['reminders'] ?? {},
      ).map((k, v) => MapEntry(k, PlannerReminder.fromMap(plannerMap(v)))),
      templates: (m['templates'] as List? ?? []).map((t) {
        final template = ChallengeTemplate.fromMap(plannerMap(t));
        if (m['schemaVersion'] == schemaVersion) return template;
        return template.forNewCommitments().copyWith(
          skipPenalty: template.skipPenalty ?? 0,
        );
      }).toList(),
      categories: (m['categories'] as List? ?? [])
          .map((c) => ChallengeCategory.fromMap(plannerMap(c)))
          .toList(),
      templatesInitialized: m['templatesInitialized'] as bool? ?? false,
      selections: (m['selections'] as List? ?? [])
          .map((s) => DailySelection.fromMap(plannerMap(s)))
          .toList(),
      selectionDeadlineMinute: m['selectionDeadlineMinute'] as int? ?? 1439,
      missedSelectionPenalty: m['missedSelectionPenalty'] as int? ?? 5,
      lastObservedAt: m['lastObservedAt'] == null
          ? null
          : DateTime.parse(m['lastObservedAt'] as String),
    );
    if (state.ledger.map((e) => e.idempotencyKey).toSet().length !=
            state.ledger.length ||
        state.balance < 0) {
      throw StateError(
        'The XP history is inconsistent. Your saved data has not been changed.',
      );
    }
    for (final item in [...state.items, ...state.overrides.values]) {
      item.validate();
    }
    state._validateHistory();
    return state;
  }

  void _validateHistory() {
    Never invalid(String reason) =>
        throw StateError('$reason Your saved data has not been changed.');
    bool unique(Iterable<String> ids) => ids.length == ids.toSet().length;
    bool occurrenceKey(String key) {
      final split = key.lastIndexOf('@');
      if (split < 1) return false;
      final suffix = key.substring(split + 1);
      final parsed = DateTime.tryParse(suffix);
      return parsed != null && plannerDateKey(parsed) == suffix;
    }

    if (!unique(items.map((item) => item.id)) ||
        !unique(instances.map((instance) => instance.id)) ||
        !unique(ledger.map((event) => event.id)) ||
        !unique(achievements.map((achievement) => achievement.id))) {
      invalid('Saved identifiers are duplicated.');
    }
    if (items.any((item) => item.id.contains('/'))) {
      invalid('An ordinary activity uses a reserved challenge identifier.');
    }
    var runningBalance = 0;
    final balancesBefore = <String, int>{};
    for (final event in ledger) {
      balancesBefore[event.idempotencyKey] = runningBalance;
      runningBalance += event.change;
      if (event.id.isEmpty ||
          event.idempotencyKey.isEmpty ||
          event.reason.trim().isEmpty ||
          runningBalance < 0) {
        invalid('The XP history is inconsistent.');
      }
      if ((event.type == 'task_completion' ||
                  event.type == 'challenge_completion') &&
              event.change < 0 ||
          (event.type == 'task_skip' || event.type == 'challenge_failure') &&
              event.change > 0) {
        invalid('An XP transaction contradicts its event type.');
      }
    }
    for (final entry in overrides.entries) {
      if (!occurrenceKey(entry.key) ||
          !entry.key.startsWith('${entry.value.id}@') ||
          !items.any((item) => item.id == entry.value.id) ||
          entry.value.recurrence != PlannerRecurrence.once) {
        invalid('An occurrence override has an invalid original identifier.');
      }
    }
    for (final entry in records.entries) {
      if (!occurrenceKey(entry.key)) {
        invalid('A task occurrence has an invalid date identifier.');
      }
      final record = entry.value;
      final steps = record.completedSteps;
      if (!record.amount.isFinite ||
          record.amount < 0 ||
          steps.toSet().length != steps.length ||
          List.generate(
            steps.length,
            (index) => index,
          ).any((index) => !steps.contains(index)) ||
          record.status != CompletionStatus.pending && record.at == null) {
        invalid('A saved task completion record is invalid.');
      }
    }
    for (final reminder in reminders.values) {
      if (reminder.offsetMinutes < 0 ||
          reminder.offsetMinutes > 10080 ||
          reminder.minute != null &&
              (reminder.minute! < 0 || reminder.minute! >= 1440)) {
        invalid('A saved reminder preference is invalid.');
      }
    }
    final events = {for (final event in ledger) event.idempotencyKey: event};
    if (selectionDeadlineMinute < 0 ||
        selectionDeadlineMinute >= 1440 ||
        missedSelectionPenalty < 0 ||
        missedSelectionPenalty > 1000000 ||
        !unique(templates.map((t) => t.id)) ||
        !unique(categories.map((c) => c.id)) ||
        categories.any((c) => c.id.isEmpty || c.name.trim().isEmpty) ||
        categories.map((c) => c.name.trim().toLowerCase()).toSet().length !=
            categories.length ||
        !unique(selections.map((s) => s.dateKey))) {
      invalid('Saved selection rules or identifiers are invalid.');
    }
    for (final template in templates) {
      template.validate();
      if (template.categoryId != null &&
          !categories.any((c) => c.id == template.categoryId)) {
        invalid('A package category reference is missing.');
      }
    }
    for (final selection in selections) {
      final event = events['missed_selection:${selection.dateKey}'];
      if (selection.penalty < 0 ||
          selection.penalty > 1000000 ||
          selection.isSelected && selection.isMissed ||
          selection.isSelected &&
              !instances.any(
                (i) =>
                    i.id == selection.instanceId &&
                    plannerDateKey(i.startDate) == selection.dateKey &&
                    i.startedAt.isBefore(selection.deadline),
              ) ||
          selection.isMissed &&
              (event == null ||
                  selection.missedAt != selection.deadline ||
                  event.type != 'missed_selection' ||
                  event.relatedId != selection.dateKey ||
                  event.change !=
                      -math.min(
                        selection.penalty,
                        balancesBefore['missed_selection:${selection.dateKey}']!,
                      )) ||
          !selection.isMissed && event != null) {
        invalid('A daily package selection has inconsistent history.');
      }
    }
    for (final event in ledger.where((e) => e.type == 'missed_selection')) {
      if (!selections.any(
        (selection) =>
            selection.isMissed &&
            event.idempotencyKey == 'missed_selection:${selection.dateKey}',
      )) {
        invalid(
          'A missed-selection transaction has no matching daily outcome.',
        );
      }
    }
    for (final instance in instances) {
      try {
        instance.snapshot.validate();
      } catch (_) {
        invalid('A saved challenge snapshot has invalid rules.');
      }
      if (instance.id.isEmpty ||
          instance.id.contains('/') ||
          instance.id.contains('@') ||
          instance.deadline !=
              plannerAddDays(
                instance.startDate,
                instance.snapshot.durationDays,
              ) ||
          (instance.status == ChallengeStatus.active) !=
              (instance.endedAt == null)) {
        invalid('A saved challenge lifecycle is inconsistent.');
      }
      var mandatoryComplete = true;
      for (final task in instance.snapshot.leafTasks) {
        for (final offset in task.dayOffsets.toSet()) {
          final id =
              '${instance.id}/${task.id}@${plannerDateKey(plannerAddDays(instance.startDate, offset))}';
          final record = records[id];
          if (record == null ||
              record.completedSteps.length > task.steps.length) {
            invalid('A challenge task record is missing or inconsistent.');
          }
          if (instance.snapshot.isRequired(task) &&
              record.status != CompletionStatus.completed) {
            mandatoryComplete = false;
          }
          if (record.status == CompletionStatus.completed &&
              (record.completedSteps.length != task.steps.length ||
                  task.target != null && record.amount < task.target! ||
                  (instance.snapshot.rewardMode ==
                          ChallengeRewardMode.legacyPerTask
                      ? events['complete:$id']?.change != task.rewardXp ||
                            events['complete:$id']?.type != 'task_completion'
                      : events.containsKey('complete:$id')))) {
            invalid(
              'A challenge completion does not satisfy its captured rules.',
            );
          }
          if (record.status == CompletionStatus.skipped &&
              (instance.snapshot.recordsTaskSkips
                  ? events['skip:$id'] == null ||
                        events['skip:$id']?.type != 'task_skip' ||
                        events['skip:$id']!.change !=
                            -math.min(
                              instance.snapshot.skipPenaltyForTask(task),
                              balancesBefore['skip:$id']!,
                            ) ||
                        events.containsKey('complete:$id')
                  : events.containsKey('skip:$id') ||
                        events.containsKey('complete:$id'))) {
            invalid('A skipped challenge task has inconsistent XP history.');
          }
          if (record.status == CompletionStatus.pending &&
              (events.containsKey('skip:$id') ||
                  events.containsKey('complete:$id'))) {
            invalid(
              'A pending challenge task already has a terminal XP event.',
            );
          }
        }
      }
      if (instance.status == ChallengeStatus.completed &&
          (!mandatoryComplete ||
              events['package:${instance.id}']?.change !=
                  instance.snapshot.completionXp ||
              events['package:${instance.id}']?.type !=
                  'challenge_completion' ||
              events.containsKey('failure:${instance.id}'))) {
        invalid('A completed challenge has inconsistent results.');
      }
      if (instance.status == ChallengeStatus.failed &&
          (events['failure:${instance.id}'] == null ||
              events['failure:${instance.id}']?.type != 'challenge_failure' ||
              events['failure:${instance.id}']!.change !=
                  -math.min(
                    instance.snapshot.failurePenalty,
                    balancesBefore['failure:${instance.id}']!,
                  ) ||
              events.containsKey('package:${instance.id}'))) {
        invalid('A failed challenge has inconsistent results.');
      }
      if (instance.status == ChallengeStatus.active &&
          (events.containsKey('failure:${instance.id}') ||
              events.containsKey('package:${instance.id}'))) {
        invalid('An active challenge already has a terminal XP event.');
      }
    }
  }
}

class LevelProgression {
  const LevelProgression({this.baseXp = 100, this.growthXp = 50});
  final int baseXp;
  final int growthXp;
  int threshold(int level) {
    if (level < 1 || baseXp <= 0 || growthXp < 0) {
      throw ArgumentError(
        'Level rules require a positive base and non-negative growth.',
      );
    }
    return (level - 1) * baseXp + ((level - 1) * (level - 2) ~/ 2) * growthXp;
  }

  int levelFor(int xp) {
    var level = 1;
    while (xp >= threshold(level + 1)) {
      level++;
    }
    return level;
  }

  double progress(int xp) {
    final level = levelFor(xp);
    return math.max(
      0,
      (xp - threshold(level)) / (threshold(level + 1) - threshold(level)),
    );
  }
}
