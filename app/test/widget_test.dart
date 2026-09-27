import 'dart:async';

import 'package:sogda/bootstrap.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/features/backlog/backlog_screen.dart';
import 'package:sogda/router/app_router.dart';
import 'package:sogda/features/today/today_screen.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart';
import 'package:sogda/router/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, Locale, MaterialApp, Navigator, ThemeMode;
import 'package:material_ui/material_ui.dart' as material show Theme;

void main() {
  /// The app under a scope with the overrides bootstrap would have supplied.
  ///
  /// The theme is watched from a provider now, so a bare `SogdaApp`
  /// has nothing to read it from.
  Future<SogdaApp> pumpApp(
    WidgetTester tester, {
    ThemeModeSetting? choose,
    bool settle = true,
  }) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    if (choose != null) {
      await settings.write(SettingKeys.themeMode, choose);
    }

    final app = SogdaApp();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
        child: app,
      ),
    );
    // The aurora drifts for ever under glass: nothing to settle.
    settle ? await tester.pumpAndSettle() : await tester.pump();
    return app;
  }

  testWidgets('the app boots into the shell with Today showing', (
    tester,
  ) async {
    await pumpApp(tester);

    final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text(l10n.tabToday), findsWidgets);
    expect(
      find.byType(TodayScreen),
      findsOneWidget,
      reason: 'Today is the first tab',
    );
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

  testWidgets('FR-M3-02 Glass renders glass, light or smoked as the phone '
      'is', (tester) async {
    await pumpApp(tester, choose: ThemeModeSetting.glass, settle: false);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.extension<SgTokens>()!.isGlass, isTrue);
    expect(app.darkTheme!.extension<SgTokens>()!.isGlass, isTrue);
    expect(app.darkTheme!.brightness, Brightness.dark);
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

  testWidgets('#166 the meaning language and the app language switch apart, '
      'as M3 sets each', (tester) async {
    await pumpApp(tester);
    Locale? locale() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final languages = container.read(languagesProvider.notifier);
    MeaningLanguage meaning() => container.read(languagesProvider).meaning;

    // বাংলা copy with English meanings.
    await languages.setUi(UiLanguage.bangla);
    await languages.setMeaning(MeaningLanguage.english);
    await tester.pump();
    expect(locale(), const Locale('bn'));
    expect(meaning(), MeaningLanguage.english);

    // English copy with Bangla meanings: each moved alone.
    await languages.setUi(UiLanguage.english);
    await tester.pump();
    expect(locale(), const Locale('en'));
    expect(
      meaning(),
      MeaningLanguage.english,
      reason:
          'the app language '
          'left the meanings alone',
    );
    await languages.setMeaning(MeaningLanguage.bangla);
    await tester.pump();
    expect(
      locale(),
      const Locale('en'),
      reason:
          'the meanings left the '
          'app language alone',
    );
    expect(meaning(), MeaningLanguage.bangla);
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
    expect(find.byType(BacklogScreen), findsOneWidget);

    final second = await pumpApp(tester);
    expect(identical(first.router, second.router), isFalse);
    expect(
      find.byType(TodayScreen),
      findsOneWidget,
      reason: 'the second app inherited the first one’s stack',
    );
  });

  group("FR-M3-02 #644 following the phone's light/dark switch", () {
    // Through BootstrapHost, as `main` runs it, and the phone's own switch.
    // `main` used to take the dispatcher's onPlatformBrightnessChanged, the
    // framework's own callback: the theme notifier heard the switch, but the
    // root MediaQuery never did, so the app's system theme mode kept the old
    // brightness until some other metric changed.
    // Not pumpAndSettle: Glass's aurora drifts for ever. A second covers
    // bootstrap's answer and MaterialApp's theme animation.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> pumpHost(
      WidgetTester tester, {
      ThemeModeSetting choose = ThemeModeSetting.system,
      Brightness phone = Brightness.light,
    }) async {
      tester.platformDispatcher.platformBrightnessTestValue = phone;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      await settings.write(SettingKeys.themeMode, choose);
      final ready = Bootstrap(
        db: db,
        content: ContentDao(db),
        settings: settings,
        glass: GlassCapability(),
        router: buildRouter(),
        contentVersion: 'test',
        contentChange: null,
        themeMode: SgMode.light,
        themeSetting: choose,
        isFirstRun: false,
        elapsed: Duration.zero,
      );
      await tester.pumpWidget(
        BootstrapHost(
          run: ({
            Brightness platformBrightness = Brightness.light,
            void Function(UiLanguage)? onUiLanguage,
          }) async => BootstrapReady(ready),
          // The plugins have no platform side here; brightness isn't theirs.
          wire: (_, _) {},
        ),
      );
      await settle(tester);
    }

    /// The brightness the app draws in, and the mode its notifier holds.
    (Brightness, SgMode) shown(WidgetTester tester) => (
      material.Theme.of(tester.element(find.byType(Navigator).first))
          .brightness,
      ProviderScope.containerOf(tester.element(find.byType(SogdaApp)))
          .read(themeProvider),
    );

    Future<void> flip(WidgetTester tester, Brightness phone) async {
      tester.platformDispatcher.platformBrightnessTestValue = phone;
      await settle(tester);
    }

    testWidgets('a dark phone gets a dark first frame', (tester) async {
      await pumpHost(tester, phone: Brightness.dark);

      expect(shown(tester), (Brightness.dark, SgMode.dark));
    });

    testWidgets('System follows the switch while the app runs, both ways', (
      tester,
    ) async {
      await pumpHost(tester);
      expect(shown(tester), (Brightness.light, SgMode.light));

      await flip(tester, Brightness.dark);
      expect(shown(tester), (Brightness.dark, SgMode.dark));

      await flip(tester, Brightness.light);
      expect(shown(tester), (Brightness.light, SgMode.light));
    });

    testWidgets('Glass follows it too, into its smoked dark variant', (
      tester,
    ) async {
      await pumpHost(tester, choose: ThemeModeSetting.glass);
      expect(shown(tester), (Brightness.light, SgMode.glass));

      await flip(tester, Brightness.dark);
      expect(shown(tester), (Brightness.dark, SgMode.glass));
    });

    Future<void> choose(WidgetTester tester, ThemeModeSetting setting) async {
      await ProviderScope.containerOf(tester.element(find.byType(SogdaApp)))
          .read(themeProvider.notifier)
          .choose(setting);
      await settle(tester);
    }

    testWidgets('#649 Dark chosen on a dark phone, from System, stops the app '
        'following the phone', (tester) async {
      // The mode it resolves to is the one System had, so the root never
      // rebuilt, and it kept ThemeMode.system: the phone going light took the
      // app with it, despite the explicit Dark.
      await pumpHost(tester, phone: Brightness.dark);
      expect(shown(tester), (Brightness.dark, SgMode.dark));

      await choose(tester, ThemeModeSetting.dark);
      await flip(tester, Brightness.light);
      expect(shown(tester), (Brightness.dark, SgMode.dark));
    });

    testWidgets('#649 and System chosen from Light follows it from then on', (
      tester,
    ) async {
      await pumpHost(tester, choose: ThemeModeSetting.light);

      await choose(tester, ThemeModeSetting.system);
      await flip(tester, Brightness.dark);
      expect(shown(tester), (Brightness.dark, SgMode.dark));
    });

    testWidgets('an explicit choice is not overridden', (tester) async {
      await pumpHost(tester, choose: ThemeModeSetting.light);

      await flip(tester, Brightness.dark);
      expect(shown(tester), (Brightness.light, SgMode.light));
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
