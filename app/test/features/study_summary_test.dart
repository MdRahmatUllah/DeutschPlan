import 'dart:io';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

import '../db/content_fixture.dart';

/// T3 · the session summary — #107.
void main() {
  const today = '2026-09-21';
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;
  const strasse = ContentFixture.strasse;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const words = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
      SessionBlock(SessionBlockKind.newWords, <String>[haus, tuer]),
    ],
  );
  const withGrammar = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
      SessionBlock(SessionBlockKind.grammar, <String>['g1']),
    ],
  );

  /// Today's plan, on a database that already has a day's worth of other
  /// reviews: FR-T3-01 counts the session, not the day.
  Future<void> open() async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_summary');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) VALUES
  ('$today', '$strasse', 'revise', 'A1.2'),
  ('$today', '$haus', 'new', 'A1.1'),
  ('$today', '$tuer', 'new', 'A1.1')
''');
    await db.customStatement('''
INSERT INTO daily_stats (day, new_done, reviews_done, seconds)
VALUES ('$today', 9, 12, 900)
''');
    settings = SettingsRepository(db);
    await settings.load();
    await settings.write(SettingKeys.autoplayHeadword, false);
  }

  /// The app's routes that T3 leads to, as plain pages.
  GoRouter router(SessionArgs args) => GoRouter(
    initialLocation: '/today',
    routes: <RouteBase>[
      GoRoute(
        path: '/today',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/study'),
              child: const Text('T1 today'),
            ),
          ),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'backlog',
            builder: (context, _) => TextButton(
              onPressed: () => context.push('/study'),
              child: const Text('T4 backlog'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/study',
        // T3's next block hands its own session (#328).
        builder: (_, state) =>
            StudyScreen(args: state.extra as SessionArgs? ?? args),
      ),
      GoRoute(
        path: '/learn',
        builder: (context, _) => TextButton(
          onPressed: () => context.push('/study'),
          child: const Text('L2 learn'),
        ),
      ),
      GoRoute(
        path: '/sentences',
        builder: (_, _) => const Text('T5 sentences'),
      ),
      GoRoute(
        path: '/day-complete',
        builder: (_, _) => const Text('T6 day complete'),
      ),
      GoRoute(
        path: '/grammar-practice',
        builder: (_, state) => Text(
          'L15 ${(state.extra! as GrammarPracticeArgs).topicUids.join(',')}',
        ),
      ),
    ],
  );

  /// The study screen over Today; [next] stands in for the day's state.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    SessionArgs args = words,
    StudyNext? next,
    FakeTts? tts,
    String? seed,
  }) async {
    await tester.runAsync(() async {
      await open();
      for (final statement in (seed ?? '').split(';')) {
        if (statement.trim().isNotEmpty) await db.customStatement(statement);
      }
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
          fakeVoice(tts ?? FakeTts()),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
          if (next != null)
            studyNextProvider(today).overrideWith((ref) async => next),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(args),
        ),
      ),
    );
    await tester.tap(find.text('T1 today'));
    await tester.pumpAndSettle();
    await tester.pump(StudyScreen.bannerTime);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(StudyScreen)));
  }

  /// Runs [act] against the session with its writes landing, then settles.
  Future<void> session(
    WidgetTester tester,
    ProviderContainer container,
    Future<void> Function(StudySession notifier) act, {
    SessionArgs args = words,
  }) async {
    await tester.runAsync(
      () => act(container.read(studySessionProvider(args).notifier)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  group('FR-T3-01 the counts are the session\'s own', () {
    testWidgets('cards, time and a pill per rating given', (tester) async {
      final container = await pump(tester);
      await session(tester, container, (n) async {
        await n.rate(Rating.again);
        await n.knewIt();
        await n.rate(Rating.good);
      });

      expect(find.byType(StudySummarySheet), findsOneWidget);
      expect(find.text(l10n.summaryTitle), findsOneWidget);
      // Three, although the day already holds 21.
      expect(find.text(l10n.summaryStats(3, 1)), findsOneWidget);
      expect(find.text(l10n.summaryPill(1, l10n.ratingAgain)), findsOneWidget);
      expect(find.text(l10n.summaryPill(1, l10n.ratingGood)), findsOneWidget);
      // I know it is an Easy rating (BR-STATUS-04).
      expect(find.text(l10n.summaryPill(1, l10n.ratingEasy)), findsOneWidget);
      expect(find.textContaining(l10n.ratingHard), findsNothing);
    });

    testWidgets('a skip is not a card done', (tester) async {
      final container = await pump(tester);
      await session(tester, container, (n) async {
        await n.rate(Rating.good);
        await n.skip();
        await n.rate(Rating.hard);
      });
      expect(find.text(l10n.summaryStats(2, 1)), findsOneWidget);
    });

    testWidgets('the words rated Again are the words to watch', (tester) async {
      final container = await pump(tester);
      await session(tester, container, (n) async {
        await n.rate(Rating.again);
        await n.rate(Rating.good);
        await n.rate(Rating.again);
      });
      expect(find.text(l10n.summaryWatch.toUpperCase()), findsOneWidget);
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
      expect(find.text('die Tür', findRichText: true), findsOneWidget);
      expect(find.text('das Haus', findRichText: true), findsNothing);
    });

    testWidgets('V01 a word to watch plays; with no German voice it says how '
        'to install one', (tester) async {
      final tts = FakeTts(voice: false);
      final container = await pump(tester, tts: tts);
      await session(tester, container, (n) async {
        await n.rate(Rating.again);
        await n.rate(Rating.again);
        await n.rate(Rating.again);
      });
      final play = find.byWidgetPredicate(
        (w) =>
            w is StudyPlayButton && w.label == l10n.summaryPlay('die Straße'),
      );
      await tester.ensureVisible(play);
      await tester.pumpAndSettle();
      await tester.tap(play);
      await tester.pump();
      expect(tts.spoken, <String>['die Straße']);
      expect(find.text(l10n.speakerNoVoice), findsOneWidget);
    });

    testWidgets('none rated Again: no words to watch', (tester) async {
      final container = await pump(tester);
      await session(tester, container, (n) async {
        for (var i = 0; i < 3; i++) {
          await n.rate(Rating.good);
        }
      });
      expect(find.text(l10n.summaryWatch.toUpperCase()), findsNothing);
    });
  });

  testWidgets('at most five words to watch', (tester) async {
    final uids = <String>[for (var i = 0; i < 7; i++) 'w$i'];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          for (final uid in uids)
            studyWordProvider(uid).overrideWith(
              (ref) async => WordWithState(
                word: Word(
                  uid: uid,
                  sublevelCode: 'A1.1',
                  levelCode: 'A1',
                  seq: 1,
                  seqInSublevel: 1,
                  article: 'das',
                  german: 'Wort$uid',
                  english: 'word',
                  searchKey: uid,
                  searchKeyAlt: uid,
                ),
                state: null,
                status: WordStatus.learning,
              ),
            ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StudySummarySheet(
                session: StudySessionState(
                  items: <StudyItem>[
                    for (final uid in uids)
                      StudyItem(SessionBlockKind.revise, uid),
                  ],
                  position: uids.length,
                  results: <int, CardOutcome>{
                    for (var i = 0; i < uids.length; i++) i: CardOutcome.again,
                  },
                ),
                next: null,
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StudyPlayButton), findsNWidgets(5));
    expect(find.text('das Wortw5', findRichText: true), findsNothing);
  });

  group('FR-T3-02 the next step', () {
    Future<void> finish(WidgetTester tester, StudyNext next) async {
      final container = await pump(tester, next: next);
      await session(tester, container, (n) async {
        for (var i = 0; i < 3; i++) {
          await n.rate(Rating.good);
        }
      });
    }

    DpButton button(WidgetTester tester, String label) =>
        tester.widget<DpButton>(find.widgetWithText(DpButton, label));

    final sentences = l10n0((l) => l.summarySentences(3));

    testWidgets('no sentences, no backlog: Done for now alone, and first', (
      tester,
    ) async {
      await finish(tester, StudyNext(sentences: 0, backlog: 0, dayDone: false));
      expect(find.byType(DpButton), findsOneWidget);
      expect(button(tester, l10n.summaryDone).kind, DpButtonKind.primary);
    });

    testWidgets('sentences open: they lead, and Done for now follows', (
      tester,
    ) async {
      await finish(tester, StudyNext(sentences: 3, backlog: 0, dayDone: true));
      expect(button(tester, sentences(l10n)).kind, DpButtonKind.primary);
      expect(button(tester, l10n.summaryDone).kind, DpButtonKind.text);
      expect(find.text(l10n.summaryBacklog(0)), findsNothing);
    });

    testWidgets('a backlog: second, under Done for now leading', (
      tester,
    ) async {
      await finish(
        tester,
        StudyNext(sentences: 0, backlog: 14, dayDone: false),
      );
      expect(button(tester, l10n.summaryDone).kind, DpButtonKind.primary);
      expect(
        button(tester, l10n.summaryBacklog(14)).kind,
        DpButtonKind.secondary,
      );
      expect(find.byType(DpButton), findsNWidgets(2));
    });

    testWidgets('both: sentences, then the backlog, then Done for now', (
      tester,
    ) async {
      await finish(
        tester,
        StudyNext(sentences: 3, backlog: 14, dayDone: false),
      );
      final order = <String>[
        for (final b in tester.widgetList<DpButton>(find.byType(DpButton)))
          b.label,
      ];
      expect(order, <String>[
        sentences(l10n),
        l10n.summaryBacklog(14),
        l10n.summaryDone,
      ]);
    });

    testWidgets('grammar still in the session comes first of all', (
      tester,
    ) async {
      final container = await pump(
        tester,
        args: withGrammar,
        next: StudyNext(sentences: 3, backlog: 0, dayDone: false),
      );
      await session(
        tester,
        container,
        (n) => n.rate(Rating.good),
        args: withGrammar,
      );
      final grammar = find.widgetWithText(DpButton, l10n.summaryGrammar(1));
      expect(tester.widget<DpButton>(grammar).kind, DpButtonKind.primary);

      await tester.tap(grammar);
      await tester.pumpAndSettle();
      expect(find.text('L15 g1'), findsOneWidget);
      expect(find.byType(StudyScreen), findsNothing);
    });

    test("#328 FR-T3-02 the order is the day's: revisions, new words, "
        'grammar, sentences', () {
      const none = StudySessionState(items: <StudyItem>[]);
      StudyNextStep step(StudyNext next) =>
          StudySummarySheet.primaryFor(none, next);
      expect(
        step(
          const StudyNext(
            sentences: 3,
            backlog: 0,
            dayDone: false,
            revise: <String>['r'],
            newWords: <String>['n'],
            grammar: <String>['g'],
          ),
        ),
        StudyNextStep.revise,
      );
      expect(
        step(
          const StudyNext(
            sentences: 3,
            backlog: 0,
            dayDone: false,
            newWords: <String>['n'],
            grammar: <String>['g'],
          ),
        ),
        StudyNextStep.newWords,
      );
      expect(
        step(
          const StudyNext(
            sentences: 3,
            backlog: 0,
            dayDone: false,
            grammar: <String>['g'],
          ),
        ),
        StudyNextStep.grammar,
        reason: "the day's grammar, which this session didn't queue",
      );
      expect(
        step(const StudyNext(sentences: 3, backlog: 0, dayDone: false)),
        StudyNextStep.sentences,
      );
    });

    testWidgets("#328 FR-T3-02 after a Revise-only session, the day's new "
        'words come next, and it continues with them', (tester) async {
      const revise = SessionArgs(
        planDate: today,
        blocks: <SessionBlock>[
          SessionBlock(SessionBlockKind.revise, <String>[strasse]),
        ],
      );
      final container = await pump(tester, args: revise);
      await session(
        tester,
        container,
        (n) => n.rate(Rating.good),
        args: revise,
      );
      final next = find.widgetWithText(DpButton, l10n.summaryNew(2));
      expect(tester.widget<DpButton>(next).kind, DpButtonKind.primary);

      await tester.tap(next);
      await tester.pumpAndSettle();
      final blocks = tester
          .widget<StudyScreen>(find.byType(StudyScreen))
          .args
          .blocks;
      expect(blocks.single.kind, SessionBlockKind.newWords);
      expect(
        find.byType(StudyScreen, skipOffstage: false),
        findsOneWidget,
        reason: "in the finished session's place, not over it",
      );
      expect(blocks.single.uids, <String>[haus, tuer]);
    });

    testWidgets("#328 FR-T3-02 the day's grammar after a Revise-only session: "
        'L15 opens on the topic due, which the session never queued', (
      tester,
    ) async {
      const revise = SessionArgs(
        planDate: today,
        blocks: <SessionBlock>[
          SessionBlock(SessionBlockKind.revise, <String>[strasse]),
        ],
      );
      final container = await pump(
        tester,
        args: revise,
        seed:
            "UPDATE plan_items SET completed_at = '2026-09-21T08:00:00Z' "
            "WHERE kind = 'new'; "
            'INSERT INTO grammar_state (grammar_uid, status, due) '
            "VALUES ('g1', 'learning', '$today')",
      );
      await session(
        tester,
        container,
        (n) => n.rate(Rating.good),
        args: revise,
      );
      final next = find.widgetWithText(DpButton, l10n.summaryGrammar(1));
      expect(tester.widget<DpButton>(next).kind, DpButtonKind.primary);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('L15 g1'), findsOneWidget);
    });

    testWidgets("#328 FR-T3-02 after a backlog session, the day's revisions "
        'come next, and it continues with them', (tester) async {
      const backlog = SessionArgs(
        planDate: today,
        blocks: <SessionBlock>[
          SessionBlock(SessionBlockKind.backlog, <String>[haus]),
        ],
      );
      final container = await pump(
        tester,
        args: backlog,
        seed:
            'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
            "VALUES ('2026-09-18', '$haus', 'new', 'A1.1')",
      );
      await session(
        tester,
        container,
        (n) => n.rate(Rating.good),
        args: backlog,
      );
      final next = find.widgetWithText(DpButton, l10n.summaryRevise(1));
      expect(tester.widget<DpButton>(next).kind, DpButtonKind.primary);

      await tester.tap(next);
      await tester.pumpAndSettle();
      final blocks = tester
          .widget<StudyScreen>(find.byType(StudyScreen))
          .args
          .blocks;
      expect(blocks.single.kind, SessionBlockKind.revise);
      expect(
        find.byType(StudyScreen, skipOffstage: false),
        findsOneWidget,
        reason: "in the finished session's place, not over it",
      );
      expect(blocks.single.uids, <String>[strasse]);
    });

    testWidgets('the sentences step opens T5 in the session\'s place', (
      tester,
    ) async {
      await finish(tester, StudyNext(sentences: 3, backlog: 0, dayDone: true));
      await tester.tap(find.text(sentences(l10n)));
      await tester.pumpAndSettle();
      expect(find.text('T5 sentences'), findsOneWidget);
      expect(find.byType(StudyScreen), findsNothing);
    });

    testWidgets('the backlog step opens T4', (tester) async {
      await finish(
        tester,
        StudyNext(sentences: 0, backlog: 14, dayDone: false),
      );
      await tester.tap(find.text(l10n.summaryBacklog(14)));
      await tester.pumpAndSettle();
      expect(find.text('T4 backlog'), findsOneWidget);
      expect(find.byType(StudyScreen), findsNothing);
    });

    testWidgets('Done for now goes back to Today', (tester) async {
      await finish(tester, StudyNext(sentences: 3, backlog: 0, dayDone: true));
      await tester.tap(find.text(l10n.summaryDone));
      await tester.pumpAndSettle();
      expect(find.text('T1 today'), findsOneWidget);
    });

    testWidgets('#345 Done for now goes to T1 from a session another screen '
        'opened: L2\'s *Study*', (tester) async {
      final container = await pump(
        tester,
        next: StudyNext(sentences: 3, backlog: 0, dayDone: true),
      );
      // Out of the session T1 opened, and into L2's.
      await tester.tap(find.bySemanticsLabel(l10n.studyClose));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('T1 today'))).go('/learn');
      await tester.pumpAndSettle();
      await tester.tap(find.text('L2 learn'));
      await tester.pumpAndSettle();
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
      await session(tester, container, (n) async {
        for (var i = 0; i < 3; i++) {
          await n.rate(Rating.good);
        }
      });
      await tester.tap(find.text(l10n.summaryDone));
      await tester.pumpAndSettle();
      expect(find.text('T1 today'), findsOneWidget);
      expect(find.text('L2 learn', skipOffstage: false), findsNothing);
    });

    testWidgets('each way out clears the session', (tester) async {
      final container = await pump(
        tester,
        next: StudyNext(sentences: 3, backlog: 0, dayDone: true),
      );
      await session(tester, container, (n) async {
        for (var i = 0; i < 3; i++) {
          await n.rate(Rating.good);
        }
      });
      await tester.tap(find.text(sentences(l10n)));
      await tester.pumpAndSettle();
      // Built again from the database, not the three results kept alive.
      final again = await tester.runAsync(
        () => container.read(studySessionProvider(words).future),
      );
      expect(again!.results, isEmpty);
    });
  });

  group('FR-T3-03 dragging the sheet down', () {
    Future<void> finish(WidgetTester tester) async {
      final container = await pump(
        tester,
        next: StudyNext(sentences: 3, backlog: 0, dayDone: true),
      );
      await session(tester, container, (n) async {
        for (var i = 0; i < 3; i++) {
          await n.rate(Rating.good);
        }
      });
    }

    testWidgets('is Done for now', (tester) async {
      await finish(tester);
      await tester.drag(find.text(l10n.summaryTitle), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('T1 today'), findsOneWidget);
    });

    testWidgets('a little way, and it settles back', (tester) async {
      await finish(tester);
      await tester.drag(find.text(l10n.summaryTitle), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.byType(StudySummarySheet), findsOneWidget);
    });
  });

  testWidgets('grammar alone: straight to L15, no summary of nothing', (
    tester,
  ) async {
    await tester.runAsync(open);
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    const grammarOnly = SessionArgs(
      planDate: today,
      blocks: <SessionBlock>[
        SessionBlock(SessionBlockKind.grammar, <String>['g1']),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          fakeVoice(FakeTts()),
          studyNextProvider(today).overrideWith(
            (ref) async => StudyNext(sentences: 3, backlog: 0, dayDone: true),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(grammarOnly),
        ),
      ),
    );
    await tester.tap(find.text('T1 today'));
    await tester.pumpAndSettle();
    expect(find.text('L15 g1'), findsOneWidget);
    expect(find.byType(StudySummarySheet), findsNothing);
  });

  testWidgets('the day complete and no sentences: T6, not the summary', (
    tester,
  ) async {
    final container = await pump(
      tester,
      next: StudyNext(sentences: 0, backlog: 14, dayDone: true),
    );
    await session(tester, container, (n) async {
      for (var i = 0; i < 3; i++) {
        await n.rate(Rating.good);
      }
    });
    expect(find.text('T6 day complete'), findsOneWidget);
    expect(find.byType(StudySummarySheet), findsNothing);
  });

  testWidgets('FR-T2-02 the last card\'s Undo works from under the summary', (
    tester,
  ) async {
    final container = await pump(
      tester,
      next: StudyNext(sentences: 3, backlog: 0, dayDone: false),
    );
    await session(tester, container, (n) async {
      await n.rate(Rating.good);
      await n.rate(Rating.good);
    });
    // The last card, rated through the screen so its undo bar shows.
    await tester.tap(find.text(l10n.studyShowMeaning));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.ratingGood));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byType(StudySummarySheet), findsOneWidget);
    expect(find.text(l10n.undo), findsOneWidget);

    // Tapped in the test's own zone: the bar's hide animation completes
    // there, not on the real event loop after the tree has gone.
    await tester.tap(find.text(l10n.undo));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StudySummarySheet), findsNothing);
    expect(
      container.read(studySessionProvider(words)).value?.current?.uid,
      tuer,
    );
    // Let the bar's own timer run out before the tree goes.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

/// A label that needs localisations, made later.
String Function(AppLocalizations) l10n0(
  String Function(AppLocalizations) make,
) => make;
