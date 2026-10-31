// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_widgets.dart';

/// Publishes the schedule and challenges for the two Android home-screen
/// widgets (ScheduleWidget and ChallengesWidget), which share one payload.
///
/// The planner's recurrence, override and challenge rules live in Dart, so the
/// app computes the next week's occurrences here (already localised) and the
/// native widget only draws them. A week of days keeps the widget correct
/// after midnight even when the app has not been opened.
abstract final class ScheduleWidgetService {
  static const dataKey = 'levelup_schedule';
  static const providers = [
    'com.streak.app.ScheduleWidgetProvider',
    'com.streak.app.ChallengesWidgetProvider',
  ];
  static const days = 7;
  static Timer? _pending;

  static Map<String, dynamic> payload(
    BuildContext context,
    PlannerController planner,
  ) {
    final today = plannerDay(planner.now);
    final tomorrow = plannerAddDays(today, 1);
    final selection = planner.selectionFor(tomorrow);
    final chosen = planner.instances
        .where((i) => i.id == selection?.instanceId)
        .firstOrNull;
    Map<String, dynamic> item(PlannerOccurrence o) => {
      'title': plannerOccurrenceTitle(context, o),
      'done': o.record.status == CompletionStatus.completed,
      'skipped': o.record.status == CompletionStatus.skipped,
      'challenge': o.isChallenge,
      'category': o.item.category,
    };
    return {
      'version': 1,
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'empty': context.plannerText('emptyTimeline'),
      'anytimeLabel': context.plannerText('anytimeToday'),
      'challengeTitle': context.plannerText('todaysChallenge'),
      'noChallenge': context.plannerText('noChallenge'),
      // Only meaningful on [tomorrowFor]; the widget hides it on other days.
      'tomorrowFor': plannerDateKey(today),
      'tomorrowLabel': chosen != null
          ? '${context.plannerText('selectedForTomorrow')}: ${plannerTemplateName(context, chosen.snapshot)}'
          : context.plannerText(
              selection?.isMissed == true
                  ? 'selectionMissed'
                  : 'chooseTomorrow',
            ),
      'days': [
        for (var i = 0; i < days; i++)
          () {
            final day = plannerAddDays(today, i);
            final occurrences = planner.occurrences(day);
            final timed = occurrences.where((o) => o.start != null).toList()
              ..sort((a, b) => a.start!.compareTo(b.start!));
            return {
              'key': plannerDateKey(day),
              'title': plannerLocalDate(context, day, compact: true),
              'items': [
                for (final o in timed)
                  {
                    ...item(o),
                    'time': plannerInterval(o, context: context),
                    // Minutes from this day's midnight; overnight ends pass 1440.
                    'start': o.start!.difference(day).inMinutes,
                    'end': o.end!.difference(day).inMinutes,
                  },
              ],
              'anytime': [
                for (final o in occurrences.where((o) => o.start == null))
                  item(o),
              ],
              // Packages with tasks on this day, with that day's progress.
              'challenges': [
                for (final instance in planner.instances)
                  if (occurrences.any((o) => o.challengeId == instance.id))
                    () {
                      final tasks =
                          occurrences
                              .where((o) => o.challengeId == instance.id)
                              .toList()
                            // Timed tasks in time order, then anytime tasks.
                            ..sort((a, b) {
                              if (a.start == null || b.start == null) {
                                return (a.start == null ? 1 : 0) -
                                    (b.start == null ? 1 : 0);
                              }
                              return a.start!.compareTo(b.start!);
                            });
                      return {
                        'name': plannerTemplateName(context, instance.snapshot),
                        'done': tasks
                            .where(
                              (o) =>
                                  o.record.status == CompletionStatus.completed,
                            )
                            .length,
                        'total': tasks.length,
                        'tasks': [
                          for (final o in tasks)
                            {
                              ...item(o),
                              if (o.start != null)
                                'time': plannerInterval(o, context: context),
                            },
                        ],
                      };
                    }(),
              ],
            };
          }(),
      ],
    };
  }

  /// Debounced so a burst of edits publishes once. Android only.
  static void publish(BuildContext context, PlannerController planner) {
    if (!Platform.isAndroid) return;
    final data = jsonEncode(payload(context, planner));
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 600), () async {
      try {
        await HomeWidget.saveWidgetData<String>(dataKey, data);
        for (final provider in providers) {
          await HomeWidget.updateWidget(qualifiedAndroidName: provider);
        }
      } catch (_) {
        // A missing widget host or plugin must never affect the planner.
      }
    });
  }
}
