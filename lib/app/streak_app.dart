import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/i18n/app_locale.dart';
import 'package:streak/app/app_background.dart';
import 'package:streak/app/app_lock.dart';
import 'package:streak/features/planner/pages/level_up_shell.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/services/home_widget_service.dart';

class StreakApp extends StatelessWidget {
  const StreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: 'Level Up',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppNavigator.key,
      theme: AppTheme.light(
        settings.accentColor,
        settings.appStyle,
        settings.colorTheme,
      ),
      darkTheme: AppTheme.dark(
        settings.accentColor,
        settings.appStyle,
        settings.colorTheme,
      ),
      themeMode: settings.themeMode,
      builder: (context, child) {
        HomeWidgetService.localize(
          AppLocalizations.of(context),
          () => context.read<HabitsController>().asMap,
        );
        final media = MediaQuery.of(context);
        final typography = AppTypography.forLocale(
          Theme.of(context),
          Localizations.localeOf(context),
        );
        return Theme(
          data: typography,
          child: DefaultTextStyle(
            style: typography.textTheme.bodyMedium!,
            child: MediaQuery(
              data: settings.animations
                  ? media
                  : media.copyWith(disableAnimations: true),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppTheme.systemBars(Theme.of(context).brightness),
                child: AppLockGate(
                  child: AppBackground(
                    // The app draws edge-to-edge; keep every page (and its
                    // sheets) clear of the system navigation buttons while
                    // the background still fills behind them.
                    child: SafeArea(
                      top: false,
                      left: false,
                      right: false,
                      child: _DesktopFrame(
                        shell: true,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      locale: settings.locale,
      supportedLocales: shippedLocales,
      localeListResolutionCallback: (wanted, _) => pickLocale(wanted),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LevelUpShell(),
    );
  }
}

class _DesktopFrame extends StatelessWidget {
  const _DesktopFrame({required this.shell, required this.child});

  final bool shell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || (shell && hasSideRail(context))) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: phoneWidth),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
