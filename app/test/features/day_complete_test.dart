import 'dart:io';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/day_complete/day_complete_screen.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import 'today_fixtures.dart';

/// T6 · Day complete — #111.
void main() {
  const today = '2026-09-21';

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  GoRouter router() => GoRouter(
    initialLocation: '/today',
    routes: <RouteBase>[
      GoRoute(
        path: '/today',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/day-complete'),
            child: const Text('T1 today'),
          ),
        ),
      ),
      GoRoute(
        path: '/day-complete',
        builder: (_, _) => const DayCompleteScreen(),
      ),
    ],
  );

  /// T6 over Today, the day's view being the artboard's: 17 words in 12
  /// minutes, a 13-day streak, tomorrow 12 revisions and 7 new.
  Future<void> pump(
    WidgetTester tester, {
    bool shownAlready = false,
    bool still = false,
    TodayView? view,
  }) async {
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      if (shownAlready) {
        await db.customStatement(
          "INSERT INTO daily_stats (day, completed_shown) VALUES ('$today', 1)",
        );
      }
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 20)),
          todayViewProvider.overrideWith((ref) async => view ?? artboardDone()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(),
        ),
      ),
    );
    await tester.tap(find.text('T1 today'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    // The route builds, the day is claimed, and the next frame starts the
    // reward.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<int?> shown() async =>
      (await db
              .customSelect(
                "SELECT completed_shown FROM daily_stats WHERE day = '$today'",
              )
              .getSingleOrNull())
          ?.read<int>('completed_shown');

  testWidgets('the reward: the day, its streak, and tomorrow', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text(l10n.dayCompleteTitle), findsOneWidget);
    expect(find.text(l10n.dayCompleteStats(17, 12)), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text(l10n.dayCompleteStreak(13)), findsOneWidget);
    expect(find.text(l10n.dayCompleteTomorrow(12, 7)), findsOneWidget);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('FR-T6-01 shown, it is marked for the day', (tester) async {
    await pump(tester);
    expect(await tester.runAsync(shown), 1);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('FR-T6-01 and a second time the same day goes straight to '
      'Today', (tester) async {
    await pump(tester, shownAlready: true);
    await tester.pumpAndSettle();
    expect(find.byType(DayCompleteScreen), findsNothing);
    expect(find.text('T1 today'), findsOneWidget);
  });

  testWidgets('FR-T6-03 no share prompts, ads or upsells: one way out', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byType(DpButton), findsOneWidget);
    expect(find.text(l10n.dayCompleteBack), findsOneWidget);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('twenty paper-cut pieces fall once, over 1.2 s', (tester) async {
    await pump(tester);
    ConfettiPainter confetti() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<ConfettiPainter>()
        .single;
    expect(ConfettiPainter.pieces, hasLength(20));
    expect(confetti().progress, lessThan(0.2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(confetti().progress, inExclusiveRange(0.2, 1));
    await tester.pump(const Duration(milliseconds: 700));
    expect(confetti().progress, 1);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('and the ink check draws itself', (tester) async {
    await pump(tester);
    CheckPainter check() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CheckPainter>()
        .single;
    expect(check().progress, 0);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(check().progress, 1);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('FR-T6-03 reduced motion: no confetti, the check already '
      'drawn', (tester) async {
    await pump(tester, still: true);
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .toList();
    expect(painters.whereType<ConfettiPainter>(), isEmpty);
    expect(painters.whereType<CheckPainter>().single.progress, 1);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('back to Today after 4 s', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(DayCompleteScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('T1 today'), findsOneWidget);
  });

  testWidgets('or on a tap anywhere', (tester) async {
    await pump(tester);
    // Past the route's own entrance.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.text('T1 today'), findsOneWidget);
  });

  testWidgets('or Back to Today', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.tap(find.text(l10n.dayCompleteBack));
    await tester.pumpAndSettle();
    expect(find.text('T1 today'), findsOneWidget);
  });

  testWidgets('tomorrow a rest day says so', (tester) async {
    await pump(
      tester,
      view: artboardDone(
        tomorrow: const TomorrowPreview(
          revise: 0,
          newWords: 0,
          grammar: 0,
          estimate: Duration.zero,
          restDay: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text(l10n.dayCompleteTomorrowRest), findsOneWidget);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  test('FR-T6-01 the claim is one-shot', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final plans = PlanRepository(db);
    expect(await plans.claimDayComplete(today), isTrue);
    expect(await plans.claimDayComplete(today), isFalse);
    expect(await plans.claimDayComplete('2026-09-22'), isTrue);
  });

  test("FR-T6-01 on a day with ratings: the day's row is marked, its "
      'counts kept', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO daily_stats (day, new_done, reviews_done, seconds) "
      "VALUES ('$today', 7, 10, 720)",
    );
    final plans = PlanRepository(db);
    expect(await plans.claimDayComplete(today), isTrue);
    expect(await plans.claimDayComplete(today), isFalse);
    final row = await db
        .customSelect(
          'SELECT new_done, reviews_done, seconds, completed_shown '
          "FROM daily_stats WHERE day = '$today'",
        )
        .getSingle();
    expect(row.data, <String, Object?>{
      'new_done': 7,
      'reviews_done': 10,
      'seconds': 720,
      'completed_shown': 1,
    });
  });
  test('FR-T6-01 a day already celebrated is not done again: a later '
      'session ends on its summary, not T6', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    // The sentence picker reads the course's examples.
    final directory = Directory.systemTemp.createTempSync('dp_t6');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    Future<bool> dayDone() async {
      container.invalidate(studyNextProvider(today));
      final hold = container.listen(studyNextProvider(today), (_, _) {});
      addTearDown(hold.close);
      return (await container.read(studyNextProvider(today).future)).dayDone;
    }

    final plans = PlanRepository(db);
    expect(await plans.dayCompleteShown(today), isFalse);
    expect(await dayDone(), isTrue);
    await plans.claimDayComplete(today);
    expect(await plans.dayCompleteShown(today), isTrue);
    expect(await dayDone(), isFalse);
  });
}
