import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/startup_failure.dart';
import 'package:streak/app/streak_app.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/utils/app_dirs.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/state/focus_actions.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/focus/widgets/focus_pill.dart';
import 'package:streak/features/habits/pages/habit_details_page.dart';
import 'package:streak/features/habits/pages/health_info_page.dart';
import 'package:streak/features/habits/state/categories_controller.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/habits/widgets/day_actions_sheet.dart';
import 'package:streak/features/island/state/island_controller.dart';
import 'package:streak/features/habits/state/notes_controller.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/statistics/pages/statistics_page.dart';
import 'package:streak/features/todos/pages/todos_page.dart';
import 'package:streak/features/todos/state/todo_tags_controller.dart';
import 'package:streak/features/todos/state/todos_controller.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/pages/planner_task_page.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/core/utils/app_snackbar.dart';
import 'package:streak/services/planner_sync.dart';
import 'package:streak/services/planner_background.dart';
import 'package:streak/services/planner_repository.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_session_store.dart';
import 'package:streak/services/cloud_sync_controller.dart';
import 'package:streak/services/native_cloud_planner_cache.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:streak/services/focus_service.dart';
import 'package:streak/services/folder_sync.dart';
import 'package:streak/services/home_widget_service.dart';
import 'package:streak/services/image_cleanup_service.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/portable_traces.dart';
import 'package:streak/services/todos_widget_service.dart';
import 'package:streak/services/widget_action_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _startup();
  } catch (e, s) {
    debugPrint('Streak could not start: $e');
    debugPrintStack(stackTrace: s);
    runApp(
      StartupFailure(
        error: '$e',
        logPath: _writeStartupLog(e, s),
        blocked: _blockedByWindows(e),
      ),
    );
    return;
  }
  _run();
}

Future<AppExitResponse> _leaveNoTrace() async {
  try {
    await NotificationService().cancelAll();
    await PortableTraces.clear(NotificationService.windowsAppId);
  } catch (e) {
    debugPrint('Could not clear what the portable app left: $e');
  }
  return AppExitResponse.exit;
}

bool _blockedByWindows(Object error) =>
    Platform.isWindows &&
    error is FileSystemException &&
    error.osError?.errorCode == 5;

String? _writeStartupLog(Object error, StackTrace stack) {
  if (isMobile) return null;
  try {
    final file = File('${Directory.systemTemp.path}/streak_startup_error.txt');
    file.writeAsStringSync('${DateTime.now()}\n$error\n\n$stack');
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> _startup() async {
  if (isMobile) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  await initializeDateFormatting();
  await LocalStore.init();
  // Check secure identity before a folder import or any provider can expose
  // another account's previous native/Hive cache.
  final savedSession = await _cloudSessions.read();
  await _cloudCache.guardSession(savedSession?.ownerId);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Cairo'],
      await rootBundle.loadString('fonts/Cairo/OFL.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      ['Level Up — Based on Streak by InlitX'],
      await rootBundle.loadString('LICENSE'),
    );
    yield LicenseEntryWithLineBreaks(
      ['Streak — Copyright (C) 2026 InlitX'],
      await rootBundle.loadString('ADDITIONAL_TERMS.md'),
    );
  });
  AppClock.cutoffHour = LocalStore.setting('dayCutoff', 0);
  await WidgetActionService.drain(
    LocalStore.readHabits(),
    todos: LocalStore.readTodos(),
  );
  await FolderSync.pull();
  // Validate/migrate once, or recover the Hive backup mirror from Android's
  // authoritative AtomicFile before creating any planner controller.
  await PlannerRepository().initialize();
  unawaited(ImageCleanupService.run());

  NotificationService.onOpenHabit = _openHabit;
  NotificationService.onOpenTodos = _openTodos;
  NotificationService.onOpenPlanner = _openPlanner;
  NotificationService.onHabitsChanged = _reloadHabits;
  NotificationService.onTodosChanged = _reloadTodos;
  FocusService.onPending = drainFocusActions;
  FocusService.listen();
  try {
    await NotificationService().initialize();
  } catch (e, s) {
    debugPrint('Startup init (notifications/widget) failed: $e\n$s');
  }
  if (isPortable) AppLifecycleListener(onExitRequested: _leaveNoTrace);

  _appChannel.setMethodCallHandler((call) async {
    if (call.method == 'openHabit') {
      final id = call.arguments as String?;
      if (id != null) _openHabit(id);
    }
    if (call.method == 'startFocus') {
      final id = call.arguments as String?;
      if (id != null) _startFocus(id);
    }
    if (call.method == 'openPage') {
      final page = call.arguments as String?;
      if (page != null) _openPage(page);
    }
    return null;
  });

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await drainFocusActions();
    final pending = NotificationService().pendingHabitId;
    if (pending != null) {
      NotificationService().pendingHabitId = null;
      NotificationService.openFromPayload(pending);
    }
    if (isMobile) {
      final launched = await _appChannel.invokeMethod<String>(
        'consumeLaunchHabit',
      );
      if (launched != null) _openHabit(launched);
      final focusOn = await _appChannel.invokeMethod<String>(
        'consumeLaunchFocus',
      );
      if (focusOn != null) _startFocus(focusOn);
      final page = await _appChannel.invokeMethod<String>('consumeLaunchPage');
      if (page != null) _openPage(page);
    }
  });
}

void _run() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(
          lazy: false,
          create: (context) {
            final settings = context.read<SettingsController>();
            late final PlannerController controller;
            final repository = PlannerRepository();
            controller = PlannerController(
              loadLatest: repository.loadLatest,
              transaction: repository.transaction,
              persist: repository.save,
              afterCommit: () async {
                await reschedulePlannerReminders(controller);
                await settings.runAutoBackup();
                unawaited(_cloud?.synchronize());
              },
            );
            return controller;
          },
        ),
        ChangeNotifierProvider<CloudSyncController>(
          lazy: false,
          create: (context) {
            final cloud = CloudSyncController(
              api: CloudHttpApi(),
              cache: _cloudCache,
              sessionStore: _cloudSessions,
              exportDraft: _cloudCache.exportDraft,
              onApplied: _reloadAccountCaches,
            );
            _cloud = cloud;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(cloud.initialize());
            });
            return cloud;
          },
        ),
        ChangeNotifierProvider(create: (_) => CategoriesController()),
        ChangeNotifierProvider(create: (_) => TodoTagsController()),
        ChangeNotifierProvider(create: (_) => NotesController()),
        ChangeNotifierProvider(
          create: (_) {
            final controller = TodosController();
            TodosWidgetService.sync(controller.all);
            return controller;
          },
        ),
        ChangeNotifierProvider(create: (_) => FocusController()),
        ChangeNotifierProvider(create: (_) => IslandController()),
        ChangeNotifierProvider(
          create: (_) {
            final controller = HabitsController();
            HomeWidgetService.sync(controller.asMap);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => controller.rescheduleReminders(),
            );
            return controller;
          },
        ),
      ],
      child: const StreakApp(),
    ),
  );
}

const _appChannel = MethodChannel('streak/app_icon');

final _cloudSessions = CloudSecureSessionStore();
CloudSyncController? _cloud;
final _cloudCache = NativeCloudPlannerCache(
  archives: CloudSecureArchiveStore(),
  timeZone: () async => (await FlutterTimezone.getLocalTimezone()).identifier,
  beforeIsolation: () async {
    final context = AppNavigator.key.currentContext;
    if (context != null) {
      final focus = context.read<FocusController>();
      if (focus.isActive) await focus.stop(completed: false);
    }
    await FocusService.hide();
    HomeWidgetService.cancelPendingSync();
    TodosWidgetService.cancelPendingSync();
  },
  cancelNotifications: () => NotificationService().cancelAll(),
);

Future<void> _reloadAccountCaches() async {
  final context = AppNavigator.key.currentContext;
  if (context == null) return;
  await context.read<SettingsController>().reloadFromStore();
  if (!context.mounted) return;
  await context.read<HabitsController>().reload();
  if (!context.mounted) return;
  context.read<CategoriesController>().reload();
  context.read<TodoTagsController>().reload();
  context.read<NotesController>().reload();
  context.read<TodosController>().reload();
  context.read<FocusController>().reload();
  context.read<IslandController>().reload();
  HomeWidgetService.sync(context.read<HabitsController>().asMap);
  TodosWidgetService.sync(context.read<TodosController>().all);
  await context.read<PlannerController>().reload();
  if (!context.mounted) return;
  await reschedulePlannerReminders(context.read<PlannerController>());
}

void _openHabit(String habitId) {
  AppNavigator.push(HabitDetailsPage(habitId: habitId), fade: true);
}

void _reloadHabits() {
  AppNavigator.key.currentContext?.read<HabitsController>().reload();
}

void _reloadTodos() {
  AppNavigator.key.currentContext?.read<TodosController>().reload();
}

Future<void> _openPlanner(String occurrenceId, String? actionId) async {
  final context = AppNavigator.key.currentContext;
  if (context == null) return;
  final controller = context.read<PlannerController>();
  try {
    await controller.evaluate();
  } catch (error) {
    if (context.mounted) {
      AppSnackbar.error(context, plannerError(context, error));
    }
    return;
  }
  final occurrence = controller.occurrenceById(occurrenceId);
  if (occurrence == null || !context.mounted) return;
  if (actionId == NotificationService.actionPlannerSnooze) {
    try {
      final snoozed = await snoozePlannerReminder(controller, occurrenceId);
      if (context.mounted) {
        if (snoozed) {
          AppSnackbar.success(context, context.plannerText('reminderSnoozed'));
        } else {
          AppSnackbar.info(
            context,
            context.plannerText('reminderUnavailable'),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        AppSnackbar.error(context, plannerError(context, error));
      }
    }
    return;
  }
  if (actionId == NotificationService.actionPlannerDone) {
    try {
      await controller.complete(occurrenceId);
      if (context.mounted) {
        AppSnackbar.success(context, context.plannerText('taskCompleted'));
      }
      return;
    } catch (error) {
      if (context.mounted) {
        AppSnackbar.info(context, plannerError(context, error));
      }
    }
  }
  AppNavigator.push(PlannerTaskPage(occurrence: occurrence), fade: true);
}

void _openTodos([String? todoId]) {
  AppNavigator.push(TodosPage(openId: todoId), fade: true);
}

void _openPage(String page) {
  if (page == 'todos') _openTodos();
  if (page == 'stats') AppNavigator.push(const StatisticsPage(), fade: true);
  if (page == 'focus') _openFocus();
  if (page == 'focusPage') _openFocusHome();
  if (page == 'focusStart') _startFreeFocus();
  if (page.startsWith('focusStart:')) _startFocus(page.substring(11));
  if (page == 'health') AppNavigator.push(const HealthInfoPage(), fade: true);
  if (page.startsWith('day:')) _openDay(page.substring(4));
}

void _openDay(String target) {
  final split = target.lastIndexOf(':');
  final context = AppNavigator.key.currentContext;
  if (split <= 0 || context == null) return;
  final habit = context.read<HabitsController>().byId(
    target.substring(0, split),
  );
  if (habit == null) return;
  showDayActionsSheet(
    context,
    habit: habit,
    date: parseDayKey(target.substring(split + 1)),
    notesEnabled: context.read<SettingsController>().notesEnabled,
  );
}

void _openFocusHome() {
  final context = AppNavigator.key.currentContext;
  if (context == null || AppNavigator.isShowing(FocusPage.routeName)) return;
  openFocus(context);
}

void _openFocus() {
  final context = AppNavigator.key.currentContext;
  if (context == null || !context.read<FocusController>().isActive) return;
  if (AppNavigator.isShowing(FocusPage.routeName)) return;
  AppNavigator.push(const FocusPage(), fade: true, name: FocusPage.routeName);
}

void _startFreeFocus() {
  final context = AppNavigator.key.currentContext;
  if (context == null || AppNavigator.isShowing(FocusPage.routeName)) return;
  final settings = context.read<SettingsController>();
  AppNavigator.push(
    context.read<FocusController>().isActive
        ? const FocusPage()
        : FocusPage(
            startMinutes: settings.focusMinutes,
            breakMinutes: settings.focusBreakMinutes,
          ),
    fade: true,
    name: FocusPage.routeName,
  );
}

void _startFocus(String habitId) {
  final context = AppNavigator.key.currentContext;
  if (context == null) return;
  if (AppNavigator.isShowing(FocusPage.routeName)) return;
  if (context.read<FocusController>().isActive) {
    AppNavigator.push(const FocusPage(), fade: true, name: FocusPage.routeName);
    return;
  }
  final habit = context.read<HabitsController>().byId(habitId);
  if (habit == null) return;
  AppNavigator.push(
    FocusPage(
      startHabitId: habit.id,
      startMinutes: habit.focusMinutes,
      breakMinutes: habit.focusBreakMinutes,
    ),
    fade: true,
    name: FocusPage.routeName,
  );
}

@pragma('vm:entry-point')
Future<void> widgetActionEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('streak/widget_action');
  try {
    await initializeDateFormatting();
    await LocalStore.init();
    AppClock.cutoffHour = LocalStore.setting('dayCutoff', 0);
    await LocalStore.reloadHabits();
    final habits = LocalStore.readHabits();
    final todos = LocalStore.readTodos();
    await WidgetActionService.drain(habits, todos: todos);
    await HomeWidgetService.sync(habits, renderIcons: false);
    await TodosWidgetService.sync(todos);
    await NotificationService().rescheduleTodos(todos);
  } catch (e) {
    debugPrint('Widget action entrypoint failed: $e');
  }
  await channel.invokeMethod('done');
}

@pragma('vm:entry-point')
Future<void> plannerReminderEntrypoint() async {
  await runPlannerBackgroundRefresh();
}
