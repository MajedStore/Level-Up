import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';
import 'package:streak/features/planner/widgets/planner_timeline_geometry.dart';
export 'planner_timeline_geometry.dart';

/// Navigation commands reuse the timeline's existing ScrollController.
class PlannerTimelineNavigation {
  _PlannerTimelineState? _state;
  bool _visible = true;
  Future<void> returnToNow() => _state?._returnToNow() ?? Future.value();
  void setVisible(bool visible) {
    _visible = visible;
    _state?._setClockVisible(visible);
  }

  void refreshClock() => _state?._tickClock();
}

class PlannerTimeline extends StatefulWidget {
  const PlannerTimeline({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onAdd,
    this.header,
    this.showChallenges = true,
    this.initialDay,
    this.navigation,
  });
  final PlannerController controller;
  final ValueChanged<PlannerOccurrence> onOpen;
  final ValueChanged<DateTime> onAdd;
  final Widget? header;
  final bool showChallenges;
  final DateTime? initialDay;
  final PlannerTimelineNavigation? navigation;
  @override
  State<PlannerTimeline> createState() => _PlannerTimelineState();
}

class _PlannerTimelineState extends State<PlannerTimeline> {
  late final DateTime _origin = plannerDay(
    widget.initialDay ?? widget.controller.now,
  );
  late DateTime _first = plannerAddDays(_origin, -7);
  late DateTime _focused = _origin;
  final _scroll = ScrollController();
  late final ValueNotifier<DateTime> _clock = ValueNotifier(
    widget.controller.now,
  );
  final _layouts = <String, PlannerDayLayout>{};
  Timer? _clockTimer;
  bool _clockVisible = true;
  int _count = 98;
  double _scale = 1;
  bool _initialized = false;
  bool _reanchoring = false;
  Future<void>? _returning;
  double get _dayHeader => 64 * math.max(1, _scale.clamp(1, 1.5));
  static const _dayBottom = 24.0;
  double get _pinnedHeight => math.max(56, 28 * _scale + 24);
  @override
  void initState() {
    super.initState();
    widget.navigation?._state = this;
    _clockVisible = widget.navigation?._visible ?? true;
    widget.controller.addListener(_changed);
    _scroll.addListener(_scrolled);
    _scheduleClockTick();
  }

  @override
  void didUpdateWidget(covariant PlannerTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      if (identical(oldWidget.navigation?._state, this)) {
        oldWidget.navigation?._state = null;
      }
      widget.navigation?._state = this;
      _clockVisible = widget.navigation?._visible ?? true;
      _scheduleClockTick();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  PlannerDayLayout _layout(DateTime day) => _layouts.putIfAbsent(
    plannerDateKey(day),
    () => PlannerDayLayout(
      day,
      widget.controller
          .occurrences(day)
          .where((o) => widget.showChallenges || !o.isChallenge),
      textScale: _scale,
    ),
  );
  double _extra(DateTime day) =>
      _layout(day).unscheduled.length * 96 * math.max(1, _scale);
  double _offsetForDay(DateTime day) {
    final index = plannerDayDistance(_first, day).clamp(0, _count - 1);
    var value = 0.0;
    for (var i = 0; i < index; i++) {
      final date = plannerAddDays(_first, i);
      value += _dayHeader + _layout(date).height + _extra(date) + _dayBottom;
    }
    return value;
  }

  (DateTime, double) _anchor() {
    var remaining = _scroll.hasClients ? _scroll.offset : 0.0;
    for (var i = 0; i < _count; i++) {
      final day = plannerAddDays(_first, i);
      final layout = _layout(day);
      final height = _dayHeader + layout.height + _extra(day) + _dayBottom;
      // Accumulated subpixel heights must not label an exactly aligned day
      // header as the preceding date after a long scroll or buffer prepend.
      if (remaining + .01 < height) {
        return (day, layout.minuteForY(remaining - _dayHeader));
      }
      remaining = math.max(0, remaining - height);
    }
    return (_focused, 0);
  }

  void _changed() {
    if (!mounted) return;
    final anchor = _anchor();
    _layouts.clear();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _returning == null) {
        _scroll.jumpTo(
          (_offsetForDay(anchor.$1) +
                  _dayHeader +
                  _layout(anchor.$1).yForMinute(anchor.$2))
              .clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _scrolled() {
    if (_reanchoring) return;
    final day = _anchor().$1;
    if (_focused != day) setState(() => _focused = day);
    if (_scroll.offset < 220) {
      final anchor = _anchor();
      _reanchoring = true;
      setState(() {
        _first = plannerAddDays(_first, -30);
        _count += 30;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            (_offsetForDay(anchor.$1) +
                    _dayHeader +
                    _layout(anchor.$1).yForMinute(anchor.$2))
                .clamp(0, _scroll.position.maxScrollExtent),
          );
        }
        _reanchoring = false;
      });
    } else if (_scroll.position.extentAfter < 1600) {
      _reanchoring = true;
      setState(() => _count += 60);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reanchoring = false;
      });
    }
  }

  void _today() {
    final day = plannerDay(widget.controller.now);
    final layout = _layout(day);
    final minute = layout.events.isEmpty
        ? widget.controller.now.hour * 60
        : layout.events.first.startMinute;
    _scroll.jumpTo(
      (_offsetForDay(day) +
              _dayHeader +
              layout.yForMinute(math.max(0, minute - 40)))
          .clamp(0, _scroll.position.maxScrollExtent),
    );
  }

  Future<void> _returnToNow() {
    if (_returning != null) return _returning!;
    final work = _animateToNow();
    _returning = work.whenComplete(() => _returning = null);
    return _returning!;
  }

  Future<void> _animateToNow() async {
    if (!mounted || !_scroll.hasClients) return;
    final now = widget.controller.now;
    final day = plannerDay(now);
    final index = plannerDayDistance(_first, day);
    if (index < 0 || index >= _count) {
      setState(() {
        if (index < 0) {
          _count += -index + 7;
          _first = plannerAddDays(day, -7);
        } else {
          _count = index + 60;
        }
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
    }
    final minute = math.max(0, now.hour * 60 + now.minute - 45);
    final target =
        (_offsetForDay(day) + _dayHeader + _layout(day).yForMinute(minute))
            .clamp(0.0, _scroll.position.maxScrollExtent);
    final distance = (target - _scroll.offset).abs();
    if (distance < 2) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    await _scroll.animateTo(
      target,
      duration: Duration(
        milliseconds: (280 + distance * .035).clamp(280, 680).round(),
      ),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (_scale != scale) {
      final anchor = _anchor();
      _scale = scale;
      _layouts.clear();
      if (_initialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(
              (_offsetForDay(anchor.$1) +
                      _dayHeader +
                      _layout(anchor.$1).yForMinute(anchor.$2))
                  .clamp(0, _scroll.position.maxScrollExtent),
            );
          }
        });
      }
    }
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _today();
      });
    }
  }

  @override
  void dispose() {
    if (identical(widget.navigation?._state, this)) {
      widget.navigation?._state = null;
    }
    widget.controller.removeListener(_changed);
    _clockTimer?.cancel();
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setClockVisible(bool visible) {
    if (_clockVisible == visible) return;
    _clockVisible = visible;
    _clockTimer?.cancel();
    _clockTimer = null;
    if (visible) _tickClock();
  }

  void _scheduleClockTick() {
    _clockTimer?.cancel();
    _clockTimer = null;
    if (!mounted || !_clockVisible) return;
    final now = DateTime.now();
    final remaining = 60000 - (now.millisecondsSinceEpoch % 60000);
    _clockTimer = Timer(
      Duration(milliseconds: remaining),
      _tickClock,
    );
  }

  void _tickClock() {
    if (!mounted) return;
    _clock.value = widget.controller.now;
    _scheduleClockTick();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: _pinnedHeight,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  key: ValueKey('timeline-focus-${plannerDateKey(_focused)}'),
                  plannerLocalDate(context, _focused, compact: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.header != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: widget.header!,
                ),
              ],
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: context.plannerText('addRoutine'),
                onPressed: () => widget.onAdd(_focused),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xBDFFFFFF),
                Colors.white,
                Colors.white,
                Color(0xBDFFFFFF),
              ],
              stops: [
                0,
                math.min(.07, 24 / bounds.height),
                math.max(.93, 1 - 24 / bounds.height),
                1,
              ],
            ).createShader(bounds),
            child: CustomScrollView(
              key: const PageStorageKey('timeline-scroll'),
              controller: _scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final day = plannerAddDays(_first, index);
                      return Column(
                        key: ValueKey('timeline-day-${plannerDateKey(day)}'),
                        children: [
                          _TimelineDay(
                            layout: _layout(day),
                            headerHeight: _dayHeader,
                            now: _clock,
                            onOpen: widget.onOpen,
                            onAdd: widget.onAdd,
                            alternate: index.isEven,
                          ),
                        ],
                      );
                    },
                    childCount: _count,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String> ||
                          !key.value.startsWith('timeline-day-')) {
                        return null;
                      }
                      final date = DateTime.tryParse(
                        key.value.substring('timeline-day-'.length),
                      );
                      if (date == null) return null;
                      final index = plannerDayDistance(_first, date);
                      return index >= 0 && index < _count ? index : null;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _TimelineDay extends StatelessWidget {
  const _TimelineDay({
    required this.layout,
    required this.headerHeight,
    required this.now,
    required this.onOpen,
    required this.onAdd,
    required this.alternate,
  });
  final PlannerDayLayout layout;
  final double headerHeight;
  final ValueListenable<DateTime> now;
  final ValueChanged<PlannerOccurrence> onOpen;
  final ValueChanged<DateTime> onAdd;
  final bool alternate;
  List<Widget> _events(
    BuildContext context,
    double available,
    double gutter,
    double scale,
  ) {
    final columns = math.max(
      1,
      (available / (100 * math.min(scale, 1.5))).floor(),
    );
    final widgets = <Widget>[];
    final groups = <int, List<PlannerTimelineEvent>>{};
    for (final event in layout.events) {
      (groups[event.overlapGroup] ??= []).add(event);
    }
    for (final group in groups.values) {
      final lanes = group.first.laneCount;
      final shown = math.min(lanes, columns);
      final dense = lanes > columns;
      final overflow = dense
          ? group.where((e) => e.lane >= shown - 1).toList()
          : <PlannerTimelineEvent>[];
      for (final event in group.where((e) => !overflow.contains(e))) {
        widgets.add(
          PositionedDirectional(
            key: ValueKey(
              'timeline-event-${event.occurrence.id}-${plannerDateKey(layout.day)}',
            ),
            start: gutter + event.lane * available / shown,
            width: available / shown - 5,
            top: layout.yForMinute(event.startMinute),
            height:
                layout.yForMinute(event.endMinute) -
                layout.yForMinute(event.startMinute) -
                2,
            child: _TimelineEventBlock(
              event: event,
              day: layout.day,
              onOpen: onOpen,
            ),
          ),
        );
      }
      if (overflow.isNotEmpty) {
        final from = overflow.map((e) => e.startMinute).reduce(math.min);
        final to = overflow.map((e) => e.endMinute).reduce(math.max);
        final names = overflow
            .map((e) => plannerOccurrenceTitle(context, e.occurrence))
            .join(', ');
        widgets.add(
          PositionedDirectional(
            key: ValueKey(
              'timeline-overlap-${plannerDateKey(layout.day)}-${group.first.overlapGroup}',
            ),
            start: gutter + (shown - 1) * available / shown,
            width: available / shown - 5,
            top: layout.yForMinute(from),
            height: layout.yForMinute(to) - layout.yForMinute(from) - 2,
            child: Semantics(
              button: true,
              label:
                  '${context.plannerText('overlaps')}: $names, ${overflow.any((e) => e.occurrence.isChallenge) ? context.plannerText('challengeTask') : context.plannerText('routineTask')}',
              child: Material(
                color: context.colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (sheet) => SafeArea(
                      child: DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: .5,
                        builder: (_, scroll) => ListView(
                          controller: scroll,
                          padding: const EdgeInsets.all(20),
                          children: [
                            Text(
                              context.plannerText('overlaps'),
                              style: Theme.of(sheet).textTheme.titleLarge,
                            ),
                            for (final event in overflow)
                              OccurrenceTile(
                                occurrence: event.occurrence,
                                onTap: () {
                                  Navigator.pop(sheet);
                                  onOpen(event.occurrence);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, bounds) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.layers_outlined, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                plannerNumber(context, overflow.length),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              if (overflow.any(
                                (e) => e.occurrence.isChallenge,
                              )) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.emoji_events_outlined,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                          if (bounds.maxHeight > 110) ...[
                            const SizedBox(height: 4),
                            Text(
                              context.plannerText('overlaps'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                names,
                                overflow: TextOverflow.fade,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final gutter = math.min(100.0, 64 * math.max(1, scale)).toDouble();
    return Material(
      color: alternate
          ? context.colors.surface
          : context.colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      plannerLocalDate(context, layout.day, weekday: true),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth - gutter - 16;
              return SizedBox(
                height: layout.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PositionedDirectional(
                      start: gutter - 8,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: context.colors.outlineVariant.withValues(
                          alpha: .45,
                        ),
                      ),
                    ),
                    for (var hour = 0; hour <= 24; hour++) ...[
                      PositionedDirectional(
                        start: 5,
                        top: (layout.yForMinute(hour * 60) - 9).clamp(
                          0,
                          layout.height - 20,
                        ),
                        width: gutter - 20,
                        child: ExcludeSemantics(
                          child: Text(
                            '${plannerNumber(context, hour % 24).padLeft(2, Localizations.localeOf(context).languageCode == 'ar' ? '٠' : '0')}:٠٠'
                                .replaceAll(
                                  '٠٠',
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'ar'
                                      ? '٠٠'
                                      : '00',
                                ),
                            maxLines: 1,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: context.tokens.muted),
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: gutter - 8,
                        end: 16,
                        top: layout.yForMinute(hour * 60),
                        child: Divider(
                          height: 1,
                          thickness: .5,
                          color: context.colors.outlineVariant.withValues(
                            alpha: .25,
                          ),
                        ),
                      ),
                    ],
                    if (layout.events.isEmpty)
                      PositionedDirectional(
                        start: gutter + 10,
                        end: 20,
                        top: layout.yForMinute(9 * 60),
                        child: Text(
                          context.plannerText('emptyTimeline'),
                          style: TextStyle(color: context.tokens.muted),
                        ),
                      ),
                    ..._events(context, available, gutter, scale),
                    ValueListenableBuilder<DateTime>(
                      valueListenable: now,
                      builder: (context, current, _) {
                        if (plannerDateKey(current) !=
                            plannerDateKey(layout.day)) {
                          return const SizedBox.shrink();
                        }
                        return PositionedDirectional(
                          key: const ValueKey('timeline-now'),
                          start: gutter - 12,
                          end: 12,
                          top: layout.yForMinute(
                            current.hour * 60 + current.minute,
                          ),
                          child: IgnorePointer(
                            child: FractionalTranslation(
                              translation: const Offset(0, -.5),
                              child: Row(
                                textDirection: rtl
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: context.colors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      key: const ValueKey('timeline-now-line'),
                                      height: 1.5,
                                      color: context.colors.primary,
                                    ),
                                  ),
                                  Text(
                                    context.plannerText('now'),
                                    style: TextStyle(
                                      color: context.colors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          for (final occurrence in layout.unscheduled)
            Container(
              height: 96 * math.max(1, scale),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Tooltip(
                message: plannerOccurrenceTitle(context, occurrence),
                child: DefaultTextStyle.merge(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: OccurrenceTile(
                    occurrence: occurrence,
                    onTap: () => onOpen(occurrence),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TimelineEventBlock extends StatelessWidget {
  const _TimelineEventBlock({
    required this.event,
    required this.day,
    required this.onOpen,
  });
  final PlannerTimelineEvent event;
  final DateTime day;
  final ValueChanged<PlannerOccurrence> onOpen;
  @override
  Widget build(BuildContext context) {
    final o = event.occurrence;
    final status = o.record.status;
    final challenge = o.isChallenge;
    final title = plannerOccurrenceTitle(context, o);
    final icon = challenge
        ? Icons.emoji_events_outlined
        : switch (o.item.category) {
            'Study' => Icons.school_outlined,
            'Fitness' => Icons.directions_run,
            'Work' => Icons.work_outline,
            'Rest' => Icons.bedtime_outlined,
            _ => Icons.schedule,
          };
    final color = challenge ? context.colors.primary : context.colors.onSurface;
    final accent = challenge
        ? context.colors.primary
        : switch (o.item.category) {
            'Study' => context.tokens.info,
            'Fitness' => context.tokens.success,
            'Work' => context.tokens.warning,
            _ => context.tokens.muted,
          };
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: () => onOpen(o),
      label:
          '$title, ${plannerInterval(o, context: context)}, ${context.plannerText(challenge ? 'challengeTask' : 'routineTask')}, ${context.plannerText(status.name)}',
      child: Tooltip(
        message: '$title · ${plannerInterval(o, context: context)}',
        child: Material(
          color: challenge
              ? context.colors.primary.withValues(alpha: .16)
              : context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(o),
            child: Container(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: status == CompletionStatus.pending
                        ? accent
                        : accent.withValues(alpha: .35),
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 6, 5),
              child: LayoutBuilder(
                builder: (context, bounds) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        if (status != CompletionStatus.pending) ...[
                          const SizedBox(width: 4),
                          Icon(
                            status == CompletionStatus.completed
                                ? Icons.check
                                : Icons.remove_circle_outline,
                            size: 16,
                            color: status == CompletionStatus.completed
                                ? context.tokens.success
                                : context.tokens.warning,
                          ),
                        ],
                        if (o.item.reminder.enabled &&
                            bounds.maxWidth > 100) ...[
                          const Spacer(),
                          Icon(
                            Icons.notifications_none,
                            size: 14,
                            color: context.tokens.muted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: math.max(
                          1,
                          ((bounds.maxHeight - 22) /
                                  (18 *
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(14) /
                                      14))
                              .floor(),
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: status == CompletionStatus.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (bounds.maxHeight > 95)
                      Text(
                        plannerInterval(o, context: context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.tokens.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
