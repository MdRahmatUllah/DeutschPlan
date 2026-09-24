import 'dart:io';

import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/sentence_store.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/sentences/sentences_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';

import '../services/fake_tts.dart';

import '../db/content_fixture.dart';

/// T5 · Practice sentences — #110.
void main() {
  const today = '2026-09-21';
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;
  const strasse = ContentFixture.strasse;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;
  late FakeTts tts;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Three learned words, and today's three sentences already drawn:
  /// Straße's, then Haus's, then Tür's. [planOpen] leaves a plan row open,
  /// so the day is not complete.
  Future<void> open({bool planOpen = true, String? rated}) async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_sentences');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, stability, difficulty, reps,
  lapses, fsrs_state, last_review, due, card_mode)
VALUES
  ('$haus', 'learning', 4, 5, 2, 0, 2, '2026-09-15T08:00:00.000Z',
   '2026-09-25', 'plain'),
  ('$tuer', 'learning', 4, 5, 2, 0, 2, '2026-09-15T08:00:00.000Z',
   '2026-09-25', 'plain'),
  ('$strasse', 'learning', 4, 5, 2, 0, 2, '2026-09-15T08:00:00.000Z',
   '2026-09-25', 'plain')
''');
    await db.customStatement('''
INSERT INTO sentence_log (word_uid, ord, shown_on, self_rating) VALUES
  ('$strasse', 1, '$today', ${rated == strasse ? 3 : 'NULL'}),
  ('$haus', 1, '$today', NULL),
  ('$tuer', 1, '$today', NULL)
''');
    if (planOpen) {
      await db.customStatement(
        "INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) "
        "VALUES ('$today', '$haus', 'revise', 'A1.1')",
      );
    }
    settings = SettingsRepository(db);
    await settings.load();
  }

  GoRouter router() => GoRouter(
    initialLocation: '/today',
    routes: <RouteBase>[
      GoRoute(
        path: '/today',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/sentences'),
            child: const Text('T1 today'),
          ),
        ),
      ),
      GoRoute(path: '/sentences', builder: (_, _) => const SentencesScreen()),
      GoRoute(
        path: '/day-complete',
        builder: (_, _) => const Text('T6 day complete'),
      ),
    ],
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool planOpen = true,
    String? rated,
    bool voice = true,
  }) async {
    tts = FakeTts(voice: voice);
    await tester.runAsync(() => open(planOpen: planOpen, rated: rated));
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
          ttsProvider.overrideWithValue(tts),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
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
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SentencesScreen)),
    );
  }

  Future<void> answer(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    // The last answer reads the day's state before it leaves.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<Map<String, Object?>>> log() async => <Map<String, Object?>>[
    for (final row
        in await db
            .customSelect(
              'SELECT word_uid, self_rating FROM sentence_log ORDER BY rowid',
            )
            .get())
      row.data,
  ];

  /// The sentence showing: the page's RichText with the headword's span.
  Finder sentence(String text) => find.text(text, findRichText: true);

  group('FR-T5-01 the day\'s sentences', () {
    testWidgets('as drawn and kept in sentence_log, one at a time', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10n.sentencesPlace(1, 3)), findsOneWidget);
      expect(sentence('Die Straße ist lang.'), findsOneWidget);
    });

    testWidgets('stable on reopening, and resumed where it stopped', (
      tester,
    ) async {
      await pump(tester, rated: strasse);
      expect(find.text(l10n.sentencesPlace(2, 3)), findsOneWidget);
      expect(sentence('Das Haus ist groß.'), findsOneWidget);
    });

    testWidgets('the headword is underlined in its gender colour', (
      tester,
    ) async {
      await pump(tester);
      final rich = tester.widget<RichText>(sentence('Die Straße ist lang.'));
      TextSpan? target;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'Straße') target = span;
        return true;
      });
      expect(target?.style?.decoration, TextDecoration.underline);
      expect(target?.style?.decorationColor, DpPalette.light.die);
    });
  });

  group('FR-T5-02 the answers', () {
    testWidgets('Understood writes 3 and moves on', (tester) async {
      await pump(tester);
      await answer(tester, l10n.sentencesUnderstood);
      final rows = await tester.runAsync(log);
      expect(rows!.first, <String, Object?>{
        'word_uid': strasse,
        'self_rating': 3,
      });
      expect(find.text(l10n.sentencesPlace(2, 3)), findsOneWidget);
    });

    testWidgets('#312 a screen reader can answer: Understood by its tap '
        'action writes 3', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await tester.runAsync(() async {
        tester.semantics.tap(find.semantics.byLabel(l10n.sentencesUnderstood));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect((await tester.runAsync(log))!.first['self_rating'], 3);
      semantics.dispose();
    });

    testWidgets('Partly writes 2', (tester) async {
      await pump(tester);
      await answer(tester, l10n.sentencesPartly);
      expect((await tester.runAsync(log))!.first['self_rating'], 2);
    });

    testWidgets('BR-FSRS-04 Not yet writes 1 and rates the headword Hard', (
      tester,
    ) async {
      await pump(tester);
      await answer(tester, l10n.sentencesNotYet);
      expect((await tester.runAsync(log))!.first['self_rating'], 1);
      final review = await tester.runAsync(
        () => db
            .customSelect('SELECT word_uid, rating, source FROM review_log')
            .getSingle(),
      );
      expect(review!.data, <String, Object?>{
        'word_uid': strasse,
        'rating': 2,
        'source': 'sentence',
      });
    });

    testWidgets('a double tap on Not yet rates the word once', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.sentencesNotYet));
        await tester.tap(find.text(l10n.sentencesNotYet));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
      final reviews = await tester.runAsync(
        () => db.customSelect('SELECT 1 FROM review_log').get(),
      );
      expect(reviews, hasLength(1));
    });

    testWidgets('only Not yet touches the word', (tester) async {
      await pump(tester);
      await answer(tester, l10n.sentencesUnderstood);
      final reviews = await tester.runAsync(
        () => db.customSelect('SELECT 1 FROM review_log').get(),
      );
      expect(reviews, isEmpty);
    });
  });

  group('FR-T5-04 moving on', () {
    testWidgets('a swipe moves to the next sentence', (tester) async {
      await pump(tester);
      await tester.fling(
        sentence('Die Straße ist lang.'),
        const Offset(-400, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.sentencesPlace(2, 3)), findsOneWidget);
    });

    testWidgets('the last answer, the day not complete: back to Today', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 0; i < 3; i++) {
        await answer(tester, l10n.sentencesUnderstood);
      }
      expect(find.text('T1 today'), findsOneWidget);
    });

    testWidgets('the last answer completing the day: T6', (tester) async {
      await pump(tester, planOpen: false);
      for (var i = 0; i < 3; i++) {
        await answer(tester, l10n.sentencesUnderstood);
      }
      expect(find.text('T6 day complete'), findsOneWidget);
    });
  });

  group('FR-T5-03 a tapped word', () {
    testWidgets("a course word: its meaning, and the way to it", (
      tester,
    ) async {
      await pump(tester);
      await tester.runAsync(() async {
        await tester.tapOnText(find.textRange.ofSubstring('Straße'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
      expect(find.text('street'), findsOneWidget);

      await tester.tap(find.text(l10n.sentencesOpenWord));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
        strasse,
      );
    });

    testWidgets('a word the course lacks: Duden', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        await tester.tapOnText(find.textRange.ofSubstring('lang'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text(l10n.sentencesNotInCourse), findsOneWidget);
      expect(find.text(l10n.sentencesDuden), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('play speaks the sentence; a long-press, slowly', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said, <(String, double)>[
        ('Die Straße ist lang.', 1),
        ('Die Straße ist lang.', 0.75),
      ]);
    });

    testWidgets(
      'V01 no German voice: the speaker is slashed, and a tap says how to '
      'install one',
      (tester) async {
        await pump(tester, voice: false);
        expect(
          tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state,
          DpSpeakerState.unavailable,
        );
        expect(find.text(l10n.speakerNoVoice), findsNothing);

        await tester.tap(find.byType(DpSpeakerButton));
        await tester.pump();
        expect(find.text(l10n.speakerNoVoice), findsOneWidget);
      },
    );

    testWidgets('Show translation reveals the English', (tester) async {
      await pump(tester);
      expect(find.text('The street is long.'), findsNothing);
      await tester.tap(find.text(l10n.sentencesShowTranslation));
      await tester.pumpAndSettle();
      expect(find.text('The street is long.'), findsOneWidget);
    });

    testWidgets('the answers are Lime, Tangerine and Coral', (tester) async {
      await pump(tester);
      Color fill(String label) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: find.text(label),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(fill(l10n.sentencesUnderstood), DpPalette.light.easy);
      expect(fill(l10n.sentencesPartly), DpPalette.light.hard);
      expect(fill(l10n.sentencesNotYet), DpPalette.light.again);
    });
  });

  group('the data', () {
    setUp(() => open(rated: strasse));
    tearDown(() async {
      await settings.dispose();
      await db.close();
    });

    test('ratings(): where T5 picks up again', () async {
      expect(await DriftSentenceStore(db).ratings(today), <(String, int), int>{
        (strasse, 1): 3,
      });
    });

    test("FR-T5-03 a token's word: its key, or the longest key it starts "
        'with', () async {
      final dao = ContentDao(db);
      expect((await dao.wordForToken('strasse'))?.uid, strasse);
      expect((await dao.wordForToken('hausfrau'))?.uid, haus);
      expect(await dao.wordForToken('lang'), isNull);
      expect(await dao.wordForToken(''), isNull);
    });

    test('a short key only as itself: "in" does not claim "innen"', () async {
      await db.customStatement('''
INSERT INTO c.words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
  german, english, search_key, search_key_alt)
VALUES ('uid-in', 'A1.1', 'A1', 9, 9, 'in', 'in', 'in', 'in')
''');
      final dao = ContentDao(db);
      expect((await dao.wordForToken('in'))?.uid, 'uid-in');
      expect(await dao.wordForToken('innen'), isNull);
    });
  });
}
