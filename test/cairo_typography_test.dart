import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/features/planner/pages/planner_editor_page.dart';
import 'package:streak/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final name in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      loader.addFont(rootBundle.load('fonts/Cairo/Cairo-$name.ttf'));
    }
    await loader.load();
  });

  test('bundled Cairo faces have real weight classes and shaping tables', () {
    for (final entry in {
      400: 'Regular',
      500: 'Medium',
      600: 'SemiBold',
      700: 'Bold',
      800: 'ExtraBold',
      900: 'Black',
    }.entries) {
      final bytes = File(
        'fonts/Cairo/Cairo-${entry.value}.ttf',
      ).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      final tables = <String, int>{};
      for (var n = 0; n < data.getUint16(4); n++) {
        final record = 12 + n * 16;
        tables[String.fromCharCodes(bytes.sublist(record, record + 4))] = data
            .getUint32(record + 8);
      }
      expect(data.getUint16(tables['OS/2']! + 4), entry.key);
      expect(tables.keys, containsAll(['GSUB', 'GPOS', 'cmap']));
      expect(
        tables.keys,
        isNot(contains('fvar')),
        reason: 'Declared weight is an actual static instance',
      );
    }
    expect(
      File('fonts/Cairo/OFL.txt').readAsStringSync(),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
  });

  test(
    'Arabic changes font while preserving style identity and actual weights',
    () {
      for (var style = 0; style <= 2; style++) {
        final base = AppTheme.dark(null, style);
        final ar = AppTypography.forLocale(base, const Locale('ar'));
        final en = AppTypography.forLocale(base, const Locale('en'));
        expect(ar.textTheme.bodyMedium!.fontFamily, 'Cairo');
        expect(ar.textTheme.titleLarge!.fontFamily, 'Cairo');
        expect(ar.primaryTextTheme.labelLarge!.fontFamily, 'Cairo');
        expect(ar.appBarTheme.titleTextStyle!.fontFamily, 'Cairo');
        expect(ar.dialogTheme.titleTextStyle!.fontFamily, 'Cairo');
        expect(
          AppTypography.originalFamily(ar),
          base.textTheme.bodyMedium!.fontFamily,
        );
        expect(
          en.textTheme.bodyMedium!.fontFamily,
          base.textTheme.bodyMedium!.fontFamily,
        );
        expect(en.textTheme.bodyMedium!.fontFamilyFallback, contains('Cairo'));
        expect(ar.colorScheme, base.colorScheme);
        if (style == 2) {
          expect(ar.textTheme.headlineLarge!.fontWeight, FontWeight.w700);
          expect(ar.textTheme.headlineLarge!.fontVariations, isEmpty);
          for (final button in [
            ar.filledButtonTheme.style,
            ar.outlinedButtonTheme.style,
            ar.textButtonTheme.style,
          ]) {
            expect(button!.textStyle!.resolve({})!.fontFamily, 'Cairo');
            expect(button.textStyle!.resolve({})!.fontWeight, FontWeight.w800);
          }
        }
      }
    },
  );

  testWidgets('Cairo applies to Arabic routes, controls, dialogs and menus', (
    tester,
  ) async {
    final locale = ValueNotifier(const Locale('ar'));
    final input = TextEditingController(text: 'جامعة ABC ١٢:٣٠');
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: locale,
        builder: (_, value, __) => MaterialApp(
          locale: value,
          theme: AppTheme.dark(null, 2),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Theme(
            data: AppTypography.forLocale(
              Theme.of(context),
              Localizations.localeOf(context),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('عنوان عربي')),
              body: Column(
                children: [
                  TextField(
                    controller: input,
                    decoration: const InputDecoration(labelText: 'نشاط'),
                  ),
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('عنوان الحوار'),
                        content: const Text('نص الحوار'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('حفظ'),
                  ),
                  PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(TextField))),
      TextDirection.rtl,
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.fontFamily,
      'Cairo',
    );
    final title = tester.renderObject<RenderParagraph>(find.text('عنوان عربي'));
    expect(title.text.style!.fontFamily, 'Cairo');
    final save = tester.renderObject<RenderParagraph>(find.text('حفظ'));
    expect(save.text.style!.fontFamily, 'Cairo');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('عنوان الحوار'))
          .text
          .style!
          .fontFamily,
      'Cairo',
    );
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('تعديل'))
          .text
          .style!
          .fontFamily,
      'Cairo',
    );
    Navigator.of(tester.element(find.text('تعديل'))).pop();
    await tester.pumpAndSettle();
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(TextField))),
      TextDirection.ltr,
    );
    expect(input.text, 'جامعة ABC ١٢:٣٠');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.fontFamily,
      'GoogleSansFlex',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
    input.dispose();
  });

  testWidgets(
    'editor preview represents duration and remains readable in narrow RTL',
    (tester) async {
      Widget preview(
        int start,
        int end, {
        bool overnight = false,
        double scale = 1,
      }) => MaterialApp(
        locale: const Locale('ar'),
        theme: AppTypography.forLocale(AppTheme.dark(), const Locale('ar')),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ActivityTimelinePreview(
                startMinute: start,
                endMinute: end,
                overnight: overnight,
                title: 'جامعة ABC',
              ),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(preview(540, 570));
      await tester.pumpAndSettle();
      final short = tester
          .getSize(find.byKey(const ValueKey('activity-preview-event')))
          .height;
      await tester.pumpWidget(preview(540, 660));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('activity-preview-event')))
            .height,
        greaterThan(short),
      );
      await tester.pumpWidget(preview(23 * 60, 60, overnight: true, scale: 2));
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(ActivityTimelinePreview))),
        TextDirection.rtl,
      );
      expect(find.text('١٢٠ دقيقة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
