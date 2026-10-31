// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/planner/data/challenge_catalog.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:uuid/uuid.dart';

class PlannerController extends ChangeNotifier {
  PlannerController({
    DateTime Function()? clock,
    Map<String, dynamic>? initial,
    Future<void> Function(Map<String, dynamic>)? persist,
    this.afterCommit,
    List<ChallengeTemplate>? catalog,
    this.loadLatest,
    this.transaction,
    this.deadlineForLocalDay,
  }) : _clock = clock ?? DateTime.now,
       _persist =
           persist ??
           ((value) => LocalStore.writeSetting('levelUpState', value)),
       _injected = initial != null,
       _state = PlannerState.fromMap(
         initial ?? LocalStore.settingMap('levelUpState'),
       ),
       _catalog = catalog ?? levelUpChallengeCatalog {
    if (!_state.templatesInitialized) {
      _state.templates.addAll(
        _catalog.map(
          (t) => ChallengeTemplate.fromMap(
            t
                .forNewCommitments()
                .copyWith(skipPenalty: t.skipPenalty ?? 0)
                .toMap(),
          ),
        ),
      );
      _state.templatesInitialized = true;
    }
  }

  final DateTime Function() _clock;
  final Future<void> Function(Map<String, dynamic>) _persist;
  final bool _injected;
  final List<ChallengeTemplate> _catalog;
  Future<void> Function()? afterCommit;
  final Future<Map<String, dynamic>?> Function()? loadLatest;
  final Future<void> Function(Future<void> Function())? transaction;

  /// Injectable local-zone resolver for DST tests. Production uses the device's
  /// local time zone; each resolved deadline is persisted as a UTC instant.
  final DateTime Function(DateTime day, int minute)? deadlineForLocalDay;
  PlannerState _state;
  Future<void> _queue = Future.value();
  String? sideEffectError;
  bool _disposed = false;
  DateTime? _operationTime;
  static const progression = LevelProgression();
  DateTime get now => _operationTime ?? _clock();
  Map<String, dynamic> get exportState =>
      PlannerState.fromMap(_state.toMap()).toMap();
  bool get hasData => _state.hasData;
  // Clone through maps so callers cannot mutate an active historical snapshot.
  List<PlannerItem> get items => List.unmodifiable(
    _state.items.map((i) => PlannerItem.fromMap(i.toMap())),
  );
  List<ChallengeInstance> get instances => List.unmodifiable(
    _state.instances.map((i) => ChallengeInstance.fromMap(i.toMap())),
  );
  List<ChallengeTemplate> get templates => List.unmodifiable(
    _state.templates.map((t) => ChallengeTemplate.fromMap(t.toMap())),
  );
  List<ChallengeCategory> get categories =>
      List.unmodifiable(_state.categories);
  List<DailySelection> get selections => List.unmodifiable(_state.selections);
  DailySelection? selectionFor(DateTime target) {
    final key = plannerDateKey(target);
    return _state.selections.where((s) => s.dateKey == key).firstOrNull;
  }

  DailySelection? get tomorrowSelection =>
      selectionFor(plannerAddDays(plannerDay(now), 1));
  List<DailySelection> get unacknowledgedMisses =>
      selections.where((s) => s.isMissed && !s.acknowledged).toList();
  int get selectionDeadlineMinute => _state.selectionDeadlineMinute;
  int get missedSelectionPenalty => _state.missedSelectionPenalty;
  DateTime? get nextSelectionDeadline {
    final pending =
        selections.where((s) => s.isPending).map((s) => s.deadline).toList()
          ..sort();
    return pending.firstOrNull;
  }

  List<XpTransaction> get ledger => List.unmodifiable(_state.ledger);
  List<PlannerAchievement> get achievements =>
      List.unmodifiable(_state.achievements);
  int get balance => _state.balance;
  int get level => progression.levelFor(balance);
  int get nextLevelXp => progression.threshold(level + 1);
  double get levelProgress => progression.progress(balance);
  int get earnedXp =>
      ledger.where((e) => e.change > 0).fold(0, (sum, e) => sum + e.change);
  int get lostXp =>
      -ledger.where((e) => e.change < 0).fold(0, (sum, e) => sum + e.change);
  int get completedCount => _state.records.values
      .where((r) => r.status == CompletionStatus.completed)
      .length;
  int get skippedCount => _state.records.values
      .where((r) => r.status == CompletionStatus.skipped)
      .length;
  int get currentStreak => _streaks(_state).$1;
  int get bestStreak => _streaks(_state).$2;
  int get completedChallengeCount =>
      instances.where((i) => i.status == ChallengeStatus.completed).length;
  int get failedChallengeCount =>
      instances.where((i) => i.status == ChallengeStatus.failed).length;

  Future<T> _change<T>(
    T Function(PlannerState draft) action, {
    bool evaluationOnly = false,
    PlannerState? replacement,
  }) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      var committed = false;
      var loadedChanged = false;
      Object? failure;
      StackTrace? failureStack;
      late T value;
      Future<void> run() async {
        try {
          final latest = await loadLatest?.call();
          if (latest != null) {
            loadedChanged = jsonEncode(latest) != jsonEncode(_state.toMap());
            _state = PlannerState.fromMap(latest);
            if (!_state.templatesInitialized) {
              _state.templates.addAll(
                _catalog.map(
                  (t) => ChallengeTemplate.fromMap(
                    t
                        .forNewCommitments()
                        .copyWith(skipPenalty: t.skipPenalty ?? 0)
                        .toMap(),
                  ),
                ),
              );
              _state.templatesInitialized = true;
            }
          }
          final observed = _clock();
          final highWater = _state.lastObservedAt;
          _operationTime = highWater != null && observed.isBefore(highWater)
              ? observed.add(highWater.difference(observed))
              : observed;
          final draft = PlannerState.fromMap((replacement ?? _state).toMap());
          _evaluate(draft);
          final evaluated = PlannerState.fromMap(draft.toMap());
          final evaluationChanged =
              jsonEncode(evaluated.toMap()) != jsonEncode(_state.toMap());
          try {
            value = action(draft);
          } catch (error, stack) {
            // A rejected late action must still persist the deadline transition.
            if (evaluationChanged) {
              _awardAchievements(evaluated);
              await _commit(evaluated);
              committed = true;
            }
            Error.throwWithStackTrace(error, stack);
          }
          _evaluate(draft);
          _awardAchievements(draft);
          if (!evaluationOnly ||
              evaluationChanged ||
              draft.achievements.length != _state.achievements.length) {
            await _commit(draft);
            committed = true;
          }
        } catch (error, stack) {
          failure = error;
          failureStack = stack;
        }
      }

      try {
        if (transaction == null) {
          await run();
        } else {
          await transaction!(run);
        }
        if (committed) await _runAfterCommit();
        if (!committed && loadedChanged && !_disposed) notifyListeners();
        if (failure != null) {
          result.completeError(failure!, failureStack);
        } else {
          result.complete(value);
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _operationTime = null;
      }
    });
    return result.future;
  }

  Future<void> _commit(PlannerState state) async {
    state.lastObservedAt = now.toUtc();
    await _persist(state.toMap());
    _state = state;
    sideEffectError = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _runAfterCommit() async {
    try {
      await afterCommit?.call();
    } catch (error) {
      sideEffectError =
          'Your data was saved, but reminders could not refresh: $error';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> reload() async {
    await _queue;
    if (!_injected && loadLatest == null) {
      _state = PlannerState.fromMap(LocalStore.settingMap('levelUpState'));
    }
    if (!_disposed) notifyListeners();
    await evaluate();
  }

  Future<void> evaluate() => _change((_) {}, evaluationOnly: true);

  /// Replaces all planner data (schedule, challenges, XP) with [state], e.g.
  /// from an imported export. It goes through the normal commit path, so it
  /// is evaluated at the current time, persisted, and synced like any edit.
  Future<void> replaceState(Map<String, dynamic> state) =>
      _change((_) {}, replacement: PlannerState.fromMap(state));

  static DateTime weekStart(
    DateTime day, {
    int firstWeekday = DateTime.monday,
  }) =>
      plannerAddDays(plannerDay(day), -((day.weekday - firstWeekday + 7) % 7));
  List<PlannerOccurrence> occurrences(
    DateTime day, {
    bool includeUnscheduled = true,
  }) => _occurrences(
    _state,
    day,
  ).where((o) => includeUnscheduled || o.isScheduled).toList();
  List<PlannerOccurrence> tasksFor(DateTime day) => occurrences(day);
  List<PlannerOccurrence> conflictsFor(PlannerOccurrence occurrence) {
    if (!occurrence.isScheduled) return [];
    final candidates = [
      for (var offset = -1; offset <= 1; offset++)
        ...occurrences(plannerAddDays(occurrence.day, offset)),
    ];
    return {
      for (final other in candidates)
        if (other.id != occurrence.id && occurrence.overlaps(other))
          other.id: other,
    }.values.toList();
  }

  List<PlannerOccurrence> _occurrences(PlannerState state, DateTime selected) {
    final day = plannerDay(selected);
    final tomorrow = plannerAddDays(day, 1);
    final found = <String, PlannerOccurrence>{};
    void add(
      String id,
      PlannerItem item,
      DateTime origin, {
      String? challengeId,
      DateTime? validUntil,
    }) {
      final reminder = state.reminders[id] ?? state.reminders[item.id];
      final occurrence = PlannerOccurrence(
        id: id,
        item: reminder == null ? item : item.copyWith(reminder: reminder),
        day: origin,
        challengeId: challengeId,
        validUntil: validUntil,
        record: state.records[id] ?? const CompletionRecord(),
      );
      final visible = occurrence.start == null
          ? plannerDateKey(origin) == plannerDateKey(day)
          : occurrence.start!.isBefore(tomorrow) &&
                occurrence.end!.isAfter(day);
      if (visible) {
        // Detach only visible data; a schedule query need not clone the ledger.
        found[id] = PlannerOccurrence(
          id: id,
          item: PlannerItem.fromMap(occurrence.item.toMap()),
          day: origin,
          challengeId: challengeId,
          validUntil: validUntil,
          record: CompletionRecord.fromMap(occurrence.record.toMap()),
        );
      }
    }

    for (final item in state.items) {
      for (final origin in [plannerAddDays(day, -1), day]) {
        final id = '${item.id}@${plannerDateKey(origin)}';
        if (item.occursOn(origin) &&
            !state.exclusions.contains(id) &&
            !state.overrides.containsKey(id)) {
          add(id, item, origin);
        }
      }
    }
    for (final entry in state.overrides.entries) {
      if (!state.exclusions.contains(entry.key)) {
        add(entry.key, entry.value, entry.value.date);
      }
    }
    for (final instance in state.instances) {
      for (final task in instance.snapshot.leafTasks) {
        for (final offset in task.dayOffsets.toSet()) {
          final origin = plannerAddDays(instance.startDate, offset);
          if (origin.isBefore(plannerAddDays(day, -1)) ||
              !origin.isBefore(tomorrow)) {
            continue;
          }
          final item = _challengeItem(instance, task, origin);
          final id = '${item.id}@${plannerDateKey(origin)}';
          final begins = item.startMinute == null
              ? origin
              : DateTime(
                  origin.year,
                  origin.month,
                  origin.day,
                  item.startMinute! ~/ 60,
                  item.startMinute! % 60,
                );
          if (instance.status != ChallengeStatus.active &&
              instance.endedAt != null &&
              !begins.isBefore(instance.endedAt!) &&
              state.records[id]?.status == CompletionStatus.pending) {
            continue;
          }
          add(
            id,
            item,
            origin,
            challengeId: instance.id,
            validUntil: instance.endedAt ?? instance.deadline,
          );
        }
      }
    }
    return found.values.toList()..sort((a, b) {
      final byTime = (a.start ?? tomorrow).compareTo(b.start ?? tomorrow);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  PlannerItem _challengeItem(
    ChallengeInstance instance,
    ChallengeTaskDefinition task,
    DateTime date,
  ) {
    final end = task.startMinute == null
        ? null
        : (task.startMinute! + task.durationMinutes) % 1440;
    return PlannerItem(
      id: '${instance.id}/${task.id}',
      title: task.title,
      description: task.description,
      category: instance.snapshot.name,
      date: date,
      startMinute: task.startMinute,
      endMinute: end,
      overnight:
          task.startMinute != null &&
          task.startMinute! + task.durationMinutes >= 1440,
      steps: task.steps,
      target: task.target,
      unit: task.unit,
      dependencies: task.dependencies.map((d) => '${instance.id}/$d').toList(),
      xp: instance.snapshot.rewardMode == ChallengeRewardMode.packageOnly
          ? 0
          : task.rewardXp,
      reminder: task.reminder,
    );
  }

  Future<void> saveItem(PlannerItem item, {DateTime? occurrenceDay}) => _change(
    (state) {
      item.validate();
      if (item.id.contains('/')) {
        throw StateError('Challenge task definitions cannot be edited.');
      }
      if (occurrenceDay != null) {
        if (!state.items.any((i) => i.id == item.id)) {
          throw StateError('The recurring activity no longer exists.');
        }
        final id = '${item.id}@${plannerDateKey(occurrenceDay)}';
        state.overrides[id] = PlannerItem.fromMap(
          item.copyWith(recurrence: PlannerRecurrence.once).toMap(),
        );
        state.exclusions.remove(id);
        state.reminders.remove(id);
        if (state.reminders.containsKey(item.id)) {
          // An explicit occurrence edit takes precedence over an inherited
          // series preference while other dates keep their configuration.
          state.reminders[id] = PlannerReminder.fromMap(item.reminder.toMap());
        }
      } else {
        final index = state.items.indexWhere((i) => i.id == item.id);
        final saved = PlannerItem.fromMap(item.toMap());
        if (index < 0) {
          state.items.add(saved);
        } else {
          state.items[index] = saved;
        }
        state.reminders.removeWhere(
          (key, _) => key == item.id || key.startsWith('${item.id}@'),
        );
        state.overrides.updateAll(
          (_, override) => override.id == item.id
              ? override.copyWith(reminder: saved.reminder)
              : override,
        );
      }
      _validateDependencies(state);
    },
  );

  Future<void> deleteItem(String id, {DateTime? occurrenceDay}) => _change((
    state,
  ) {
    if (id.contains('/')) {
      throw StateError('An active challenge cannot be cancelled or deleted.');
    }
    if (occurrenceDay == null) {
      state.items.removeWhere((i) => i.id == id);
      state.overrides.removeWhere((key, _) => key.startsWith('$id@'));
    } else {
      final occurrenceId = '$id@${plannerDateKey(occurrenceDay)}';
      state.exclusions.add(occurrenceId);
      state.overrides.remove(occurrenceId);
    }
  });

  PlannerOccurrence _resolve(PlannerState state, String id) {
    final split = id.lastIndexOf('@');
    if (split < 1) throw StateError('Task occurrence not found.');
    final date = DateTime.tryParse(id.substring(split + 1));
    if (date == null) throw StateError('Task date is invalid.');
    final override = state.overrides[id];
    final matches = _occurrences(
      state,
      override?.date ?? date,
    ).where((o) => o.id == id);
    if (matches.isEmpty) throw StateError('This task is no longer available.');
    return matches.first;
  }

  PlannerOccurrence? occurrenceById(String id) {
    try {
      return _resolve(_state, id);
    } catch (_) {
      return null;
    }
  }

  void _assertAvailable(PlannerState state, PlannerOccurrence occurrence) {
    if (occurrence.record.status != CompletionStatus.pending) return;
    if (plannerDay(occurrence.day).isAfter(plannerDay(now))) {
      throw StateError(
        'This task becomes available on ${plannerDateKey(occurrence.day)}.',
      );
    }
    if (occurrence.challengeId != null &&
        state.instances
                .firstWhere((i) => i.id == occurrence.challengeId)
                .status !=
            ChallengeStatus.active) {
      throw StateError('This challenge has ended. Its history is read-only.');
    }
    for (final dependency in occurrence.item.dependencies) {
      final sameDay = '$dependency@${plannerDateKey(occurrence.day)}';
      if (state.records[sameDay]?.status == CompletionStatus.completed) {
        continue;
      }
      // Dependencies on standalone one-off tasks can have an earlier due date.
      final base = state.items.where(
        (i) => i.id == dependency && i.recurrence == PlannerRecurrence.once,
      );
      if (base.isNotEmpty &&
          state
                  .records['$dependency@${plannerDateKey(base.first.date)}']
                  ?.status ==
              CompletionStatus.completed) {
        continue;
      }
      String? title = base.firstOrNull?.title;
      if (title == null) {
        try {
          title = _resolve(state, sameDay).title;
        } catch (_) {
          /* Deleted prerequisite. */
        }
      }
      throw StateError(
        title == null
            ? 'Complete the prerequisite task first.'
            : 'Complete the prerequisite task first: $title.',
      );
    }
  }

  Future<void> complete(String id) => _change((state) {
    final occurrence = _resolve(state, id);
    if (occurrence.record.status != CompletionStatus.pending) return;
    _assertAvailable(state, occurrence);
    // Steps are no longer a feature; older data may still carry them, but
    // they never block completion.
    if (occurrence.item.target != null &&
        occurrence.record.amount < occurrence.item.target!) {
      throw StateError(
        'Record at least ${occurrence.item.target} ${occurrence.item.unit} first.',
      );
    }
    _finishTask(state, occurrence);
  });

  Future<void> completeStep(String id, int index) => _change((state) {
    final occurrence = _resolve(state, id);
    if (occurrence.record.status != CompletionStatus.pending) return;
    _assertAvailable(state, occurrence);
    if (index < 0 || index >= occurrence.item.steps.length) {
      throw RangeError('Step does not exist.');
    }
    final done = occurrence.record.completedSteps.toSet();
    if (done.contains(index)) return;
    if (List.generate(index, (i) => i).any((i) => !done.contains(i))) {
      throw StateError('Complete the earlier steps first.');
    }
    done.add(index);
    state.records[id] = CompletionRecord(
      completedSteps: done.toList()..sort(),
      amount: occurrence.record.amount,
      at: now,
    );
    final updated = _resolve(state, id);
    if (done.length == occurrence.item.steps.length &&
        (occurrence.item.target == null ||
            occurrence.record.amount >= occurrence.item.target!)) {
      _finishTask(state, updated);
    }
  });

  Future<void> recordAmount(String id, double amount) => _change((state) {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('Enter a finite, non-negative amount.');
    }
    final occurrence = _resolve(state, id);
    if (occurrence.record.status != CompletionStatus.pending) return;
    _assertAvailable(state, occurrence);
    if (occurrence.item.target == null) {
      throw StateError('This task has no amount target.');
    }
    state.records[id] = CompletionRecord(
      completedSteps: occurrence.record.completedSteps,
      amount: amount,
      at: now,
    );
    if (amount >= occurrence.item.target!) {
      _finishTask(state, _resolve(state, id));
    }
  });

  void _finishTask(PlannerState state, PlannerOccurrence occurrence) {
    state.records[occurrence.id] = CompletionRecord(
      status: CompletionStatus.completed,
      completedSteps: occurrence.record.completedSteps,
      amount: occurrence.record.amount,
      at: now,
    );
    if (!occurrence.isChallenge ||
        state.instances
                .firstWhere((i) => i.id == occurrence.challengeId)
                .snapshot
                .rewardMode ==
            ChallengeRewardMode.packageOnly) {
      return;
    }
    _xp(
      state,
      'complete:${occurrence.id}',
      occurrence.item.xp,
      'Completed ${occurrence.title}',
      'task_completion',
      occurrence.id,
    );
  }

  int skipPenaltyFor(PlannerOccurrence occurrence) {
    if (!occurrence.isChallenge) return 0;
    final instance = _state.instances.firstWhere(
      (i) => i.id == occurrence.challengeId,
    );
    return instance.snapshot.skipPenaltyForTask(
      instance.snapshot.tasks.firstWhere(
        (t) => occurrence.item.id == '${instance.id}/${t.id}',
      ),
    );
  }

  Future<void> skip(String id) => _change((state) {
    final occurrence = _resolve(state, id);
    if (occurrence.record.status != CompletionStatus.pending) return;
    // Skipping must be possible even when a prerequisite was skipped.
    if (plannerDay(occurrence.day).isAfter(plannerDay(now))) {
      throw StateError('Future tasks cannot be skipped early.');
    }
    var penalty = 0;
    if (occurrence.challengeId != null) {
      final instance = state.instances.firstWhere(
        (i) => i.id == occurrence.challengeId,
      );
      if (instance.status != ChallengeStatus.active) {
        throw StateError('This challenge has ended.');
      }
      penalty = instance.snapshot.skipPenaltyForTask(
        instance.snapshot.tasks.firstWhere(
          (t) => occurrence.item.id == '${instance.id}/${t.id}',
        ),
      );
    }
    state.records[id] = CompletionRecord(
      status: CompletionStatus.skipped,
      completedSteps: occurrence.record.completedSteps,
      amount: occurrence.record.amount,
      at: now,
    );
    if (!occurrence.isChallenge ||
        !state.instances
            .firstWhere((i) => i.id == occurrence.challengeId)
            .snapshot
            .recordsTaskSkips) {
      return;
    }
    _xp(
      state,
      'skip:$id',
      -penalty,
      'Skipped ${occurrence.title} (configured penalty: $penalty XP; balance floors at zero)',
      'task_skip',
      id,
    );
  });

  Future<void> setReminder(
    String occurrenceId,
    PlannerReminder reminder, {
    bool entireSeries = false,
  }) => _change((state) {
    final occurrence = _resolve(state, occurrenceId);
    occurrence.item.copyWith(reminder: reminder).validate();
    state.reminders[entireSeries ? occurrence.itemId : occurrenceId] =
        PlannerReminder.fromMap(reminder.toMap());
  });

  /// Seeds legacy immediate commitments for regression tests. Product flows
  /// must use assignTomorrow/assignPackage so each new date has one assignment.
  /// Existing instances remain valid even if old versions allowed several.
  @visibleForTesting
  Future<ChallengeInstance> startChallenge(
    ChallengeTemplate template, {
    DateTime? startDate,
  }) =>
      _change((state) => _startInstance(state, template, startDate: startDate));

  ChallengeInstance _startInstance(
    PlannerState state,
    ChallengeTemplate template, {
    DateTime? startDate,
  }) {
    _validateTemplate(template);
    final date = plannerDay(startDate ?? now);
    if (date.isBefore(plannerDay(now))) {
      throw ArgumentError('A challenge cannot start in the past.');
    }
    for (final prerequisite in template.prerequisiteTemplateIds) {
      if (!state.instances.any(
        (i) =>
            i.snapshot.id == prerequisite &&
            i.status == ChallengeStatus.completed,
      )) {
        throw StateError(
          'Complete the prerequisite package first: $prerequisite.',
        );
      }
    }
    final instance = ChallengeInstance(
      id: const Uuid().v4(),
      snapshot: ChallengeTemplate.fromMap(
        _withCategoryName(state, template).toMap(),
      ),
      startedAt: now,
      startDate: date,
      deadline: plannerAddDays(date, template.durationDays),
    );
    state.instances.add(instance);
    for (final task in instance.snapshot.leafTasks) {
      for (final offset in task.dayOffsets.toSet()) {
        state.records['${instance.id}/${task.id}@${plannerDateKey(plannerAddDays(date, offset))}'] =
            const CompletionRecord();
      }
    }
    return ChallengeInstance.fromMap(instance.toMap());
  }

  ChallengeTemplate _withCategoryName(
    PlannerState state,
    ChallengeTemplate template,
  ) {
    if (template.categoryId == null) return template;
    final category = state.categories
        .where((c) => c.id == template.categoryId)
        .firstOrNull;
    if (category == null) throw ArgumentError('Package category not found.');
    return template.copyWith(categoryName: category.name);
  }

  Future<ChallengeCategory> saveCategory({String? id, required String name}) =>
      _change((state) {
        final trimmed = name.trim();
        if (trimmed.isEmpty || id == '') {
          throw ArgumentError('Enter a category name.');
        }
        if (state.categories.any(
          (c) => c.id != id && c.name.toLowerCase() == trimmed.toLowerCase(),
        )) {
          throw ArgumentError('A category with this name already exists.');
        }
        final category = ChallengeCategory(
          id: id ?? const Uuid().v4(),
          name: trimmed,
        );
        final index = state.categories.indexWhere((c) => c.id == category.id);
        if (index < 0) {
          state.categories.add(category);
        } else {
          state.categories[index] = category;
        }
        for (var i = 0; i < state.templates.length; i++) {
          if (state.templates[i].categoryId == category.id) {
            state.templates[i] = state.templates[i].copyWith(
              categoryName: trimmed,
            );
          }
        }
        return category;
      });

  Future<void> deleteCategory(String id) => _change((state) {
    state.categories.removeWhere((c) => c.id == id);
    for (var i = 0; i < state.templates.length; i++) {
      if (state.templates[i].categoryId == id) {
        state.templates[i] = state.templates[i].copyWith(clearCategory: true);
      }
    }
  });

  Future<void> saveTemplate(ChallengeTemplate template) => _change((state) {
    template.validate();
    final saved = ChallengeTemplate.fromMap(
      _withCategoryName(state, template).toMap(),
    );
    final index = state.templates.indexWhere((t) => t.id == template.id);
    if (index < 0) {
      state.templates.add(saved);
    } else {
      state.templates[index] = saved;
    }
  });

  Future<void> deleteTemplate(String id) => _change((state) {
    state.templates.removeWhere((t) => t.id == id);
  });

  Future<ChallengeTemplate> duplicateTemplate(String id, {String? name}) =>
      _change((state) {
        final original = state.templates.where((t) => t.id == id).firstOrNull;
        if (original == null) throw StateError('Package template not found.');
        final map = original.toMap();
        map['id'] = const Uuid().v4();
        map['name'] = name?.trim().isNotEmpty == true
            ? name!.trim()
            : original.name;
        map['createdAt'] = now.toIso8601String();
        map['updatedAt'] = now.toIso8601String();
        final duplicate = ChallengeTemplate.fromMap(map);
        state.templates.add(duplicate);
        return ChallengeTemplate.fromMap(duplicate.toMap());
      });

  Future<ChallengeInstance> assignTomorrow(String templateId) =>
      assignPackage(templateId, plannerAddDays(plannerDay(now), 1));

  Future<ChallengeInstance> assignPackage(
    String templateId,
    DateTime targetDate,
  ) => _change((state) {
    final target = plannerDay(targetDate);
    if (target != plannerAddDays(plannerDay(now), 1)) {
      throw StateError('Choose a package for tomorrow.');
    }
    final index = state.selections.indexWhere(
      (s) => s.dateKey == plannerDateKey(target),
    );
    if (index < 0) {
      throw StateError('The selection deadline has passed.');
    }
    final selection = state.selections[index];
    if (!selection.isPending) {
      throw StateError(
        selection.isSelected
            ? 'A package is already assigned to this date.'
            : 'The selection deadline has passed.',
      );
    }
    if (!now.isBefore(selection.deadline)) {
      throw StateError('The selection deadline has passed.');
    }
    final template = state.templates
        .where((t) => t.id == templateId)
        .firstOrNull;
    if (template == null) throw StateError('Package template not found.');
    final instance = _startInstance(state, template, startDate: target);
    state.selections[index] = selection.copyWith(instanceId: instance.id);
    return instance;
  });

  /// Tomorrow's package has not started, so it can still be withdrawn. The
  /// date's selection reopens with its original deadline: before it, another
  /// package can be chosen; after it, the missed-selection penalty applies.
  Future<void> cancelTomorrow() => _change((state) {
    final target = plannerAddDays(plannerDay(now), 1);
    final index = state.selections.indexWhere(
      (s) => s.dateKey == plannerDateKey(target),
    );
    final selection = index < 0 ? null : state.selections[index];
    final instance = state.instances
        .where((i) => i.id == selection?.instanceId)
        .firstOrNull;
    if (selection == null || instance == null) {
      throw StateError('No package is assigned to tomorrow.');
    }
    final prefix = '${instance.id}/';
    if (plannerDateKey(instance.startDate) != selection.dateKey ||
        instance.status != ChallengeStatus.active ||
        state.ledger.any(
          (e) =>
              e.relatedId == instance.id ||
              (e.relatedId?.startsWith(prefix) ?? false),
        )) {
      throw StateError('This package has already started.');
    }
    state.instances.removeWhere((i) => i.id == instance.id);
    state.records.removeWhere((key, _) => key.startsWith(prefix));
    state.overrides.removeWhere((key, _) => key.startsWith(prefix));
    state.reminders.removeWhere((key, _) => key.startsWith(prefix));
    state.exclusions.removeWhere((key) => key.startsWith(prefix));
    state.selections[index] = DailySelection(
      targetDate: selection.targetDate,
      deadline: selection.deadline,
      penalty: selection.penalty,
    );
  });

  Future<void> updateSelectionRules({
    required int deadlineMinute,
    required int missedPenalty,
  }) => _change((state) {
    if (deadlineMinute < 0 ||
        deadlineMinute >= 1440 ||
        missedPenalty < 0 ||
        missedPenalty > 1000000) {
      throw ArgumentError('Daily selection rules are invalid.');
    }
    state.selectionDeadlineMinute = deadlineMinute;
    state.missedSelectionPenalty = missedPenalty;
    // Only the still-open selection for tomorrow can receive edited rules.
    // Closed/historical outcomes retain the rules in effect at commitment.
    final target = plannerAddDays(plannerDay(now), 1);
    final index = state.selections.indexWhere(
      (s) => s.dateKey == plannerDateKey(target),
    );
    if (index >= 0 && state.selections[index].isPending) {
      state.selections[index] = _newSelection(state, target);
    }
  });

  Future<void> acknowledgeMissedSelections() => _change((state) {
    for (var i = 0; i < state.selections.length; i++) {
      final selection = state.selections[i];
      if (selection.isMissed && !selection.acknowledged) {
        state.selections[i] = selection.copyWith(acknowledged: true);
      }
    }
  });

  Future<void> cancelChallenge(String id) => Future.error(
    StateError(
      'A started challenge cannot be cancelled. You can skip individual tasks under its stated rules.',
    ),
  );

  /// Required descendant leaves are the progress denominator. Groups never own
  /// persisted completion records and cannot complete their children.
  List<ChallengeTaskDefinition> _requiredDescendants(
    ChallengeTemplate template,
    String nodeId,
  ) {
    final node = template.tasks.firstWhere((t) => t.id == nodeId);
    if (!node.isGroup) return [node];
    return [
      for (final child in template.childrenOf(nodeId).where((t) => t.mandatory))
        ..._requiredDescendants(template, child.id),
    ];
  }

  List<String> _nodeOccurrenceIds(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) => [
    for (final task in _requiredDescendants(instance.snapshot, nodeId))
      for (final offset in task.dayOffsets.toSet())
        if (day == null ||
            plannerDateKey(plannerAddDays(instance.startDate, offset)) ==
                plannerDateKey(day))
          '${instance.id}/${task.id}@${plannerDateKey(plannerAddDays(instance.startDate, offset))}',
  ];

  CompletionStatus taskNodeStatus(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) {
    final ids = _nodeOccurrenceIds(instance, nodeId, day: day);
    if (ids.isEmpty) return CompletionStatus.pending;
    if (ids.every(
      (id) => _state.records[id]?.status == CompletionStatus.completed,
    )) {
      return CompletionStatus.completed;
    }
    if (ids.any(
      (id) => _state.records[id]?.status == CompletionStatus.skipped,
    )) {
      return CompletionStatus.skipped;
    }
    return CompletionStatus.pending;
  }

  CompletionStatus groupStatus(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) => taskNodeStatus(instance, nodeId, day: day);
  int groupTotalCount(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) => _nodeOccurrenceIds(instance, nodeId, day: day).length;
  int groupCompletedCount(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) => _nodeOccurrenceIds(instance, nodeId, day: day)
      .where((id) => _state.records[id]?.status == CompletionStatus.completed)
      .length;
  double groupProgress(
    ChallengeInstance instance,
    String nodeId, {
    DateTime? day,
  }) {
    final total = groupTotalCount(instance, nodeId, day: day);
    return total == 0
        ? 0
        : groupCompletedCount(instance, nodeId, day: day) / total;
  }

  int challengeTotalCount(ChallengeInstance instance) => instance
      .snapshot
      .requiredLeafTasks
      .fold(0, (sum, t) => sum + t.dayOffsets.toSet().length);
  int challengeCompletedCount(ChallengeInstance instance) => [
    for (final task in instance.snapshot.requiredLeafTasks)
      for (final offset in task.dayOffsets.toSet())
        '${instance.id}/${task.id}@${plannerDateKey(plannerAddDays(instance.startDate, offset))}',
  ].where((id) => _state.records[id]?.status == CompletionStatus.completed).length;
  double challengeProgress(ChallengeInstance instance) =>
      challengeTotalCount(instance) == 0
      ? 0
      : challengeCompletedCount(instance) / challengeTotalCount(instance);

  void _evaluate(PlannerState state) {
    _evaluateSelections(state);
    for (var index = 0; index < state.instances.length; index++) {
      final instance = state.instances[index];
      if (instance.status != ChallengeStatus.active) continue;
      final required = [
        for (final task in instance.snapshot.requiredLeafTasks)
          for (final offset in task.dayOffsets.toSet())
            '${instance.id}/${task.id}@${plannerDateKey(plannerAddDays(instance.startDate, offset))}',
      ];
      // Deadline wins if a completion command arrives at/after expiration.
      if (!now.isBefore(instance.deadline)) {
        state.instances[index] = instance.finish(
          ChallengeStatus.failed,
          instance.deadline,
        );
        _xp(
          state,
          'failure:${instance.id}',
          -instance.snapshot.failurePenalty,
          'Failed ${instance.snapshot.name} (configured penalty: ${instance.snapshot.failurePenalty} XP)',
          'challenge_failure',
          instance.id,
        );
      } else if (required.isNotEmpty &&
          required.every(
            (id) => state.records[id]?.status == CompletionStatus.completed,
          )) {
        state.instances[index] = instance.finish(
          ChallengeStatus.completed,
          now,
        );
        _xp(
          state,
          'package:${instance.id}',
          instance.snapshot.completionXp,
          'Completed ${instance.snapshot.name}',
          'challenge_completion',
          instance.id,
        );
      }
    }
  }

  DailySelection _newSelection(PlannerState state, DateTime target) {
    final selectionDay = plannerAddDays(target, -1);
    final minute = state.selectionDeadlineMinute;
    final deadline =
        deadlineForLocalDay?.call(selectionDay, minute) ??
        DateTime(
          selectionDay.year,
          selectionDay.month,
          selectionDay.day,
          minute ~/ 60,
          minute % 60,
        );
    // Old versions allowed independently activated future packages. Keep every
    // instance, and honor the earliest commitment as that date's assignment.
    final legacy =
        state.instances
            .where((i) => plannerDateKey(i.startDate) == plannerDateKey(target))
            .toList()
          ..sort((a, b) {
            final byStart = a.startedAt.compareTo(b.startedAt);
            return byStart != 0 ? byStart : a.id.compareTo(b.id);
          });
    final original = legacy.firstOrNull;
    final fixedDeadline =
        original != null && !original.startedAt.isBefore(deadline)
        ? original.startedAt.toUtc().add(const Duration(microseconds: 1))
        : deadline.toUtc();
    return DailySelection(
      targetDate: plannerDay(target),
      deadline: fixedDeadline,
      penalty: state.missedSelectionPenalty,
      instanceId: original?.id,
    );
  }

  void _evaluateSelections(PlannerState state) {
    final tomorrow = plannerAddDays(plannerDay(now), 1);
    if (state.selections.isEmpty) {
      // Enrollment starts today. Migration never charges for pre-feature days.
      state.selections.add(_newSelection(state, tomorrow));
    } else {
      var latest = state.selections
          .map((s) => s.targetDate)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      while (latest.isBefore(tomorrow)) {
        latest = plannerAddDays(latest, 1);
        state.selections.add(_newSelection(state, latest));
      }
    }
    for (var i = 0; i < state.selections.length; i++) {
      final selection = state.selections[i];
      if (!selection.isPending || now.isBefore(selection.deadline)) continue;
      state.selections[i] = selection.copyWith(missedAt: selection.deadline);
      _xp(
        state,
        'missed_selection:${selection.dateKey}',
        -selection.penalty,
        'Missed package selection for ${selection.dateKey} (configured penalty: ${selection.penalty} XP)',
        'missed_selection',
        selection.dateKey,
      );
    }
  }

  void _xp(
    PlannerState state,
    String key,
    int requested,
    String reason,
    String type,
    String related,
  ) {
    if (state.ledger.any((e) => e.idempotencyKey == key)) return;
    final actual = math.max(-state.balance, requested);
    state.ledger.add(
      XpTransaction(
        id: const Uuid().v4(),
        reason: reason,
        change: actual,
        type: type,
        at: now,
        idempotencyKey: key,
        relatedId: related,
      ),
    );
  }

  (int, int) _streaks(PlannerState state) {
    final days =
        state.records.values
            .where(
              (r) => r.status == CompletionStatus.completed && r.at != null,
            )
            .map((r) => plannerDateKey(r.at!))
            .toSet()
            .map(DateTime.parse)
            .toList()
          ..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      run = previous != null && plannerDayDistance(previous, day) == 1
          ? run + 1
          : 1;
      best = math.max(best, run);
      previous = day;
    }
    var current = 0;
    var cursor = plannerDay(now);
    final keys = days.map(plannerDateKey).toSet();
    if (!keys.contains(plannerDateKey(cursor))) {
      cursor = plannerAddDays(cursor, -1);
    }
    while (keys.contains(plannerDateKey(cursor))) {
      current++;
      cursor = plannerAddDays(cursor, -1);
    }
    return (current, best);
  }

  void _awardAchievements(PlannerState state) {
    void unlock(String id, String title, bool condition) {
      if (condition && !state.achievements.any((a) => a.id == id)) {
        state.achievements.add(
          PlannerAchievement(id: id, title: title, unlockedAt: now),
        );
      }
    }

    final completed = state.records.values
        .where((r) => r.status == CompletionStatus.completed)
        .length;
    unlock('first-task', 'First task completed', completed >= 1);
    unlock(
      'first-package',
      'First package completed',
      state.instances.any((i) => i.status == ChallengeStatus.completed),
    );
    unlock(
      'seven-days',
      'Seven days of qualifying activity',
      _streaks(state).$2 >= 7,
    );
    unlock(
      'first-hard',
      'First hard package completed',
      state.instances.any(
        (i) =>
            i.status == ChallengeStatus.completed &&
            i.snapshot.difficulty == ChallengeDifficulty.hard,
      ),
    );
    unlock('fifty-tasks', 'Fifty tasks completed', completed >= 50);
  }

  void _validateDependencies(PlannerState state) {
    final graph = {for (final item in state.items) item.id: item.dependencies};
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw ArgumentError('Task prerequisites cannot form a cycle.');
      }
      for (final dependency in graph[id] ?? <String>[]) {
        if (!graph.containsKey(dependency)) {
          throw ArgumentError(
            'A prerequisite task does not exist: $dependency.',
          );
        }
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in graph.keys) {
      visit(id);
    }
  }

  void _validateTemplate(ChallengeTemplate template) => template.validate();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
