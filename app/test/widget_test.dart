import 'dart:async';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, Locale, MaterialApp, ThemeMode, VoidCallback;

void main() {
  /// The app under a scope with the overrides bootstrap would have supplied.
  ///
  /// The theme is watched from a provider now, so a bare `DeutschPlanApp`
  /// has nothing to read it from.
  Future<DeutschPlanApp> pumpApp(
    WidgetTester tester, {
    ThemeModeSetting? choose,
  }) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    if (choose != null) {
      await settings.write(SettingKeys.themeMode, choose);
    }

    final app = DeutschPlanApp();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('the app boots into the shell with Today showing', (
    tester,
  ) async {
    await pumpApp(tester);

    final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text(l10n.tabToday), findsWidgets);
    expect(find.text('T1'), findsOneWidget, reason: 'Today is the first tab');
  });

  testWidgets('the chosen mode is what the app renders', (tester) async {
    // Read from `themeProvider`, not captured at launch: Settings writes
    // through `Theme.choose` and the new mode has to reach the next frame.
    for (final pair in const <(ThemeModeSetting, ThemeMode)>[
      (ThemeModeSetting.light, ThemeMode.light),
      (ThemeModeSetting.dark, ThemeMode.dark),
    ]) {
      await pumpApp(tester, choose: pair.$1);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, pair.$2, reason: '${pair.$1}');
    }
  });

  testWidgets('a Settings change reaches the next frame', (tester) async {
    // The whole point of watching the provider. Before this, `choose` moved
    // the notifier and repainted nothing.
    await pumpApp(tester, choose: ThemeModeSetting.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    final scope = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await scope.read(themeProvider.notifier).choose(ThemeModeSetting.dark);
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('the app speaks ui_language, and page 2 changes it at once', (
    tester,
  ) async {
    // S2 page 2: "This also sets the app language." Without `locale:` the
    // setting was stored and nothing read it — the app followed the phone.
    await pumpApp(tester);
    Locale? locale() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;
    expect(locale(), const Locale('en'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    unawaited(
      container
          .read(languagesProvider.notifier)
          .chooseMeaning(MeaningLanguage.bangla),
    );
    await tester.pump();

    expect(locale(), const Locale('bn'));
    expect(
      AppLocalizations.of(tester.element(find.byType(AppShell))).localeName,
      'bn',
    );
  });

  testWidgets('following the system keeps following it', (tester) async {
    // `theme_mode = system` resolves to a concrete mode for the first frame.
    // Passing that straight to MaterialApp would pin the app to whatever the
    // phone was on at launch.
    await pumpApp(tester, choose: ThemeModeSetting.system);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('each app gets its own navigation stack', (tester) async {
    // The router owns the stack, so a static one would be shared by every
    // instance — and two widget tests in a file would inherit each other's
    // history. The real app's router comes from bootstrap; this is the
    // default path.
    final first = await pumpApp(tester);

    first.router.go('/today/backlog');
    await tester.pumpAndSettle();
    expect(find.text('T4'), findsOneWidget);

    final second = await pumpApp(tester);
    expect(identical(first.router, second.router), isFalse);
    expect(
      find.text('T1'),
      findsOneWidget,
      reason: 'the second app inherited the first one’s stack',
    );
  });

  group('following the system brightness', () {
    Future<(ProviderContainer, SettingsRepository)> scope({
      ThemeModeSetting? choose,
    }) async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      if (choose != null) {
        await settings.write(SettingKeys.themeMode, choose);
      }

      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      return (container, settings);
    }

    test('seeds the notifier with the real brightness at startup', () async {
      // The notifier's own default is `light`. A dark phone would otherwise
      // see a light first frame before anything changed.
      final (container, _) = await scope();

      followPlatformBrightness(
        container,
        read: () => Brightness.dark,
        onChanged: (_) {},
      );

      expect(container.read(themeProvider), DpMode.dark);
    });

    test('and follows it afterwards', () async {
      final (container, _) = await scope();
      var brightness = Brightness.light;
      VoidCallback? listener;

      followPlatformBrightness(
        container,
        read: () => brightness,
        onChanged: (callback) => listener = callback,
      );
      expect(container.read(themeProvider), DpMode.light);
      expect(listener, isNotNull, reason: 'nothing was registered');

      brightness = Brightness.dark;
      listener!();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeProvider), DpMode.dark);
    });

    test('an explicit choice is not overridden', () async {
      final (container, _) = await scope(choose: ThemeModeSetting.light);

      followPlatformBrightness(
        container,
        read: () => Brightness.dark,
        onChanged: (_) {},
      );

      expect(container.read(themeProvider), DpMode.light);
    });
  });

  test('English leads supportedLocales so it is the fallback locale', () {
    expect(supportedLocales.first.languageCode, 'en');
    expect(
      supportedLocales.map((l) => l.languageCode).toSet(),
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      reason: 'a language was added to lib/l10n/ without adding it to supportedLocales',
    );
  });
}
