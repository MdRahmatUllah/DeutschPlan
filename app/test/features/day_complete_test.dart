import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/plan_repository.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/plan_engine.dart' show parsePlanDate;
import 'package:sogda/features/day_complete/day_complete_screen.dart';
import 'package:sogda/features/study/study_summary.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/features/today/today_view.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/core/components/sg_progress_ring.dart';
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

  GoRouter router({String? day}) => GoRouter(
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
        builder: (_, _) => DayCompleteScreen(day: day),
      ),
    ],
  );

  /// T6 over Today, the day's view being the artboard's: 17 words in 12
  /// minutes, a 13-day streak, tomorrow 12 revisions and 7 new.
  Future<void> pump(
    WidgetTester tester, {
    bool shownAlready = false,
    bool still = false,
    bool screenReader = false,
    TodayView? view,
    bool viewFails = false,
    String? day,
  }) async {
    if (still || screenReader) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
            disableAnimations: still,
            accessibleNavigation: screenReader,
          );
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
          todayViewProvider.overrideWith(
            (ref) async => viewFails
                ? throw StateError('the read failed')
                : view ?? artboardDone(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(day: day),
        ),
      ),
    );
    await tester.tap(find.text('T1 today'));
    await tester.runAsync(pumpEventQueue);
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

  testWidgets("#729 #1004 FR-T6-01 the words studied, not the plan's "
      'done: 17 done for the plan, 10 studied', (tester) async {
    await pump(tester, view: artboardDone(words: 10));
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text(l10n.dayCompleteStats(10, 12)), findsOneWidget);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
  });

  testWidgets('#853 the ring reads the count of the day, not "1 of 1"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    final day = artboardDone();
    expect(day.total, greaterThan(1));
    // The reward reads as one: the ring first.
    expect(
      tester.getSemantics(find.byType(SgProgressRing)).label,
      startsWith(l10n.todayRing(day.completed, day.total)),
    );
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
    semantics.dispose();
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

  testWidgets('#660 FR-T6-01 a session that crossed midnight goes straight '
      "to Today, and today's T6 is still to come", (tester) async {
    // Yesterday's plan, finished after midnight.
    await pump(tester, day: '2026-09-20');
    await tester.pumpAndSettle();
    expect(find.byType(DayCompleteScreen), findsNothing);
    expect(find.text('T1 today'), findsOneWidget);
    expect(await tester.runAsync(shown), isNull, reason: 'not claimed');
  });

  testWidgets('FR-T6-03 no share prompts, ads or upsells: one way out', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byType(SgButton), findsOneWidget);
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

  testWidgets('#689 TD-13 under a screen reader it stays until Back to '
      'Today: no time limit (WCAG 2.2.1)', (tester) async {
    await pump(tester, screenReader: true);
    await tester.pump(DayCompleteScreen.stay * 2);
    await tester.pumpAndSettle();
    expect(find.byType(DayCompleteScreen), findsOneWidget);
    await tester.tap(find.text(l10n.dayCompleteBack));
    await tester.pumpAndSettle();
    expect(find.text('T1 today'), findsOneWidget);
  });

  testWidgets('#689 TD-12 "Tag geschafft!" is German, read in a German '
      'voice', (tester) async {
    await pump(tester);
    final title = tester.widget<SgText>(
      find.byWidgetPredicate(
        (widget) => widget is SgText && widget.data == l10n.dayCompleteTitle,
      ),
    );
    expect(title.german, isTrue);
    await tester.pump(DayCompleteScreen.stay);
    await tester.pumpAndSettle();
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
    final directory = tempDir('sg_t6');
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

    // A day with something planned, all done (#942).
    await db.customStatement(
      'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, '
      "completed_at) VALUES ('$today', '${ContentFixture.haus}', 'revise', "
      "'A1.1', '${today}T08:00:00Z')",
    );
    final plans = PlanRepository(db);
    expect(await plans.dayCompleteShown(today), isFalse);
    expect(await dayDone(), isTrue);
    await plans.claimDayComplete(today);
    expect(await plans.dayCompleteShown(today), isTrue);
    expect(await dayDone(), isFalse);
  });

  test(
    '#328 BR-PLAN-02 a rest day offers no grammar, as Today shows none',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final directory = tempDir('sg_t6');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      await db.customStatement(
        "INSERT INTO grammar_state (grammar_uid, status, due) "
        "VALUES ('g1', 'learning', '$today')",
      );
      // Every day off but the one before today: today is a rest day.
      final off = 1 << (parsePlanDate(today).weekday - 1);
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A1.1', '2026-09-01', 7, ${127 & ~off})",
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
      final hold = container.listen(studyNextProvider(today), (_, _) {});
      addTearDown(hold.close);
      final next = await container.read(studyNextProvider(today).future);
      expect(next.grammar, isEmpty);
    },
  );

  test(
    '#328 BR-PLAN-10 grammar due keeps the day open, as Today counts it',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final directory = tempDir('sg_t6');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      await db.customStatement(
        "INSERT INTO grammar_state (grammar_uid, status, due) "
        "VALUES ('g1', 'learning', '$today')",
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
      final hold = container.listen(studyNextProvider(today), (_, _) {});
      addTearDown(hold.close);
      final next = await container.read(studyNextProvider(today).future);
      expect(next.grammar, <String>['g1']);
      expect(next.dayDone, isFalse);
    },
  );

  test('Z05 BR-CONTENT-02 BR-PLAN-10 a word a content update removed does '
      'not hold the day open: its row stays, T6 still comes', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final directory = tempDir('sg_t6');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    // Planned before the update took 'gone' out of the course; Haus done.
    // A day needs something planned and done to be one (#942).
    await db.customStatement(
      'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, '
      "completed_at) VALUES ('$today', 'gone', 'revise', 'A1.1', NULL), "
      "('$today', '${ContentFixture.haus}', 'revise', 'A1.1', "
      "'${today}T08:00:00Z')",
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
    final hold = container.listen(studyNextProvider(today), (_, _) {});
    addTearDown(hold.close);
    final next = await container.read(studyNextProvider(today).future);

    expect(next.revise, isEmpty, reason: 'no blank card to study');
    expect(next.dayDone, isTrue);
  });

  group(
    '#942 FR-T6-01 T6 follows T1: a study day, something planned, all done',
    () {
      Future<StudyNext> next({required int mask, required String rows}) async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final directory = tempDir('sg_t6');
        final content = ContentFixture.write('${directory.path}/content.db');
        await db.customStatement(
          "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
        );
        await db.customStatement(
          'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
          "study_days_mask) VALUES ('A1.1', '2026-09-01', 7, $mask)",
        );
        if (rows.isNotEmpty) {
          await db.customStatement(
            'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, '
            'completed_at) VALUES $rows',
          );
        }
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
        final hold = container.listen(studyNextProvider(today), (_, _) {});
        addTearDown(hold.close);
        return container.read(studyNextProvider(today).future);
      }

      final off = 1 << (parsePlanDate(today).weekday - 1);
      final done = "'${today}T08:00:00Z'";

      test('Revise anyway on a rest day, finished: no T6', () async {
        final result = await next(
          mask: 127 & ~off,
          rows: "('$today', '${ContentFixture.haus}', 'revise', 'A1.1', $done)",
        );
        expect(result.dayDone, isFalse);
      });

      test('a backlog session on a day with nothing planned: no T6', () async {
        final result = await next(
          mask: 127,
          rows:
              "('2026-09-20', '${ContentFixture.haus}', 'new', 'A1.1', $done)",
        );
        expect(result.dayDone, isFalse);
      });

      test("a study day's plan, all done: T6", () async {
        final result = await next(
          mask: 127,
          rows: "('$today', '${ContentFixture.haus}', 'revise', 'A1.1', $done)",
        );
        expect(result.dayDone, isTrue);
      });
    },
  );

  testWidgets('#677 FR-T6 a day that will not read goes on to Today, not a '
      'blank page', (tester) async {
    await pump(tester, viewFails: true);
    await tester.pumpAndSettle();
    expect(find.byType(DayCompleteScreen), findsNothing);
    expect(find.text('T1 today'), findsOneWidget);
  });
}
