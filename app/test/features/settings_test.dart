import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_slider.dart';
import 'package:sogda/core/components/sg_stepper.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/fsrs.dart';
import 'package:sogda/domain/plan_engine.dart';
import 'package:sogda/features/me/settings_screen.dart';
import 'package:sogda/features/today/today_providers.dart'
    show voiceInstalledProvider;
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_language_locale.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/router/routes.dart' show SettingsRoute;
import 'package:sogda/services/model_downloads.dart' show DownloadPhase;

import '../core/semantics_checks.dart';
import '../db/content_fixture.dart';
import 'model_manager_fixtures.dart' show FakeDownloads, FakeModels;
import 'settings_fixtures.dart';

/// M3 · Settings — #146.
void main() {
  late AppLocalizations l10n;
  late AppDatabase db;
  late SettingsRepository settings;
  late String went;
  late _Photos photos;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    went = '';
    photos = _Photos(db);
  });

  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester, {
    List<double> stabilities = const <double>[],
    ModelState? model,
    AdaptiveChrome chrome = AdaptiveChrome.material,
    Locale? locale,
    // Null reads it as the app does, from [extra]'s models and downloads.
    bool? voiceInstalled = true,
    List<Override> extra = const <Override>[],
    // `SettingsRoute.row` (#1364).
    String? row,
    Size size = const Size(1200, 9000),
  }) async {
    // Tall enough that every row is built: the table below reaches all of
    // them without scrolling.
    tester.view
      ..physicalSize = size
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
          if (voiceInstalled != null)
            voiceInstalledProvider.overrideWith((ref) async => voiceInstalled),
          documentRepositoryProvider.overrideWithValue(photos),
          ...extra,
        ],
        child: MaterialApp.router(
          builder: (context, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          locale: locale,
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
                    builder: (_, _) => SettingsScreen(row: row),
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
    (widget) => widget is SgSlider && widget.label == label,
  );

  testWidgets('#1364 opened from a locked exam, M3 shows Unlock mock exams '
      'at, down the page', (tester) async {
    bool onScreen(WidgetTester tester) {
      final top = tester.getRect(find.text(l10n.settingsUnlockAt)).top;
      return top >= 0 && top < 2400 / 3;
    }

    await pump(tester, size: const Size(1080, 2400));
    expect(
      find.text(l10n.settingsUnlockAt).hitTestable(),
      findsNothing,
      reason: 'below the fold on its own',
    );
    await pump(
      tester,
      size: const Size(1080, 2400),
      row: SettingsRoute.examUnlock,
    );
    expect(onScreen(tester), isTrue);
  });

  testWidgets('every row in settings.md is there', (tester) async {
    // Translation's with a model on the phone (#513).
    await pump(tester, model: downloadingModel());

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
      l10n.settingsQuizCustomWords,
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
      l10n.settingsDocDailyCap,
      l10n.settingsDocSaveImages,
      l10n.settingsDocAutodelete,
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
      (l10n.settingsDocDailyCapIncrease, SettingKeys.docDailyCap, 6),
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
      for (final stepper in tester.widgetList<SgStepper>(
        find.byType(SgStepper),
      ))
        stepper.increaseLabel: (stepper.min, stepper.max),
    };
    expect(ranges, <String, (int, int)>{
      l10n.settingsDailyNewIncrease: (1, 50),
      l10n.settingsReviseCountIncrease: (0, 100),
      l10n.settingsSentenceCountIncrease: (0, 20),
      l10n.settingsDoneDaysIncrease: (3, 60),
      l10n.settingsDocDailyCapIncrease: (0, 20),
    });
    final retention = tester.widget<SgSlider>(
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
      (l10n.settingsQuizCustomWords, SettingKeys.quizCustomWords),
      (l10n.settingsShowPronBn, SettingKeys.showPronBn),
      (l10n.settingsAutoplayHeadword, SettingKeys.autoplayHeadword),
      (l10n.settingsAutoplayExample, SettingKeys.autoplayExample),
      (l10n.settingsListening, SettingKeys.listeningQuestions),
      (l10n.settingsTimerDefault, SettingKeys.examTimerDefault),
      // No photo kept: nothing to ask (FR-D3-04).
      (l10n.settingsDocSaveImages, SettingKeys.docSaveImages),
    ]) {
      final before = settings.read(key);
      await tester.tap(switchFor(label));
      await tester.pumpAndSettle();
      expect(settings.read(key), !before, reason: key.name);
    }
  });

  testWidgets('#345 a switch row flips from anywhere on it, not only its '
      'switch', (tester) async {
    await pump(tester);
    for (final (label, key) in <(String, BoolSetting)>[
      (l10n.settingsSwipeToRate, SettingKeys.swipeToRate),
      (l10n.settingsAutoplayExample, SettingKeys.autoplayExample),
    ]) {
      final before = settings.read(key);
      await tester.tap(find.text(label));
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

  group('#698 a slider saves when the finger lets go', () {
    /// How many times retention was written, as `SettingsEditor` hears it.
    List<Object?> writes() {
      final heard = <Object?>[];
      final listening = settings.changes
          .where((key) => key == SettingKeys.desiredRetention)
          .listen(heard.add);
      addTearDown(listening.cancel);
      return heard;
    }

    testWidgets('a drag shows every step in its row at once, and writes once, '
        'on release', (tester) async {
      await pump(tester);
      final heard = writes();
      final slider = sliderFor(l10n.settingsRetention);
      int shown() => tester.widget<SgSlider>(slider).value;

      // 90 % sits 10/17 of the way along the 120 dp track.
      final gesture = await tester.startGesture(
        tester.getCenter(slider) + const Offset(10.6, 0),
      );
      // Past the slop: the drag starts, and the next move moves it.
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(9.4, 0));
      await tester.pump();
      expect(shown(), 94);
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(shown(), 96);
      expect(find.text(l10n.settingsRetentionLine(96, 0)), findsOneWidget);
      expect(settings.read(SettingKeys.desiredRetention), 0.9);
      expect(heard, isEmpty, reason: 'a step wrote user.db');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.desiredRetention), 0.96);
      expect(heard, hasLength(1));
      expect(shown(), 96);
      expect(find.text(l10n.settingsRetentionLine(96, 0)), findsOneWidget);

      // And the row follows the setting again: an import or a reset writes
      // it too.
      await settings.write(SettingKeys.desiredRetention, 0.85);
      await tester.pumpAndSettle();
      expect(shown(), 85);
    });

    testWidgets('a drag let go and the screen left at once still saves: '
        'nothing waits for a later frame', (tester) async {
      await pump(tester);
      final slider = sliderFor(l10n.settingsRetention);
      final gesture = await tester.startGesture(
        tester.getCenter(slider) + const Offset(10.6, 0),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(9.4, 0));
      await tester.pump();
      expect(tester.widget<SgSlider>(slider).value, 94);

      await gesture.up();
      // Left before another frame: Settings and its providers are gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.desiredRetention), 0.94);
    });

    testWidgets('a touch the scroll view takes over keeps, and saves, the '
        'value the thumb moved to', (tester) async {
      await pump(tester);
      final slider = sliderFor(l10n.settingsRetention);
      final gesture = await tester.startGesture(
        tester.getCenter(slider) + const Offset(59, 0),
      );
      // Past the tap's deadline: its down moves the thumb.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<SgSlider>(slider).value, 97);

      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.desiredRetention), 0.97);
      expect(tester.widget<SgSlider>(slider).value, 97);
    });

    testWidgets("a key's or a screen reader's step saves at once", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      // The row's node, which its note and its slider's label share.
      tester.semantics.increase(
        find.semantics.byLabel(RegExp(RegExp.escape(l10n.settingsRetention))),
      );
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.desiredRetention), 0.91);
      semantics.dispose();
    });

    testWidgets('its target is 48 dp tall around the 32 dp it draws', (
      tester,
    ) async {
      await pump(tester);
      final slider = sliderFor(l10n.settingsSpeed);

      // 20 dp over the track's middle: outside what it draws, inside 48.
      await tester.tapAt(tester.getCenter(slider) + const Offset(-59, -20));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.ttsSpeed), 0.5);
    });
  });

  testWidgets("speech speed is on the study menu's grid: 0.75 and 1.25 read "
      'as they are', (tester) async {
    await settings.write(SettingKeys.ttsSpeed, 0.75);
    await pump(tester);
    expect(find.text(l10n.settingsSpeedLine('0.75')), findsOneWidget);
    final slider = tester.widget<SgSlider>(sliderFor(l10n.settingsSpeed));
    expect((slider.min, slider.value, slider.max), (2, 3, 6));

    await settings.write(SettingKeys.ttsSpeed, 1.25);
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsSpeedLine('1.25')), findsOneWidget);
  });

  testWidgets('#425 in the Bangla UI, the speed line and the slider a '
      'screen reader hears are in Bangla digits', (tester) async {
    await settings.write(SettingKeys.ttsSpeed, 0.75);
    await pump(tester, locale: const Locale('bn'));
    final bn = lookupAppLocalizations(const Locale('bn'));
    expect(find.text(bn.settingsSpeedLine('০.৭৫')), findsOneWidget);
    final slider = tester.widget<SgSlider>(sliderFor(bn.settingsSpeed));
    expect(slider.describe!(3), '০.৭৫×');
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

    // #1081: Bangla first, the English it was first after it.
    await choose(l10n.settingsMeaning, 'বাংলা');
    expect(meaningChoiceOf(settings), const MeaningChoice('bn', 'en'));
    // The meaning alone: M3's rows leave the app language (#1078).
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.english);

    await choose(l10n.settingsMeaningSecond, l10n.settingsMeaningNone);
    expect(meaningChoiceOf(settings), const MeaningChoice('bn'));
    await choose(l10n.settingsMeaning, 'English');
    expect(meaningChoiceOf(settings), const MeaningChoice('en'));
    await choose(l10n.settingsMeaningSecond, 'বাংলা');
    expect(meaningChoiceOf(settings), const MeaningChoice('en', 'bn'));
    await choose(l10n.settingsUiLanguage, 'বাংলা');
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.bangla);
    expect(meaningChoiceOf(settings), const MeaningChoice('en', 'bn'));
  });

  testWidgets('#1081 the meaning rows list the languages the course ships, '
      'each named in itself; the second offers none, and never the first', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.settingsMeaningSecond), findsOneWidget);

    await tester.tap(find.text(l10n.settingsMeaningSecond));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsMeaningNone), findsOneWidget);
    // English is the first: the row's and the app language's values only.
    expect(find.text('English'), findsNWidgets(2));
    expect(find.text('Polski'), findsNothing, reason: 'not in the course');
  });

  testWidgets('#1078 M3 lists every app language, each named in itself', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.text('English'),
      findsNWidgets(2),
      reason: "the app's row and the first meaning's",
    );

    await tester.tap(find.text(l10n.settingsUiLanguage));
    await tester.pumpAndSettle();
    for (final name in UiLanguage.values.map((l) => l.nativeName)) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    await tester.tap(find.text('Polski'));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.polish);
    expect(meaningChoiceOf(settings), const MeaningChoice('en', 'bn'));
  });

  testWidgets('#537 #1077 FR-M3-04 the Bangla pronunciation switch is offered '
      "only while Bangla is a meaning language; M3's meaning row leaves the "
      "learner's switch as set", (tester) async {
    await pump(tester);
    Future<void> choose(String row, String option) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    expect(settings.read(SettingKeys.showPronBn), isTrue);
    await choose(l10n.settingsMeaningSecond, l10n.settingsMeaningNone);
    expect(meaningChoiceOf(settings), const MeaningChoice('en'));
    // English only: no Bangla pronunciation to switch, the row gone at once.
    expect(find.text(l10n.settingsShowPronBn), findsNothing);
    expect(settings.read(SettingKeys.showPronBn), isTrue, reason: 'as set');

    await choose(l10n.settingsMeaning, 'বাংলা');
    expect(meaningChoiceOf(settings), const MeaningChoice('bn'));
    expect(find.text(l10n.settingsShowPronBn), findsOneWidget);
    await tester.tap(switchFor(l10n.settingsShowPronBn));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.showPronBn), isFalse);
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

  testWidgets('BR-PLAN-08 new words, revisions and the words from documents '
      '(#1296) apply from tomorrow', (tester) async {
    await pump(tester);
    expect(find.text(l10n.settingsFromTomorrow), findsNWidgets(3));
  });

  group('#1296 FR-D3-04 Save original images, turned off', () {
    Future<void> flip(WidgetTester tester) async {
      await tester.tap(switchFor(l10n.settingsDocSaveImages));
      await tester.pumpAndSettle();
    }

    testWidgets('with photos kept, asks; Delete images drops them', (
      tester,
    ) async {
      photos.bytes = 4000;
      await pump(tester);
      await flip(tester);
      expect(settings.read(SettingKeys.docSaveImages), isFalse);
      expect(find.text(l10n.settingsDocImagesDropTitle), findsOneWidget);

      await tester.tap(find.text(l10n.settingsDocImagesDrop));
      await tester.pumpAndSettle();
      expect(photos.drops, 1);
      expect(find.text(l10n.settingsDocImagesDropTitle), findsNothing);
    });

    testWidgets('Keep them keeps them, and the switch stays off', (
      tester,
    ) async {
      photos.bytes = 4000;
      await pump(tester);
      await flip(tester);
      await tester.tap(find.text(l10n.settingsDocImagesKeep));
      await tester.pumpAndSettle();
      expect(photos.drops, 0);
      expect(settings.read(SettingKeys.docSaveImages), isFalse);
    });

    testWidgets('with none kept, or turned on, nothing is asked', (
      tester,
    ) async {
      await pump(tester);
      await flip(tester);
      expect(find.text(l10n.settingsDocImagesDropTitle), findsNothing);

      photos.bytes = 4000;
      await flip(tester);
      expect(settings.read(SettingKeys.docSaveImages), isTrue);
      expect(find.text(l10n.settingsDocImagesDropTitle), findsNothing);
      expect(photos.drops, 0);
    });
  });

  testWidgets('#1296 FR-D3-03 Auto-delete documents: Never, or after 30, 90 '
      'or 365 days, its value beside it', (tester) async {
    await pump(tester);
    expect(find.text(l10n.settingsDocAutodeleteNever), findsOneWidget);
    expect(find.text(l10n.settingsDocAutodeleteNote), findsOneWidget);

    await tester.tap(find.text(l10n.settingsDocAutodelete));
    await tester.pumpAndSettle();
    for (final days in <int>[30, 90, 365]) {
      expect(find.text(l10n.settingsDocAutodeleteAfter(days)), findsOneWidget);
    }
    await tester.tap(find.text(l10n.settingsDocAutodeleteAfter(90)));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.docAutodeleteDays), 90);
    expect(find.text(l10n.settingsDocAutodeleteAfter(90)), findsOneWidget);
    expect(find.text(l10n.settingsDocAutodeleteNever), findsNothing);
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
    expect(container.read(themeProvider), SgMode.light);

    await tester.tap(find.text(l10n.settingsTheme));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsThemeGlass).last);
    await tester.pumpAndSettle();

    expect(container.read(themeProvider), SgMode.glass);
    expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.glass);
    expect(find.text(l10n.settingsThemeGlass), findsOneWidget);
  });

  group('FR-M3-03 translation', () {
    // Without a usable model: a failed download's.
    testWidgets('on without a usable model: M4, and the switch stays off', (
      tester,
    ) async {
      await pump(tester, model: downloadingModel(ModelStatus.failed));
      expect(
        find.text(l10n.settingsTranslationStatus('failed', 42)),
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

    testWidgets('#154 ADR 30: the Translation group shows in every build, '
        'with no model on the phone too', (tester) async {
      for (final model in <ModelState?>[
        null,
        downloadingModel(ModelStatus.notDownloaded),
      ]) {
        // A new scope for each: one keeps its first overrides.
        await tester.pumpWidget(const SizedBox());
        await pump(tester, model: model);
        expect(find.text(l10n.settingsGroupTranslation), findsOneWidget);
        expect(find.text(l10n.settingsTranslation), findsOneWidget);
      }
    });

    testWidgets('#154 below Hy-MT2\'s memory floor, translation can\'t be '
        'turned on, and the row says why', (tester) async {
      await pump(
        tester,
        model: downloadingModel(ModelStatus.ready),
        extra: <Override>[
          translationFitsProvider.overrideWith((ref) async => false),
        ],
      );
      expect(
        find.text(l10n.modelsNeedsMemory(l10n.modelsSizeGb('4'))),
        findsOneWidget,
      );
      // Dimmed, as Material draws a disabled switch.
      final dimmed = tester.widget<Opacity>(
        find
            .descendant(
              of: switchFor(l10n.settingsTranslation),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dimmed.opacity, 0.38);
      await tester.tap(switchFor(l10n.settingsTranslation));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.mtEnabled), isFalse);
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

  testWidgets('#345 Supertonic chosen but not on the phone: the phone voice '
      'speaks, and the row says so', (tester) async {
    await pump(tester, voiceInstalled: false);
    expect(find.text(l10n.settingsVoicePhoneForSupertonic), findsOneWidget);
    expect(find.text(l10n.settingsVoiceSupertonic('Anna')), findsNothing);
  });

  testWidgets('#757 FR-M3 the voice lands while M3 is open: the row names it, '
      'with no restart', (tester) async {
    final models = FakeModels();
    final downloads = FakeDownloads();
    await pump(
      tester,
      voiceInstalled: null,
      extra: <Override>[
        modelRepositoryProvider.overrideWithValue(models),
        modelDownloadsProvider.overrideWithValue(downloads),
      ],
    );
    expect(find.text(l10n.settingsVoicePhoneForSupertonic), findsOneWidget);

    models.voice = ModelStatus.ready;
    downloads.live[ModelRepository.voiceModel]!.add((
      phase: DownloadPhase.ready,
      progress: 1,
    ));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsVoiceSupertonic('Anna')), findsOneWidget);
  });

  testWidgets('#345 a change of theme keeps the list where it was', (
    tester,
  ) async {
    // The aurora drifts forever unless motion is reduced.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final theme = ValueNotifier<ThemeData>(AppTheme.light());
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          learnedStabilitiesProvider.overrideWith(
            (ref) async => const <double>[],
          ),
          translationModelProvider.overrideWith((ref) async => null),
          voiceInstalledProvider.overrideWith((ref) async => true),
        ],
        child: ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (_, value, _) => MaterialApp.router(
            theme: value,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(0));

    // Glass wraps the screen in its aurora, which builds the list anew.
    theme.value = AppTheme.glass();
    await tester.pumpAndSettle();
    expect(offset(), before);
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
    await pump(tester, model: downloadingModel());
    expect(find.text(l10n.settingsGroupDailyPlan), findsOneWidget);
    expect(find.byType(SgSurface), findsNothing);

    await pump(
      tester,
      model: downloadingModel(),
      chrome: AdaptiveChrome.cupertino,
    );
    expect(
      find.text(l10n.settingsGroupDailyPlan.toUpperCase()),
      findsOneWidget,
    );
    expect(find.byType(SgSurface), findsNWidgets(8));
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

  // The slider says its value, and its row's line opens with it too: the line
  // goes to a screen reader without it, so the value is heard once (#1190).
  for (final locale in supportedLocales) {
    testWidgets('#1190 a screen reader hears the retention and speech-rate '
        'values once, in ${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        stabilities: List<double>.filled(110, 10),
        locale: locale,
      );
      final t = lookupAppLocalizations(locale);
      for (final title in <String>[t.settingsRetention, t.settingsSpeed]) {
        final slider = tester.widget<SgSlider>(sliderFor(title));
        final value = slider.describe!(slider.value);
        final row = find.semantics
            .byLabel(RegExp(RegExp.escape(title)))
            .evaluate()
            .single;
        final heard = '${row.value} ${row.label}';
        expect(value.allMatches(heard), hasLength(1), reason: heard);
        // The rest of the line is still read, without the value's « · ».
        expect(row.label, isNot(equals(title)), reason: heard);
        expect(
          row.label
              .split('\n')
              .where((line) => line.trimLeft().startsWith('·')),
          isEmpty,
          reason: heard,
        );
      }
      semantics.dispose();
    });
  }

  // #1197: the speed takes the language's separator, as the line's own copy
  // does: «1,0× · … 0,75×» in Polish, not «1.0×» beside «0,75×».
  for (final (code, speed) in <(String, String)>[
    ('en', '1.0'),
    ('bn', '১.০'),
    ('pl', '1,0'),
    ('ru', '1,0'),
  ]) {
    testWidgets('#1197 the speech rate reads $speed× in $code', (tester) async {
      await pump(tester, locale: Locale(code));
      final t = lookupAppLocalizations(Locale(code));
      expect(find.text(t.settingsSpeedLine(speed)), findsOneWidget);
      final slider = tester.widget<SgSlider>(sliderFor(t.settingsSpeed));
      expect(slider.describe!(slider.value), '$speed×');
    });
  }

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

  test('FR-M3-01 BR-CONTENT-02 BR-CONTENT-04 #867 #886 sums over every word '
      'rated and not suspended that is revised: not a removed word or a '
      'note', () async {
    final content = ContentFixture.write(
      '${tempDir('sg_m3_course').path}/content.db',
    ).file;
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    // A row #630 made a lesson note after the learner had rated it.
    await db.customStatement(
      "UPDATE c.words SET kind = 'note' WHERE uid = '${ContentFixture.tuer}'",
    );
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, stability, reps) VALUES
  ('${ContentFixture.haus}', 'learning', 2.5, 1),
  ('custom:1', 'done', 30, 6),
  ('${ContentFixture.strasse}', 'suspended', 12, 3),
  ('custom:2', 'todo', 0, 0),
  ('${ContentFixture.tuer}', 'learning', 4, 2),
  ('uid-removed', 'done', 40, 5)
''');
    expect(await WordRepository(db, settings).learnedStabilities(), <double>[
      30,
      2.5,
    ]);
  });

  test("#409 M3's translation row reads the one build the manifest offers, "
      'Q4_K_M', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final support = tempDir('sogda_m3');
    final container = ProviderContainer(
      overrides: <Override>[
        modelRepositoryProvider.overrideWithValue(
          ModelRepository(settings, support: support),
        ),
      ],
    );
    addTearDown(container.dispose);
    final model = await container.read(translationModelProvider.future);
    expect(model!.variant.id, 'q4_k_m');
    expect(model.status, ModelStatus.notDownloaded);
  });

  testWidgets('#912 no tappable node wraps another', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(tapsInsideTaps(tester), isEmpty);
    semantics.dispose();
  });
}

/// FR-D3-04's documents (#1296): [bytes] of photos kept, and how many times
/// they were dropped. No disk: path_provider has no platform here.
class _Photos extends DocumentRepository {
  _Photos(AppDatabase db) : super(db, () => DateTime(2026, 10, 2));

  int bytes = 0;
  int drops = 0;

  @override
  Future<int> imageBytes({Directory? support}) async => bytes;

  @override
  Future<void> dropImages({Directory? support}) async {
    drops++;
    bytes = 0;
  }
}
