import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import '../services/fake_tts.dart';
import 'word_fixtures.dart';

/// W1 · Word detail (#140, spec key R04): `word-detail.md`.
void main() {
  late AppLocalizations l10n;
  late SettingsRepository settings;
  late FakeTts tts;
  String? went;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> openSettings(WidgetTester tester, AppDatabase db) async {
    await tester.runAsync(() async {
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
  }

  /// A page with a word to open, as every list row is, and W2 behind
  /// *Compare*.
  ///
  /// The opener sits in a shell with a tab bar, as every list in the app
  /// does, so the sheet has to rise over the bar rather than stop above it.
  GoRouter router(String uid) => GoRouter(
    routes: <RouteBase>[
      ShellRoute(
        builder: (_, _, child) => Scaffold(
          body: child,
          bottomNavigationBar: const SizedBox(height: 80, child: Text('tabs')),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: GestureDetector(
                    onTap: () => WordRoute.open(context, uid),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/compare/:uid',
        builder: (_, state) {
          went = state.uri.path;
          return const Scaffold(body: Text('W2'));
        },
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    WordDetail? detail,
    bool missing = false,
    Object? error,
    ReviewHistory history = artboardHistory,
    Size size = const Size(390, 844),
    double ratio = 3,
    ThemeData? theme,
    bool voice = true,
  }) async {
    tester.view
      ..physicalSize = size * ratio
      ..devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    went = null;
    tts = FakeTts(voice: voice);
    await openSettings(tester, AppDatabase.memory());
    final uid = detail?.word.uid ?? 'uid-strasse';

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(tts),
          todayProvider.overrideWithValue('2026-09-21'),
          wordDetailProvider.overrideWith(
            (ref, uid) => error != null
                ? Stream<WordDetail?>.error(error)
                : Stream.value(
                    missing ? null : detail ?? artboardWordDetail(uid: uid),
                  ),
          ),
          wordHistoryProvider.overrideWith((ref, uid) => Stream.value(history)),
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(uid),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('R04 the word', () {
    testWidgets('the header: article and headword, speaker, step, status', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
      expect(find.byType(DpSpeakerButton), findsOneWidget);
      expect(find.text('A1.1'), findsOneWidget);
      expect(find.text(l10n.wordStatusDone), findsOneWidget);
    });

    testWidgets('the caption, and the meanings in both languages', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Nomen · die Straße, -n · /স্ট্রাসে/'), findsOneWidget);
      expect(find.text('street, road'), findsOneWidget);
      expect(find.text('রাস্তা'), findsOneWidget);
    });

    testWidgets('an English learner reads the English only', (tester) async {
      await pump(
        tester,
        detail: artboardWordDetail(meaning: MeaningLanguage.english),
      );
      expect(find.text('street, road'), findsOneWidget);
      expect(find.text('রাস্তা'), findsNothing);
    });

    testWidgets('every example with its translation', (tester) async {
      await pump(tester);
      expect(find.text(l10n.wordExamples.toUpperCase()), findsOneWidget);
      expect(
        find.text('Die Straße ist wegen Bauarbeiten gesperrt.'),
        findsOneWidget,
      );
      expect(
        find.text('The street is closed because of roadworks.'),
        findsOneWidget,
      );
      expect(find.text('Wir wohnen in einer ruhigen Straße.'), findsOneWidget);
      expect(find.text('We live on a quiet street.'), findsOneWidget);
    });

    testWidgets('collocations and register in the note box', (tester) async {
      await pump(tester);
      expect(
        find.text(
          l10n.studyCollocations(
            'die Straße überqueren · auf der Straße · die Straße entlang',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.studyRegister('Gasse = narrow street · Weg = path, way'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the history caption', (tester) async {
      await pump(tester);
      expect(
        find.text('Next review in 8 days · reviewed 5 times · last: Good'),
        findsOneWidget,
      );
    });

    testWidgets('a word never reviewed has no history caption', (tester) async {
      await pump(tester, history: (reviews: 0, last: null));
      expect(find.textContaining('reviewed'), findsNothing);
    });
  });

  group('R04 sound', () {
    testWidgets('the speaker says the word with its article; a long-press '
        'at 0.75× (FR-T2-09)', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said, <(String, double)>[
        ('die Straße', 1),
        ('die Straße', 0.75),
      ]);
    });

    testWidgets('FR-W1-04 an example plays, and the sheet stays open', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Wir wohnen in einer ruhigen Straße.'));
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['Wir wohnen in einer ruhigen Straße.']);
      expect(find.byType(WordDetailView), findsOneWidget);
    });

    testWidgets('the speaker is its own button to a screen reader, not the '
        'whole header', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        tester.getSemantics(find.byType(DpSpeakerButton)),
        matchesSemantics(
          label: l10n.wordPronounce('die Straße'),
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('no German voice: the speaker is slashed', (tester) async {
      await pump(tester, voice: false);
      expect(
        tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state,
        DpSpeakerState.unavailable,
      );
    });

    testWidgets('?speak=1 plays the headword once it has loaded, and once '
        'only', (tester) async {
      tts = FakeTts();
      await openSettings(tester, AppDatabase.memory());
      final words = StreamController<WordDetail?>();
      addTearDown(words.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsProvider.overrideWithValue(settings),
            ttsProvider.overrideWithValue(tts),
            todayProvider.overrideWithValue('2026-09-21'),
            wordDetailProvider.overrideWith((ref, uid) => words.stream),
            wordHistoryProvider.overrideWith(
              (ref, uid) => Stream.value(artboardHistory),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const WordDetailScreen(uid: 'uid-strasse', speak: true),
          ),
        ),
      );
      await tester.pump();
      expect(tts.spoken, isEmpty, reason: 'nothing to say yet');

      words.add(artboardWordDetail());
      await tester.pumpAndSettle();
      // The same word again, as a rating re-emits it.
      words.add(artboardWordDetail(status: WordStatus.learning));
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['die Straße']);
    });
  });

  group('FR-W1-06 Compare', () {
    testWidgets('offered for a headword that names a set, and opens W2', (
      tester,
    ) async {
      await pump(
        tester,
        detail: artboardWordDetail(
          uid: 'uid-circa',
          article: null,
          german: 'circa / etwa / rund',
        ),
      );
      final link = find.text(l10n.wordCompare('circa / etwa / rund'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(went, '/compare/uid-circa');
    });

    testWidgets('not for a single word', (tester) async {
      await pump(tester);
      expect(find.textContaining('Compare'), findsNothing);
    });
  });

  group('R04 the header colours', () {
    DpTokens tokensOf(WidgetTester tester) =>
        tester.element(find.byType(WordDetailView)).tokens;

    testWidgets('on paper, the word takes its gender fill\'s ink', (
      tester,
    ) async {
      await pump(tester);
      final tokens = tokensOf(tester);
      expect(
        tester.widget<DpHeadword>(find.byType(DpHeadword)).colour,
        tokens.color.onPrimary,
      );
      final header = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byType(DpHeadword),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((header.decoration as BoxDecoration).color, tokens.color.die);
    });

    testWidgets('der on Cobalt reads in white', (tester) async {
      await pump(
        tester,
        detail: artboardWordDetail(article: 'der', german: 'Weg'),
      );
      expect(
        tester.widget<DpHeadword>(find.byType(DpHeadword)).colour,
        tokensOf(tester).color.onDer,
      );
    });

    testWidgets('a word with no article sits on Oat', (tester) async {
      await pump(tester, detail: artboardWordDetail(article: null));
      final header = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byType(DpHeadword),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (header.decoration as BoxDecoration).color,
        tokensOf(tester).surface.muted,
      );
    });

    testWidgets('under glass, the article keeps its own colour', (
      tester,
    ) async {
      await pump(tester, theme: AppTheme.glass());
      expect(tester.widget<DpHeadword>(find.byType(DpHeadword)).colour, null);
    });
  });

  group('R04 presentation', () {
    double top(WidgetTester tester) =>
        tester.getTopLeft(find.byType(WordDetailView)).dy;

    testWidgets('a phone: a sheet at the large detent, down to medium, and '
        'closed below it', (tester) async {
      await pump(tester);
      // Measured against the whole screen: the sheet is over the tab bar.
      expect(top(tester), closeTo(844 * (1 - WordDetailView.large), 1));
      expect(tester.getRect(find.byType(WordDetailView)).bottom, 844);

      await tester.timedDrag(
        find.text('die Straße', findRichText: true),
        const Offset(0, 250),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(top(tester), closeTo(844 * (1 - WordDetailView.medium), 1));

      await tester.timedDrag(
        find.text('die Straße', findRichText: true),
        const Offset(0, 300),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'the opener is back');
    });

    testWidgets('a tablet: a pane along the right edge; a tap beside it '
        'closes it', (tester) async {
      await pump(tester, size: const Size(1024, 768), ratio: 2);
      final pane = tester.getRect(find.byType(WordDetailView));
      expect(pane.right, 1024);
      expect(pane.width, 420);
      expect(pane.height, 768);

      await tester.tapAt(const Offset(100, 384));
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
    });
  });

  group('R04 states', () {
    testWidgets('a word the course does not have says so', (tester) async {
      await pump(tester, missing: true);
      expect(find.text(l10n.wordNotFound), findsOneWidget);
    });

    testWidgets('a failed query: the error panel and Retry', (tester) async {
      await pump(tester, error: StateError('disk'));
      expect(find.text(l10n.wordLoadFailed), findsOneWidget);
      expect(find.byType(DpErrorPanel), findsOneWidget);
    });
  });

  group('R04 historyCaption', () {
    WordWithState word({String? due, WordStatus status = WordStatus.done}) {
      final base = artboardWordDetail(status: status).word;
      return WordWithState(
        word: base.word,
        state: base.state!.copyWith(due: Value(due)),
        status: status,
      );
    }

    const today = '2026-09-21';
    const history = (reviews: 5, last: Rating.good);

    test('due today, or overdue', () {
      expect(
        historyCaption(word(due: today), history, today, l10n),
        'Due today · reviewed 5 times · last: Good',
      );
      expect(
        historyCaption(word(due: '2026-09-19'), history, today, l10n),
        startsWith('Due today'),
      );
    });

    test('tomorrow', () {
      expect(
        historyCaption(word(due: '2026-09-22'), history, today, l10n),
        startsWith('Next review tomorrow'),
      );
    });

    test('BR-STATUS-03 suspended: no next review', () {
      expect(
        historyCaption(
          word(due: '2026-09-29', status: WordStatus.suspended),
          (reviews: 1, last: Rating.again),
          today,
          l10n,
        ),
        'reviewed once · last: Again',
      );
    });

    test('never reviewed: nothing', () {
      expect(
        historyCaption(
          word(due: '2026-09-29'),
          (reviews: 0, last: null),
          today,
          l10n,
        ),
        isNull,
      );
    });
  });

  group('R04 over the database', () {
    testWidgets('the course\'s examples and tip; the status follows a '
        'rating while the sheet is open', (tester) async {
      final directory = Directory.systemTemp.createTempSync('deutschplan_w1');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      final db = AppDatabase.memory();
      await tester.runAsync(
        () => db.customStatement(
          "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
        ),
      );
      await openSettings(tester, db);
      tts = FakeTts();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            settingsProvider.overrideWithValue(settings),
            ttsProvider.overrideWithValue(tts),
            todayProvider.overrideWithValue('2026-09-21'),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: router(ContentFixture.strasse),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('open'));
      await settle();
      expect(find.text('Die Straße ist lang.'), findsOneWidget);
      expect(find.text('The street is long.'), findsOneWidget);
      expect(
        find.text(
          l10n.studyTip(
            tipText((
              en: 'Straße is die, not der.',
              bn: 'Straße হলো die।',
            ), settings.read(SettingKeys.meaningLanguage)),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.wordStatusToDo), findsOneWidget);

      await tester.runAsync(
        () => db
            .into(db.wordState)
            .insert(
              WordStateCompanion.insert(
                wordUid: ContentFixture.strasse,
                status: const Value('learning'),
                introducedOn: const Value('2026-09-21'),
                reps: const Value(1),
                stability: const Value(1),
                due: const Value('2026-09-22'),
              ),
            ),
      );
      await settle();
      expect(find.text(l10n.wordStatusLearning), findsOneWidget);
    });
  });
}
