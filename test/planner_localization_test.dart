import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/core/i18n/app_locale.dart';
import 'package:streak/features/planner/data/planner_models.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/pages/planner_editor_page.dart';
import 'package:streak/features/planner/state/planner_controller.dart';
import 'package:streak/features/planner/widgets/planner_reminder_editor.dart';
import 'package:streak/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arabic covers every English application message', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    final ar =
        jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync()) as Map;
    final keys = en.keys.where((key) => !(key as String).startsWith('@'));
    expect(keys.where((key) => ar[key] == null || ar[key] == ''), isEmpty);
    expect(shippedLocales, contains(const Locale('ar')));
    expect(pickLocale(const [Locale('ar', 'SA')]), const Locale('ar'));
  });

  test('Arabic and Persian keyboard numbers parse without changing units', () {
    expect(plannerParseNumber('١٢٫٥'), 12.5);
    expect(plannerParseNumber('۲۵'), 25);
    expect(plannerParseNumber('١٬٢٣٤'), 1234);
    expect(plannerParseNumber('12,5'), 12.5);
    expect(plannerParseNumber('letters'), isNull);
    expect(plannerTextForLocale('ar', 'notificationSnooze'), 'تأجيل ١٠ دقائق');
  });

  test('task counts use English and Arabic plurals with localized numbers', () {
    const examples = {
      'en': {'1': '1 task', '2': '2 tasks', '1,000': '1,000 tasks'},
      'ar': {
        '٠': 'لا مهام',
        '١': 'مهمة واحدة',
        '٢': 'مهمتان',
        '۳': '٣ مهام',
        '١١': '١١ مهمة',
        '١٠٠': '١٠٠ مهمة',
        '١٬٠٠٠': '١٬٠٠٠ مهمة',
      },
    };
    for (final locale in examples.entries) {
      final xp = locale.key == 'ar' ? '٨٠' : '80';
      for (final example in locale.value.entries) {
        final args = {'count': example.key, 'xp': xp};
        for (final key in ['groupChildren', 'packageTaskCount']) {
          expect(plannerTextForLocale(locale.key, key, args), example.value);
        }
        expect(
          plannerTextForLocale(locale.key, 'packageSummaryShort', args),
          '${example.value} · $xp ${locale.key == 'ar' ? 'نقطة خبرة' : 'XP'}',
        );
      }
    }
  });

  testWidgets('switching language keeps current form and domain state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final day = DateTime(2026, 10, 29);
    final controller = PlannerController(
      initial: {},
      persist: (_) async {},
      clock: () => day,
    );
    await controller.saveItem(
      PlannerItem(
        id: 'university',
        title: 'جامعة ABC',
        date: day,
        startMinute: 480,
        endMinute: 840,
        recurrence: PlannerRecurrence.weekdays,
        weekdays: const [1, 2, 3, 4],
      ),
    );
    final before = controller.exportState;
    final locale = ValueNotifier(const Locale('en'));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, value, __) => MaterialApp(
            locale: value,
            theme: AppTheme.dark(),
            builder: (context, child) => Theme(
              data: AppTypography.forLocale(
                Theme.of(context),
                Localizations.localeOf(context),
              ),
              child: child!,
            ),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: PlannerEditorPage(item: controller.items.single),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'جامعة ABC — تعديل',
    );
    locale.value = const Locale('ar');
    await tester.pumpAndSettle();
    expect(find.text('تعديل النشاط'), findsOneWidget);
    expect(find.text('العنوان'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'جامعة ABC — تعديل',
    );
    expect(
      Directionality.of(tester.element(find.byType(PlannerEditorPage))),
      TextDirection.rtl,
    );
    expect(
      plannerNumber(tester.element(find.byType(PlannerEditorPage)), 12),
      '١٢',
    );
    expect(controller.exportState, before);
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Edit activity'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'جامعة ABC — تعديل',
    );
    expect(
      Directionality.of(tester.element(find.byType(PlannerEditorPage))),
      TextDirection.ltr,
    );
    expect(controller.exportState, before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
    controller.dispose();
  });

  testWidgets('Arabic reminder dialog and time picker inherit RTL', (
    tester,
  ) async {
    final day = DateTime(2026, 10, 29);
    final occurrence = PlannerOccurrence(
      id: 'routine@2026-10-29',
      day: day,
      item: PlannerItem(
        id: 'routine',
        title: 'النشاط',
        date: day,
        reminder: const PlannerReminder(enabled: true, minute: 600),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.dark(),
        builder: (context, child) => Theme(
          data: AppTypography.forLocale(
            Theme.of(context),
            Localizations.localeOf(context),
          ),
          child: child!,
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editPlannerReminder(context, occurrence),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('تذكير المهمة'), findsOneWidget);
    expect(find.text('حفظ التذكير'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AlertDialog))),
      TextDirection.rtl,
    );
    await tester.tap(find.text('وقت التذكير'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(TimePickerDialog))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
