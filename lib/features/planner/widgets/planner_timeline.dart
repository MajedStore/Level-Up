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
    this.banner,
    this.showChallenges = true,
    this.initialDay,
    this.navigation,
    this.zoom = 1,
    this.onZoom,
  });
  final PlannerController controller;
  final ValueChanged<PlannerOccurrence> onOpen;
  final ValueChanged<DateTime> onAdd;
  final Widget? header;

  /// Shown under the header, above the scrolling days. When set, today's
  /// untimed challenge tasks are left to it rather than listed again.
  final Widget? banner;
  final bool showChallenges;
  final DateTime? initialDay;
  final PlannerTimelineNavigation? navigation;

  /// Vertical scale: 1 is the overview, larger values spread the hours out so
  /// times can be read precisely.
  final double zoom;

  /// When set, pinch and the zoom buttons change [zoom] through it.
  final ValueChanged<double>? onZoom;

  static const minZoom = 0.5;
  static const maxZoom = 8.0;

  /// Stops used by the zoom buttons; pinching moves freely between them.
  static const zoomSteps = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0];

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

  /// Pointers on the timeline, for two-finger zoom. A Listener sees them
  /// without competing with the scroll gesture.
  final _pointers = <int, Offset>{};
  double? _pinchDistance;
  double _pinchZoom = 1;

  /// Viewport height the next zoom keeps fixed: the pinch midpoint, or the
  /// middle of the view for the buttons.
  double? _zoomFocus;
  bool get _pinching => _pinchDistance != null;

  List<Offset> get _pinchPoints => _pointers.values.take(2).toList();

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (widget.onZoom != null && _pointers.length == 2) {
      final points = _pinchPoints;
      setState(() {
        _pinchDistance = math.max(1, (points[0] - points[1]).distance);
        _pinchZoom = widget.zoom;
      });
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final base = _pinchDistance;
    if (base == null || _pointers.length < 2) return;
    final points = _pinchPoints;
    _zoomFocus = (points[0].dy + points[1].dy) / 2;
    final next =
        ((_pinchZoom * (points[0] - points[1]).distance / base) * 100).round() /
        100;
    final zoom = next.clamp(PlannerTimeline.minZoom, PlannerTimeline.maxZoom);
    if (zoom != widget.zoom) widget.onZoom?.call(zoom.toDouble());
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _pinching) {
      setState(() {
        _pinchDistance = null;
        _zoomFocus = null;
      });
    }
  }

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
    if (oldWidget.zoom != widget.zoom) {
      if (_scroll.hasClients) {
        final viewport = _scroll.position.viewportDimension;
        final focus = (_zoomFocus ?? viewport / 2).clamp(0.0, viewport);
        final anchor = _locate(_scroll.offset + focus);
        _layouts.clear();
        final target =
            _offsetForDay(anchor.$1) +
            _dayHeader +
            _layout(anchor.$1).yForMinute(anchor.$2) -
            focus;
        // Corrected before this frame's layout, so the time under the
        // fingers (or mid-view) stays put with no corrective jump.
        _scroll.position.correctPixels(math.max(0, target));
      } else {
        _layouts.clear();
      }
    }
    if (oldWidget.controller != widget.controller) {
      _occurrences.clear();
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  /// A day's occurrences do not depend on zoom; caching them separately
  /// means a pinch only recomputes geometry.
  final _occurrences = <String, List<PlannerOccurrence>>{};

  List<PlannerOccurrence> _dayOccurrences(DateTime day) =>
      _occurrences.putIfAbsent(
        plannerDateKey(day),
        () => widget.controller
            .occurrences(day)
            .where((o) => widget.showChallenges || !o.isChallenge)
            .where(
              (o) =>
                  widget.banner == null ||
                  !(o.isChallenge &&
                      o.start == null &&
                      plannerDateKey(day) ==
                          plannerDateKey(widget.controller.now)),
            )
            .toList(),
      );

  PlannerDayLayout _layout(DateTime day) => _layouts.putIfAbsent(
    plannerDateKey(day),
    () => PlannerDayLayout(
      day,
      _dayOccurrences(day),
      textScale: _scale,
      zoom: widget.zoom,
    ),
  );

  /// Height of one day in the list; also the list's item extent, so list
  /// positions and these offsets can never disagree.
  double _dayExtent(DateTime day) =>
      _dayHeader + _layout(day).height + _extra(day) + _dayBottom;
  double _extra(DateTime day) =>
      _layout(day).unscheduled.length * 96 * math.max(1, _scale);
  double _offsetForDay(DateTime day) {
    final index = plannerDayDistance(_first, day).clamp(0, _count - 1);
    var value = 0.0;
    for (var i = 0; i < index; i++) {
      value += _dayExtent(plannerAddDays(_first, i));
    }
    return value;
  }

  (DateTime, double) _anchor() =>
      _locate(_scroll.hasClients ? _scroll.offset : 0.0);

  /// The day and minute at [offset] in the scrolling content.
  (DateTime, double) _locate(double offset) {
    var remaining = offset;
    for (var i = 0; i < _count; i++) {
      final day = plannerAddDays(_first, i);
      final layout = _layout(day);
      final height = _dayExtent(day);
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
    _occurrences.clear();
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
      ?widget.banner,
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: _pointerUp,
                onPointerCancel: _pointerUp,
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
                      physics: _pinching
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                      slivers: [
                        // Each day's extent is known up front, so the list
                        // places days from these heights. It never reuses
                        // stale positions when zoom changes every height.
                        SliverVariedExtentList(
                          itemExtentBuilder: (index, _) => index < _count
                              ? _dayExtent(plannerAddDays(_first, index))
                              : null,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final day = plannerAddDays(_first, index);
                              return Column(
                                key: ValueKey(
                                  'timeline-day-${plannerDateKey(day)}',
                                ),
                                children: [
                                  _TimelineDay(
                                    layout: _layout(day),
                                    headerHeight: _dayHeader,
                                    now: _clock,
                                    onOpen: widget.onOpen,
                                    onAdd: widget.onAdd,
                                    alternate: index.isEven,
                                    zoom: widget.zoom,
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
                              return index >= 0 && index < _count
                                  ? index
                                  : null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onZoom case final onZoom?)
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: _ZoomControls(zoom: widget.zoom, onZoom: onZoom),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Compact − / + pill floating over the timeline.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.zoom, required this.onZoom});
  final double zoom;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    const steps = PlannerTimeline.zoomSteps;
    final lower = steps.lastWhere((z) => z < zoom - .01, orElse: () => zoom);
    final higher = steps.firstWhere((z) => z > zoom + .01, orElse: () => zoom);
    return Material(
      color: context.colors.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('timeline-zoom-out'),
            tooltip: context.plannerText('zoomOut'),
            onPressed: lower < zoom ? () => onZoom(lower) : null,
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          IconButton(
            key: const ValueKey('timeline-zoom-in'),
            tooltip: context.plannerText('zoomIn'),
            onPressed: higher > zoom ? () => onZoom(higher) : null,
            icon: const Icon(Icons.zoom_in_rounded),
          ),
        ],
      ),
    );
  }
}

class _TimelineDay extends StatelessWidget {
  const _TimelineDay({
    required this.layout,
    required this.headerHeight,
    required this.now,
    required this.onOpen,
    required this.onAdd,
    required this.alternate,
    this.zoom = 1,
  });
  final PlannerDayLayout layout;
  final double headerHeight;
  final ValueListenable<DateTime> now;
  final ValueChanged<PlannerOccurrence> onOpen;
  final ValueChanged<DateTime> onAdd;
  final bool alternate;
  final double zoom;

  /// Minutes between labelled grid lines, chosen so labels stay about
  /// 20 px or more apart: every 2 h zoomed out, down to every 5 min at 6.5x.
  int get _gridStep => zoom >= 6.5
      ? 5
      : zoom >= 4
      ? 10
      : zoom >= 2.5
      ? 15
      : zoom >= 1.5
      ? 30
      : zoom >= .8
      ? 60
      : 120;

  static String _clockLabel(BuildContext context, int minute) {
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String two(int n) =>
        plannerNumber(context, n).padLeft(2, arabic ? '٠' : '0');
    return '${two(minute ~/ 60 % 24)}:${two(minute % 60)}';
  }

  /// Narrower lanes make overlapping routines unreadable, so a busy day's
  /// routines scroll sideways instead of being squeezed or collapsed.
  static const _minLaneWidth = 150.0;

  double _laneMin(double scale) => _minLaneWidth * math.min(scale, 1.5);

  /// Width of the day's routine canvas: the visible width, or wider when an
  /// overlap needs more lanes than fit.
  double _canvasWidth(double available, double scale) {
    var widest = available;
    for (final event in layout.events) {
      widest = math.max(widest, event.laneCount * _laneMin(scale));
    }
    return widest;
  }

  /// Routine blocks positioned on the canvas. Overlap groups that fit share
  /// the visible width; larger groups use fixed-width lanes off-screen.
  List<Widget> _events(double available, double scale) => [
    for (final event in layout.events)
      () {
        final lanes = event.laneCount;
        final lane = lanes * _laneMin(scale) <= available
            ? available / lanes
            : _laneMin(scale);
        return PositionedDirectional(
          key: ValueKey(
            'timeline-event-${event.occurrence.id}-${plannerDateKey(layout.day)}',
          ),
          start: event.lane * lane,
          width: lane - 5,
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
        );
      }(),
  ];

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
                    for (
                      var minute = 0;
                      minute <= 1440;
                      minute += _gridStep
                    ) ...[
                      PositionedDirectional(
                        start: 5,
                        top: (layout.yForMinute(minute) - 9).clamp(
                          0,
                          layout.height - 20,
                        ),
                        width: gutter - 20,
                        child: ExcludeSemantics(
                          child: Text(
                            _clockLabel(context, minute),
                            maxLines: 1,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: minute % 60 == 0
                                      ? context.tokens.muted
                                      : context.tokens.muted.withValues(
                                          alpha: .6,
                                        ),
                                ),
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: gutter - 8,
                        end: 16,
                        top: layout.yForMinute(minute),
                        child: Divider(
                          height: 1,
                          thickness: .5,
                          color: context.colors.outlineVariant.withValues(
                            alpha: minute % 60 == 0 ? .25 : .12,
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
                    PositionedDirectional(
                      start: gutter,
                      end: 16,
                      top: 0,
                      bottom: 0,
                      child: SingleChildScrollView(
                        // Its own storage slot: without one it shares the
                        // vertical list's saved offset and opens scrolled.
                        key: PageStorageKey(
                          'timeline-lanes-${plannerDateKey(layout.day)}',
                        ),
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _canvasWidth(available, scale),
                          height: layout.height,
                          child: Stack(children: _events(available, scale)),
                        ),
                      ),
                    ),
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
