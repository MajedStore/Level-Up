import 'package:flutter/material.dart';

/// Keep the user's theme style independent of the alphabet used to render it.
@immutable
class AppTypographyOrigin extends ThemeExtension<AppTypographyOrigin> {
  const AppTypographyOrigin(this.family);
  final String? family;
  @override
  AppTypographyOrigin copyWith({String? family}) =>
      AppTypographyOrigin(family ?? this.family);
  @override
  AppTypographyOrigin lerp(AppTypographyOrigin? other, double t) =>
      t < .5 || other == null ? this : other;
}

class AppTypography {
  const AppTypography._();
  static const arabicFamily = 'Cairo';
  static const arabicFallback = ['Cairo'];

  static String? originalFamily(ThemeData theme) =>
      theme.extension<AppTypographyOrigin>()?.family ??
      theme.textTheme.bodyMedium?.fontFamily;

  /// Applied above the Navigator, including its dialogs and popup overlays.
  /// Latin fonts have no Arabic glyphs, so the inherited fallback also gives
  /// Arabic entered into an English interface the same bundled Cairo family.
  static ThemeData forLocale(ThemeData base, Locale locale) {
    final arabic = locale.languageCode == 'ar';
    TextStyle? style(TextStyle? original) {
      if (original == null) return null;
      final weightAxis = original.fontVariations
          ?.where((v) => v.axis == 'wght')
          .firstOrNull;
      return original.copyWith(
        fontFamily: arabic ? arabicFamily : original.fontFamily,
        fontFamilyFallback: arabicFallback,
        letterSpacing: arabic ? 0 : original.letterSpacing,
        fontVariations: arabic ? const [] : original.fontVariations,
        fontWeight: arabic && weightAxis != null
            ? FontWeight.values[((weightAxis.value / 100).round() - 1).clamp(
                0,
                8,
              )]
            : original.fontWeight,
      );
    }

    TextTheme textTheme(TextTheme original) => TextTheme(
      displayLarge: style(original.displayLarge),
      displayMedium: style(original.displayMedium),
      displaySmall: style(original.displaySmall),
      headlineLarge: style(original.headlineLarge),
      headlineMedium: style(original.headlineMedium),
      headlineSmall: style(original.headlineSmall),
      titleLarge: style(original.titleLarge),
      titleMedium: style(original.titleMedium),
      titleSmall: style(original.titleSmall),
      bodyLarge: style(original.bodyLarge),
      bodyMedium: style(original.bodyMedium),
      bodySmall: style(original.bodySmall),
      labelLarge: style(original.labelLarge),
      labelMedium: style(original.labelMedium),
      labelSmall: style(original.labelSmall),
    );
    ButtonStyle? buttonStyle(ButtonStyle? original) =>
        original?.textStyle == null
        ? original
        : original!.copyWith(
            textStyle: WidgetStateProperty.resolveWith(
              (states) => style(original.textStyle!.resolve(states)),
            ),
          );
    return base.copyWith(
      textTheme: textTheme(base.textTheme),
      primaryTextTheme: textTheme(base.primaryTextTheme),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(base.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(base.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttonStyle(base.textButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle(base.elevatedButtonTheme.style),
      ),
      extensions: [
        ...base.extensions.values.where((e) => e is! AppTypographyOrigin),
        AppTypographyOrigin(originalFamily(base)),
      ],
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: style(base.appBarTheme.titleTextStyle),
        toolbarTextStyle: style(base.appBarTheme.toolbarTextStyle),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        titleTextStyle: style(base.dialogTheme.titleTextStyle),
        contentTextStyle: style(base.dialogTheme.contentTextStyle),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: style(base.inputDecorationTheme.labelStyle),
        floatingLabelStyle: style(base.inputDecorationTheme.floatingLabelStyle),
        hintStyle: style(base.inputDecorationTheme.hintStyle),
        helperStyle: style(base.inputDecorationTheme.helperStyle),
        errorStyle: style(base.inputDecorationTheme.errorStyle),
        counterStyle: style(base.inputDecorationTheme.counterStyle),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: style(base.snackBarTheme.contentTextStyle),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        textStyle: style(base.popupMenuTheme.textStyle),
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        textStyle: style(base.tooltipTheme.textStyle),
      ),
      timePickerTheme: base.timePickerTheme.copyWith(
        hourMinuteTextStyle: style(base.timePickerTheme.hourMinuteTextStyle),
        dayPeriodTextStyle: style(base.timePickerTheme.dayPeriodTextStyle),
        helpTextStyle: style(base.timePickerTheme.helpTextStyle),
      ),
    );
  }
}
