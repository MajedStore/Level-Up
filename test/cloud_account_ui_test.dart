import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_typography.dart';
import 'package:streak/features/planner/l10n/planner_l10n.dart';
import 'package:streak/features/planner/pages/cloud_account_page.dart';
import 'package:streak/l10n/app_localizations.dart';
import 'package:streak/services/cloud_api.dart';
import 'package:streak/services/cloud_models.dart';
import 'package:streak/services/cloud_sync_controller.dart';

import 'cloud_sync_controller_test.dart'
    show
        FakeCloudApi,
        MemoryCloudCache,
        MemorySessions,
        cloudNow,
        cloudSession,
        cloudMutation;

Future<void> _open(
  WidgetTester tester,
  CloudSyncController controller, {
  String locale = 'en',
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      theme: AppTheme.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final theme = AppTypography.forLocale(
          Theme.of(context),
          Localizations.localeOf(context),
        );
        return Theme(
          data: theme,
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!,
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: child!,
            ),
          ),
        );
      },
      home: CloudAccountPage(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('fonts/Cairo/Cairo-$weight.ttf'));
    }
    await loader.load();
  });

  testWidgets(
    'unconfigured account view stays explicit without credential form',
    (tester) async {
      final api = FakeCloudApi()..configured = false;
      final c = CloudSyncController(
        api: api,
        cache: MemoryCloudCache(),
        sessionStore: MemorySessions(),
      );
      await c.initialize();
      await _open(tester, c);
      expect(
        find.text('Cloud sync is not configured for this build.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(api.events, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'sign-in validates inputs and failed network restore keeps guest untouched',
    (tester) async {
      final api = FakeCloudApi()
        ..getError = const CloudApiException('network_error');
      final cache = MemoryCloudCache();
      final c = CloudSyncController(
        api: api,
        cache: cache,
        sessionStore: MemorySessions(),
      );
      await c.initialize();
      await _open(tester, c);
      await _tap(tester, find.byKey(const ValueKey('cloud-submit')));
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('cloud-email')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloud-password')),
        'password',
      );
      await _tap(tester, find.byKey(const ValueKey('cloud-submit')));
      expect(
        find.text('Connection unavailable. Your changes stay on this device.'),
        findsOneWidget,
      );
      expect(cache.events, isEmpty);
      expect(c.user, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Arabic registration form fits 320px at 2x with Cairo and password rule',
    (tester) async {
      final api = FakeCloudApi();
      final c = CloudSyncController(
        api: api,
        cache: MemoryCloudCache(),
        sessionStore: MemorySessions(),
      );
      await c.initialize();
      await _open(tester, c, locale: 'ar', scale: 2);
      final context = tester.element(find.byType(CloudAccountPage));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'Cairo');
      await _tap(
        tester,
        find.text(plannerTextForLocale('ar', 'cloudRegister')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloud-email')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloud-password')),
        'قصير',
      );
      await _tap(tester, find.byKey(const ValueKey('cloud-submit')));
      expect(
        find.text(plannerTextForLocale('ar', 'cloudPasswordRule')),
        findsWidgets,
      );
      expect(api.events, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('conflict requires confirmation before archived restore', (
    tester,
  ) async {
    final api = FakeCloudApi();
    final cache = MemoryCloudCache()
      ..value = CloudCache(
        ownerId: 'a',
        revision: 4,
        pending: [cloudMutation('kept', 4)],
        errorCode: 'revision_conflict',
        conflict: api.remote,
      );
    final sessions = MemorySessions()..value = cloudSession();
    final c = CloudSyncController(
      api: api,
      cache: cache,
      sessionStore: sessions,
      clock: () => cloudNow,
    );
    await c.initialize(sync: false);
    await _open(tester, c);
    expect(find.text('Pending: 1'), findsOneWidget);
    await _tap(tester, find.text('Use cloud version'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(cache.archived, 0);
    expect(c.pendingCount, 1);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Go back'),
      ),
    );
    expect(cache.archived, 0);
    expect(c.pendingCount, 1);
    await _tap(tester, find.text('Use cloud version'));
    await _tap(
      tester,
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Use cloud version'),
          )
          .last,
    );
    expect(cache.archived, 1);
    expect(c.pendingCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
