import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_slider.dart';
import 'package:deutschplan/core/components/dp_stepper.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/features/me/settings_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import 'settings_fixtures.dart';

/// M3 · Settings — #146.
void main() {
  late AppLocalizations l10n;
  late AppDatabase db;
  late SettingsRepository settings;
  late String went;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    went = '';
  });

  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester, {
    List<double> stabilities = const <double>[],
    ModelState? model,
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    // Tall enough that every row is built: the table below reaches all of
    // them without scrolling.
    tester.view
      ..physicalSize = const Size(1200, 9000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    Widget away(GoRouterState state) {
      went = state.uri.toString();
      return const SizedBox();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          learnedStabilitiesProvider.overrideWith((ref) async => stabilities),
          translationModelProvider.overrideWith((ref) async => model),
        ],
        child: MaterialApp.router(
          builder: (context, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/me/settings',
            routes: <RouteBase>[
              // M1 itself records nothing: it is built under whatever is
              // opened over it, pushed or not.
              GoRoute(
                path: '/me',
                builder: (_, _) => const SizedBox(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const SettingsScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'reminder',
                        builder: (_, state) => away(state),
                      ),
                    ],
                  ),
                  for (final path in <String>['models', 'export'])
                    GoRoute(path: path, builder: (_, state) => away(state)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder switchFor(String label) => find.byWidgetPredicate(
    (widget) => widget is AdaptiveSwitch && widget.semanticLabel == label,
  );
  Finder sliderFor(String label) => find.byWidgetPredicate(
    (widget) => widget is DpSlider && widget.label == label,
  );

  testWidgets('every row in settings.md is there', (tester) async {
    await pump(tester);

    for (final title in <String>[
      l10n.settingsDailyNew,
      l10n.settingsReviseCount,
      l10n.settingsSentenceCount,
      l10n.settingsStudyDays,
      l10n.settingsAutoAdvance,
      l10n.settingsPauseNew,
      l10n.settingsRetention,
      l10n.settingsDoneDays(7),
      l10n.settingsSwipeToRate,
      l10n.settingsMeaning,
      l10n.settingsUiLanguage,
      l10n.settingsTheme,
      l10n.settingsShowPronBn,
      l10n.settingsVoiceEngine,
      l10n.settingsSpeed,
      l10n.settingsAutoplayHeadword,
      l10n.settingsAutoplayExample,
      l10n.settingsListening,
      l10n.settingsUnlockAt,
      l10n.settingsPassMark,
      l10n.settingsTimerDefault,
      l10n.settingsTranslation,
      l10n.settingsExport,
      l10n.settingsReset,
      l10n.settingsRestart,
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('each stepper writes its key, at once', (tester) async {
    await pump(tester);

    for (final (increase, key, expected) in <(String, IntSetting, int)>[
      (l10n.settingsDailyNewIncrease, SettingKeys.dailyNew, 8),
      (l10n.settingsReviseCountIncrease, SettingKeys.reviseCount, 11),
      (l10n.settingsSentenceCountIncrease, SettingKeys.sentenceCount, 4),
      (l10n.settingsDoneDaysIncrease, SettingKeys.doneStabilityDays, 8),
    ]) {
      await tester.tap(find.bySemanticsLabel(increase));
      await tester.pumpAndSettle();
      expect(settings.read(key), expected, reason: key.name);
    }
    expect(find.text(l10n.settingsDoneDays(8)), findsOneWidget);
  });

  testWidgets("the steppers' ranges are settings.md's", (tester) async {
    await pump(tester);

    final ranges = <String, (int, int)>{
      for (final stepper in tester.widgetList<DpStepper>(
        find.byType(DpStepper),
      ))
        stepper.increaseLabel: (stepper.min, stepper.max),
    };
    expect(ranges, <String, (int, int)>{
      l10n.settingsDailyNewIncrease: (1, 50),
      l10n.settingsReviseCountIncrease: (0, 100),
      l10n.settingsSentenceCountIncrease: (0, 20),
      l10n.settingsDoneDaysIncrease: (3, 60),
    });
    final retention = tester.widget<DpSlider>(
      sliderFor(l10n.settingsRetention),
    );
    expect((retention.min, retention.max), (80, 97));
  });

  testWidgets('each switch writes its key', (tester) async {
    await pump(tester);

    for (final (label, key) in <(String, BoolSetting)>[
      (l10n.settingsAutoAdvance, SettingKeys.autoAdvance),
      (l10n.settingsPauseNew, SettingKeys.pauseNewWhenBacklog),
      (l10n.settingsSwipeToRate, SettingKeys.swipeToRate),
      (l10n.settingsShowPronBn, SettingKeys.showPronBn),
      (l10n.settingsAutoplayHeadword, SettingKeys.autoplayHeadword),
      (l10n.settingsAutoplayExample, SettingKeys.autoplayExample),
      (l10n.settingsListening, SettingKeys.listeningQuestions),
      (l10n.settingsTimerDefault, SettingKeys.examTimerDefault),
    ]) {
      final before = settings.read(key);
      await tester.tap(switchFor(label));
      await tester.pumpAndSettle();
      expect(settings.read(key), !before, reason: key.name);
    }
  });

  testWidgets('the sliders write retention and speed', (tester) async {
    await pump(tester);

    // Each end of its 120 dp track, a dp in from the edge.
    final retention = sliderFor(l10n.settingsRetention);
    await tester.tapAt(tester.getCenter(retention) + const Offset(59, 0));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.desiredRetention), 0.97);

    final speed = sliderFor(l10n.settingsSpeed);
    await tester.tapAt(tester.getCenter(speed) - const Offset(59, 0));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.ttsSpeed), 0.5);
    expect(find.text(l10n.settingsSpeedLine('0.5')), findsOneWidget);
  });

  testWidgets("speech speed is on the study menu's grid: 0.75 and 1.25 read "
      'as they are', (tester) async {
    await settings.write(SettingKeys.ttsSpeed, 0.75);
    await pump(tester);
    expect(find.text(l10n.settingsSpeedLine('0.75')), findsOneWidget);
    final slider = tester.widget<DpSlider>(sliderFor(l10n.settingsSpeed));
    expect((slider.min, slider.value, slider.max), (2, 3, 6));

    await settings.write(SettingKeys.ttsSpeed, 1.25);
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsSpeedLine('1.25')), findsOneWidget);
  });

  testWidgets('each choice writes its key', (tester) async {
    await pump(tester);

    Future<void> choose(String row, String option) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      // The sheet's, over the row behind it that may say the same.
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await choose(l10n.settingsMeaning, l10n.settingsBangla);
    expect(settings.read(SettingKeys.meaningLanguage), MeaningLanguage.bangla);
    // The meaning alone: S2's one choice sets both, M3's two rows don't.
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.english);

    await choose(l10n.settingsMeaning, l10n.settingsEnglish);
    await choose(l10n.settingsUiLanguage, l10n.settingsBangla);
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.bangla);
    expect(settings.read(SettingKeys.meaningLanguage), MeaningLanguage.english);
  });

  testWidgets('the exam percentages, in fives across their ranges', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l10n.settingsUnlockAt));
    await tester.pumpAndSettle();
    for (final p in <int>[50, 55, 95, 100]) {
      expect(find.text(l10n.settingsPercent(p)), findsWidgets, reason: '$p');
    }
    await tester.tap(find.text(l10n.settingsPercent(80)).last);
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.examUnlockPercent), 80);

    await tester.tap(find.text(l10n.settingsPassMark));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsPercent(95)), findsNothing);
    await tester.tap(find.text(l10n.settingsPercent(70)).last);
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.examPassPercent), 70);
    expect(find.text(l10n.settingsPercent(70)), findsOneWidget);
  });

  testWidgets('BR-PLAN-08 New words per day reaches tomorrow\'s plan, and '
      'today\'s stays as it was', (tester) async {
    await tester.runAsync(() async {
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
      );
      await DriftPlanStore(db, settings).enroll(
        const ActiveStep(
          sublevelCode: 'A1.1',
          startedOn: '2026-09-21',
          dailyNew: 7,
          studyDaysMask: 127,
        ),
      );
    });
    PlanEngine engine() => PlanEngine(
      store: DriftPlanStore(db, settings),
      reviseCount: 10,
      backlogCatchupDays: 30,
    );
    final today = await tester.runAsync(() => engine().openDay('2026-09-21'));
    expect(today!.newToday, hasLength(7));

    await pump(tester);
    await tester.tap(find.bySemanticsLabel(l10n.settingsDailyNewIncrease));
    await tester.pumpAndSettle();

    final (again, tomorrow) = (await tester.runAsync(
      () async => (
        await engine().openDay('2026-09-21'),
        await engine().openDay('2026-09-22'),
      ),
    ))!;
    expect(settings.read(SettingKeys.dailyNew), 8);
    expect(again.newToday, hasLength(7));
    expect(tomorrow.newToday, hasLength(8));
  });

  testWidgets('BR-PLAN-08 new words and revisions apply from tomorrow', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.settingsFromTomorrow), findsNWidgets(2));
  });

  testWidgets('FR-M3-01 the retention line: reviews a day at the chosen '
      'retention', (tester) async {
    // Ten days of stability comes round every ten days at 90 %.
    await pump(tester, stabilities: List<double>.filled(110, 10));
    expect(find.text(l10n.settingsRetentionLine(90, 11)), findsOneWidget);

    final slider = sliderFor(l10n.settingsRetention);
    await tester.tapAt(tester.getCenter(slider) + const Offset(59, 0));
    await tester.pumpAndSettle();
    // At 97 % the same words come round every three days.
    expect(find.text(l10n.settingsRetentionLine(97, 37)), findsOneWidget);
  });

  testWidgets('FR-M3-02 a theme applies at once, Glass too', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    // Built first, as the app's root has it built: the choice has to reach a
    // theme already on screen.
    expect(container.read(themeProvider), DpMode.light);

    await tester.tap(find.text(l10n.settingsTheme));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsThemeGlass).last);
    await tester.pumpAndSettle();

    expect(container.read(themeProvider), DpMode.glass);
    expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.glass);
    expect(find.text(l10n.settingsThemeGlass), findsOneWidget);
  });

  group('FR-M3-03 translation', () {
    testWidgets('on without the model: M4, and the switch stays off', (
      tester,
    ) async {
      await pump(tester, model: downloadingModel(ModelStatus.notDownloaded));
      expect(
        find.text(l10n.settingsTranslationStatus('none', 42)),
        findsOneWidget,
      );

      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();

      expect(went, '/me/models');
      expect(settings.read(SettingKeys.mtEnabled), isFalse);
    });

    testWidgets('mid-download is not ready either', (tester) async {
      await pump(tester, model: downloadingModel());
      expect(
        find.text(l10n.settingsTranslationStatus('downloading', 42)),
        findsOneWidget,
      );

      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.mtEnabled), isFalse);
    });

    testWidgets('an update waiting is still a whole model', (tester) async {
      await pump(tester, model: downloadingModel(ModelStatus.updateAvailable));

      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.mtEnabled), isTrue);
      expect(went, isEmpty);
    });

    testWidgets('on with the model ready, and off again', (tester) async {
      await pump(tester, model: downloadingModel(ModelStatus.ready));

      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.mtEnabled), isTrue);
      expect(went, isEmpty);

      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.mtEnabled), isFalse);
    });
  });

  group('the study days line', () {
    testWidgets('every day, with no reminder', (tester) async {
      await pump(tester);
      expect(
        find.text('${l10n.settingsEveryDay} · ${l10n.settingsNoReminder}'),
        findsOneWidget,
      );
    });

    testWidgets("a run of days and the reminder's time", (tester) async {
      await settings.write(SettingKeys.studyDaysMask, 63);
      await settings.write(SettingKeys.reminderEnabled, true);
      await pump(tester);
      expect(
        find.text('Mon–Sat · 7:30 PM · ${l10n.settingsOnlyWhenDue}'),
        findsOneWidget,
      );
    });

    testWidgets('days apart, and a reminder whatever is due', (tester) async {
      await settings.write(SettingKeys.studyDaysMask, 1 | 4 | 16);
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderOnlyWhenDue, false);
      await pump(tester);
      expect(find.text('Mon, Wed, Fri · 7:30 PM'), findsOneWidget);
    });

    testWidgets("a run across the week's end", (tester) async {
      await settings.write(SettingKeys.studyDaysMask, 16 | 32 | 64 | 1);
      await pump(tester);
      expect(find.text('Fri–Mon · ${l10n.settingsNoReminder}'), findsOneWidget);
    });

    testWidgets('two days in a row are two days', (tester) async {
      await settings.write(SettingKeys.studyDaysMask, 32 | 64);
      await pump(tester);
      expect(
        find.text('Sat, Sun · ${l10n.settingsNoReminder}'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the voice engine says which', (tester) async {
    await pump(tester);
    expect(find.text(l10n.settingsVoiceSupertonic('Anna')), findsOneWidget);

    await settings.write(SettingKeys.ttsEngine, TtsEngineSetting.system);
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsVoicePhone), findsOneWidget);
  });

  group('rows that open another screen', () {
    for (final (row, to) in <(String Function(AppLocalizations), String)>[
      ((l10n) => l10n.settingsStudyDays, '/me/settings/reminder'),
      ((l10n) => l10n.settingsVoiceEngine, '/me/models'),
      ((l10n) => l10n.settingsExport, '/me/export'),
    ]) {
      testWidgets(to, (tester) async {
        await pump(tester);
        await tester.tap(find.text(row(l10n)));
        await tester.pumpAndSettle();
        expect(went, to);
      });
    }
  });

  testWidgets('M4 and M6 are pushed: back returns to Settings', (tester) async {
    await pump(tester);
    for (final (row, to) in <(String, String)>[
      (l10n.settingsVoiceEngine, '/me/models'),
      (l10n.settingsExport, '/me/export'),
    ]) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(went, to);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget, reason: to);
    }
  });

  testWidgets('Material headers on Android, inset groups on iOS', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.settingsGroupDailyPlan), findsOneWidget);
    expect(find.byType(DpSurface), findsNothing);

    await pump(tester, chrome: AdaptiveChrome.cupertino);
    expect(
      find.text(l10n.settingsGroupDailyPlan.toUpperCase()),
      findsOneWidget,
    );
    expect(find.byType(DpSurface), findsNWidgets(7));
  });

  testWidgets('a screen reader hears a switch row once, and its note', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final row = tester.getSemantics(find.text(l10n.settingsSwipeToRateNote));
    expect(l10n.settingsSwipeToRate.allMatches(row.label), hasLength(1));
    expect(row.label, contains(l10n.settingsSwipeToRateNote));
    semantics.dispose();
  });

  test('FR-M3-01 reviews a day: the sum of 1 ÷ interval, sampled', () {
    final fsrs = Fsrs();
    // At 90 % the interval is the stability: 1 + 1/10.
    expect(fsrs.reviewsPerDay(<double>[1, 10]), closeTo(1.1, 1e-9));
    expect(fsrs.reviewsPerDay(const <double>[]), 0);
    // Five thousand, every fifth summed and scaled back up.
    expect(
      fsrs.reviewsPerDay(List<double>.filled(5000, 10)),
      closeTo(500, 1e-9),
    );
    expect(Fsrs(desiredRetention: 0.97).intervalDays(10), 3);
  });

  test('FR-M3-01 sums over every word rated and not suspended', () async {
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, stability, reps) VALUES
  ('a', 'learning', 2.5, 1),
  ('b', 'done', 30, 6),
  ('c', 'suspended', 12, 3),
  ('d', 'todo', 0, 0)
''');
    expect(await WordRepository(db, settings).learnedStabilities(), <double>[
      2.5,
      30,
    ]);
  });
}
