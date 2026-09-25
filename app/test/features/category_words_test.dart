import '../core/text_clipping.dart';

import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/categories_screen.dart';
import 'package:deutschplan/features/learn/category_words_screen.dart';
import 'package:deutschplan/features/learn/step_words.dart' show StepWord;
import 'package:deutschplan/features/words/word_row.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';

import '../db/content_fixture.dart';
import 'today_fixtures.dart';
import 'word_fixtures.dart';

/// L6 · Category words — #121.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late QuizArgs? quiz;

  Future<void> pump(
    WidgetTester tester, {
    int id = 1,
    List<CategoryProgress>? categories,
    List<StepWord>? words,
    Stream<List<StepWord>>? stream,
    ThemeData? theme,
  }) async {
    quiz = null;
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => CategoryWordsScreen(id: id),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) {
            quiz = state.extra as QuizArgs?;
            return const Scaffold(body: Text('L8'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope each pump: a test that pumps twice gets its overrides.
        key: UniqueKey(),
        overrides: <Override>[
          categoriesProvider.overrideWith(
            (ref) => Stream.value(categories ?? artboardCategories()),
          ),
          categoryWordsProvider.overrideWith(
            (ref, id) =>
                stream ?? Stream.value(words ?? artboardCategoryWords()),
          ),
          ...wordStub(),
        ],
        // A phone that composites blur, as the glass goldens have it.
        child: GlassCapabilityScope(
          notifier: GlassCapability.always(),
          child: MaterialApp.router(
            theme: theme ?? AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: routes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A row by its headword, which draws as rich text.
  Finder row(String german) => find.byWidgetPredicate(
    (widget) => widget is WordRow && widget.word.word.german == german,
  );

  CategoryProgress wohnen({int learning = 40, int done = 150}) =>
      CategoryProgress(
        id: 1,
        name: 'Wohnen & Haushalt',
        words: 412,
        todo: 412 - learning - done,
        learning: learning,
        done: done,
      );

  testWidgets('the header: the name, its words, its steps and its bar', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Wohnen & Haushalt'), findsOneWidget);
    expect(
      find.text(l10n.categoryWordsLine(412, 'A1.1 → B1.1')),
      findsOneWidget,
    );
    final bar = tester.widget<DpSegmentedBar>(find.byType(DpSegmentedBar));
    expect((bar.done, bar.learning, bar.todo), (150, 40, 222));
  });

  test('the steps: first → last in the list, one step alone', () {
    final rows = artboardCategoryWords();
    expect(stepRange(rows), 'A1.1 → B1.1');
    expect(stepRange(rows.take(2).toList()), 'A1.1');
  });

  testWidgets('FR-L6-01 rows keep the order the query gives, with their step '
      'and status chips', (tester) async {
    await pump(tester);
    final rows = tester.widgetList<WordRow>(find.byType(WordRow)).toList();
    expect(rows.map((row) => row.word.word.german), <String>[
      'Wohnung',
      'Schlüssel',
      'Küche',
      'Rechnung',
      'Mietvertrag',
      'Nebenkosten',
      'Wohngemeinschaft',
    ]);
    expect(rows.map((row) => row.step), <String>[
      'A1.1',
      'A1.1',
      'A1.2',
      'A2.1',
      'A2.1',
      'A2.1',
      'B1.1',
    ]);
    final kitchen = row('Küche');
    expect(
      find.descendant(of: kitchen, matching: find.text('A1.2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kitchen, matching: find.text(l10n.wordStatusDone)),
      findsOneWidget,
    );
  });

  testWidgets('#314 at 200 % text nothing on L6 is cut', (tester) async {
    textAt(tester, 2);
    await pump(tester);
    expectNothingClipped(tester, within: find.byType(CategoryWordsScreen));
  });

  testWidgets('the level chips: All · A1 · A2 · B1 · B2+', (tester) async {
    await pump(tester);
    final labels = tester
        .widgetList<DpChip>(
          find.byWidgetPredicate(
            (widget) => widget is DpChip && widget.kind == DpChipKind.filter,
          ),
        )
        .map((chip) => chip.label);
    expect(labels, <String>[l10n.stepFilterAll, 'A1', 'A2', 'B1', 'B2+']);

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<WordRow>(find.byType(WordRow))
          .map((row) => row.word.word.german),
      <String>['Rechnung', 'Mietvertrag', 'Nebenkosten'],
    );

    await tester.tap(find.text('B2+'));
    await tester.pumpAndSettle();
    expect(find.byType(WordRow), findsNothing);
    expect(find.text(l10n.stepWordsNone), findsOneWidget);

    await tester.tap(find.text(l10n.stepFilterAll));
    await tester.pumpAndSettle();
    expect(find.byType(WordRow), findsNWidgets(7));
  });

  test('B2+ holds B2, C1 and C2; each other chip its own level', () {
    StepWord at(String level) {
      final row = artboardCategoryWords().first;
      return (
        meaning: row.meaning,
        word: WordWithState(
          word: row.word.word.copyWith(levelCode: level),
          state: null,
          status: row.word.status,
        ),
      );
    }

    for (final level in <String>['B2', 'C1', 'C2']) {
      expect(LevelFilter.b2Plus.holds(at(level)), isTrue, reason: level);
      expect(LevelFilter.b1.holds(at(level)), isFalse, reason: level);
    }
    expect(LevelFilter.b2Plus.holds(at('B1')), isFalse);
    expect(LevelFilter.a1.holds(at('A1')), isTrue);
    expect(LevelFilter.a1.holds(at('A2')), isFalse);
    expect(LevelFilter.all.holds(at('C2')), isTrue);
  });

  testWidgets('the longest headword keeps to its 64 dp row', (tester) async {
    // content.db's longest: a C2.2 proverb, beside a step chip.
    const proverb =
        'Was du heute kannst besorgen, das verschiebe nicht auf morgen';
    final first = artboardCategoryWords().first;
    await pump(
      tester,
      words: <StepWord>[
        (
          meaning: 'never put off till tomorrow what you can do today',
          word: WordWithState(
            word: first.word.word.copyWith(
              german: proverb,
              article: const Value<String?>(null),
              sublevelCode: 'C2.2',
              levelCode: 'C2',
            ),
            state: null,
            status: first.word.status,
          ),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    final headword = find.descendant(
      of: row(proverb),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('Was du'),
      ),
    );
    expect(tester.getSize(headword).height, 24, reason: 'one 17/24 line');
    expect(
      tester.widget<RichText>(headword).overflow,
      TextOverflow.ellipsis,
      reason: 'cut with "…", not at a letter',
    );
    expect(tester.getSize(row(proverb)).height, WordRow.height);
  });

  testWidgets('#281 BR-STATUS-03 a suspended word stays on L6, with its '
      'Suspended chip', (tester) async {
    final rows = artboardCategoryWords();
    final kitchen = rows[2];
    await pump(
      tester,
      words: <StepWord>[
        ...rows.take(2),
        (
          meaning: kitchen.meaning,
          word: WordWithState(
            word: kitchen.word.word,
            state: kitchen.word.state,
            status: WordStatus.suspended,
          ),
        ),
        ...rows.skip(3),
      ],
    );
    expect(find.byType(WordRow), findsNWidgets(7));
    expect(
      find.descendant(
        of: row('Küche'),
        matching: find.text(l10n.wordStatusSuspended),
      ),
      findsOneWidget,
    );
  });

  testWidgets('#282 on glass the word list is one frosted panel: one blur '
      'for the list, the rows unfilled; on paper, rows as before', (
    tester,
  ) async {
    Finder listBlur() => find.descendant(
      of: find.byType(WordListPanel),
      matching: find.byType(BackdropFilter),
    );
    Color? fillOf(String german) =>
        (tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: row(german),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color;

    // The aurora drifts for ever: held still, as the glass goldens hold it.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester, theme: AppTheme.glass());
    expect(listBlur(), findsOneWidget, reason: 'one BackdropFilter, not seven');
    expect(fillOf('Wohnung'), isNull);
    expect(fillOf('Wohngemeinschaft'), isNull);
    // The panel ends at the last row, with the aurora clear below it.
    expect(
      tester
          .getBottomLeft(
            find.descendant(
              of: find.byType(WordListPanel),
              matching: find.byType(DpSurface),
            ),
          )
          .dy,
      moreOrLessEquals(
        tester.getBottomLeft(row('Wohngemeinschaft')).dy,
        epsilon: 2,
      ),
    );

    await pump(tester);
    expect(listBlur(), findsNothing);
    expect(fillOf('Wohnung'), isNotNull);
  });

  testWidgets('a row opens its word', (tester) async {
    await pump(tester);
    await tester.tap(row('Mietvertrag'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
      'cat-4',
    );
  });

  testWidgets('FR-L6-02 Quiz opens the quiz with source category(id)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    expect(quiz, isNotNull);
    expect(quiz!.source, 'category');
    expect(quiz!.sourceRef, '1');
    expect(quiz!.direction, 'deEn');
  });

  testWidgets(
    '#281 FR-L6-02 Quiz ends 18 from the edge, as the artboard has it: the '
    'bar\'s 8 and the link\'s own 10',
    (tester) async {
      await pump(tester);
      final end = tester.getTopRight(find.text(l10n.stepTabQuiz)).dx;
      expect(390 - end, 18);
    },
  );

  testWidgets('Quiz stays closed until ten of the words are learned', (
    tester,
  ) async {
    await pump(
      tester,
      categories: <CategoryProgress>[wohnen(learning: 4, done: 5)],
    );
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    expect(quiz, isNull);

    await pump(
      tester,
      categories: <CategoryProgress>[wohnen(learning: 4, done: 6)],
    );
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    expect(quiz?.sourceRef, '1');
  });

  testWidgets(
    '#281 FR-L6-01 words still loading: no header, no rows, and no "no '
    'words" yet',
    (tester) async {
      final never = StreamController<List<StepWord>>();
      addTearDown(never.close);
      await pump(tester, stream: never.stream);
      expect(tester.takeException(), isNull);
      expect(find.byType(DpSegmentedBar), findsNothing);
      expect(
        find.text(l10n.categoryWordsLine(412, 'A1.1 → B1.1')),
        findsNothing,
      );
      expect(find.byType(WordRow), findsNothing);
      expect(find.text(l10n.stepWordsNone), findsNothing);
    },
  );

  testWidgets(
    'FR-L6-01 a listed category whose rows come back empty: no header, and '
    'says so',
    (tester) async {
      // The category is listed but its rows are empty: a moment between the
      // two streams, which must not take the screen down.
      await pump(tester, words: const <StepWord>[]);
      expect(tester.takeException(), isNull);
      expect(find.byType(DpSegmentedBar), findsNothing);
      expect(find.text(l10n.stepWordsNone), findsOneWidget);
    },
  );

  testWidgets('a category with no words: no header, no Quiz, and says so', (
    tester,
  ) async {
    await pump(tester, id: 99, words: const <StepWord>[]);
    expect(find.byType(DpSegmentedBar), findsNothing);
    expect(find.text(l10n.stepWordsNone), findsOneWidget);
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    expect(quiz, isNull);
  });

  group('the rows, from the database', () {
    late Directory directory;
    late AppDatabase db;
    late SettingsRepository settings;
    late ProviderContainer container;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_category');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows releases it a moment later.
      }
    });

    Future<List<String>> meanings() async {
      final sub = container.listen(categoryWordsProvider(1), (_, _) {});
      addTearDown(sub.close);
      return <String>[
        for (final row in await container.read(categoryWordsProvider(1).future))
          row.meaning,
      ];
    }

    test('#281 BR-STATUS-03 a suspended word comes through, marked '
        'suspended', () async {
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: ContentFixture.tuer,
              status: const Value('suspended'),
            ),
          );
      final sub = container.listen(categoryWordsProvider(1), (_, _) {});
      addTearDown(sub.close);
      final rows = await container.read(categoryWordsProvider(1).future);
      expect(
        <(String, WordStatus)>[
          for (final row in rows) (row.word.word.german, row.word.status),
        ],
        <(String, WordStatus)>[
          ('Haus', WordStatus.todo),
          ('Tür', WordStatus.suspended),
          ('Straße', WordStatus.todo),
        ],
      );
    });

    test('meanings in English by default', () async {
      expect(await meanings(), <String>['house', 'door', 'street']);
    });

    test('in Bangla when the learner reads Bangla, English where the course '
        'has none', () async {
      await settings.write(SettingKeys.meaningLanguage, MeaningLanguage.bangla);
      await db.customStatement(
        "UPDATE c.words SET bangla = NULL WHERE uid = '${ContentFixture.strasse}'",
      );
      expect(await meanings(), <String>['বাড়ি', 'দরজা', 'street']);
    });
  });
}
