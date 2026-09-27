import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/learn/step_detail_screen.dart';
import 'package:sogda/features/learn/step_words.dart';
import 'package:sogda/features/words/word_row.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/features/words/word_detail_screen.dart';

import '../core/text_clipping.dart';
import '../db/content_fixture.dart';
import 'today_fixtures.dart';
import 'word_fixtures.dart';

/// L2 · Words tab — #114.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  StepWord word(int i, {WordStatus status = WordStatus.todo, int? category}) {
    final base = artboardWords().first.word.word;
    return (
      meaning: 'meaning $i',
      word: WordWithState(
        word: base.copyWith(
          uid: 'w$i',
          german: 'Wort$i',
          categoryId: Value(category),
        ),
        state: null,
        status: status,
      ),
    );
  }

  List<String> germans(List<StepWord> rows) => <String>[
    for (final row in rows) row.word.word.german,
  ];

  group('FR-L2-02 the filters combine, status AND category', () {
    final words = <StepWord>[
      ...artboardWords(),
      word(0, status: WordStatus.suspended, category: 1),
    ];

    test('All keeps everything, a suspended word too', () {
      expect(filterWords(words, status: WordFilter.all), hasLength(7));
    });

    test('a status shows only its own', () {
      expect(germans(filterWords(words, status: WordFilter.learning)), <String>[
        'Mietvertrag',
        'Nebenkosten',
      ]);
      expect(germans(filterWords(words, status: WordFilter.todo)), <String>[
        'Kaution',
        'umziehen',
      ]);
    });

    test('and with a category, both must hold', () {
      expect(
        germans(filterWords(words, status: WordFilter.todo, category: 1)),
        <String>['Kaution'],
      );
      expect(filterWords(words, status: WordFilter.all, category: 2), isEmpty);
    });

    test('BR-CONTENT-04 a note is under All only: it has no status', () {
      final note = word(9);
      final rows = <StepWord>[
        ...words,
        (
          meaning: note.meaning,
          word: WordWithState(
            word: note.word.word.copyWith(kind: 'note'),
            state: null,
            status: WordStatus.todo,
          ),
        ),
      ];
      expect(
        germans(filterWords(rows, status: WordFilter.all)),
        contains('Wort9'),
      );
      expect(
        germans(filterWords(rows, status: WordFilter.todo)),
        isNot(contains('Wort9')),
      );
    });
  });

  late GoRouter routes;

  Future<void> pump(
    WidgetTester tester, {
    String code = 'A2.1',
    List<Override>? overrides,
    Locale? locale,
    TextScaler? textScaler,
  }) async {
    routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => StepDetailScreen(code: code),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides ?? todayStub(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// L2 without a database, over [words] instead of the artboard's.
  List<Override> over(List<StepWord> words) => <Override>[
    stepProgressProvider.overrideWith((ref) => Stream.value(artboardCourse())),
    stepWordsProvider.overrideWith((ref, code) => Stream.value(words)),
    stepCategoriesProvider.overrideWith(
      (ref, code) async => const <({int id, String name})>[
        (id: 1, name: 'Wohnen & Haushalt'),
      ],
    ),
    ...wordStub(),
  ];

  int rows(WidgetTester tester) => find.byType(WordRow).evaluate().length;

  Future<void> chip(WidgetTester tester, String label) async {
    // A filter chip, not a row's status chip with the same words.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is SgChip && w.kind == SgChipKind.filter && w.label == label,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("the artboard's six: headword, meaning and status", (
    tester,
  ) async {
    await pump(tester);
    expect(rows(tester), 6);
    expect(find.text('bill, invoice'), findsOneWidget);
    expect(find.text('Wohnen & Haushalt'), findsOneWidget);
  });

  bool wraps(WidgetTester tester) => tester
      .widget<ListView>(
        find.ancestor(
          of: find.byType(WordRow).first,
          matching: find.byType(ListView),
        ),
      )
      .shrinkWrap;

  testWidgets('#690 LQ-12 past 130 % a long list, with no prototype, fills '
      'the panel rather than shrink-wrap; a short one still ends at its last '
      'row (#282)', (tester) async {
    await pump(
      tester,
      overrides: over(<StepWord>[for (var i = 0; i < 40; i++) word(i)]),
      textScaler: const TextScaler.linear(1.5),
    );
    expect(wraps(tester), isFalse);
  });

  testWidgets('#690 LQ-12 and a short list at 150 %, or any at 100 %, wraps', (
    tester,
  ) async {
    await pump(
      tester,
      overrides: over(<StepWord>[for (var i = 0; i < 5; i++) word(i)]),
      textScaler: const TextScaler.linear(1.5),
    );
    expect(wraps(tester), isTrue);
  });

  testWidgets('#702 FR-L2-02 the filters hold across a trip to another '
      'inner tab and back', (tester) async {
    await pump(tester);
    await chip(tester, l10n.wordStatusLearning);
    await chip(tester, 'Wohnen & Haushalt');
    final filtered = rows(tester);
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.stepTabWords));
    await tester.pumpAndSettle();
    expect(rows(tester), filtered);
    expect(
      tester
          .widget<SgChip>(
            find.byWidgetPredicate(
              (w) =>
                  w is SgChip &&
                  w.kind == SgChipKind.filter &&
                  w.label == l10n.wordStatusLearning,
            ),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('FR-L2-02 the chips filter, and combine', (tester) async {
    await pump(tester);
    await chip(tester, l10n.wordStatusLearning);
    expect(rows(tester), 2);
    await chip(tester, l10n.wordStatusToDo);
    expect(rows(tester), 2);
    await chip(tester, 'Wohnen & Haushalt');
    expect(rows(tester), 1, reason: 'To do AND Wohnen & Haushalt');
    // A second tap lets the category go.
    await chip(tester, 'Wohnen & Haushalt');
    expect(rows(tester), 2);
    await chip(tester, l10n.stepFilterAll);
    expect(rows(tester), 6);
  });

  testWidgets('a filter that leaves nothing says so', (tester) async {
    await pump(tester, overrides: over(<StepWord>[word(1)]));
    await chip(tester, l10n.wordStatusDone);
    expect(rows(tester), 0);
    expect(find.text(l10n.stepWordsNone), findsOneWidget);
  });

  testWidgets('#314 at 200 % text nothing on L2 is cut: rows, chips and '
      'the inner tabs grow or scroll', (tester) async {
    textAt(tester, 2);
    await pump(tester);
    expectNothingClipped(tester, within: find.byType(StepDetailScreen));
    expect(
      tester.getSize(find.byType(WordRow).first).height,
      greaterThan(WordRow.height),
      reason: 'the row grows with its text',
    );
  });

  testWidgets('FR-L2-02 #550 at 200 % a long word stacks: its whole headword '
      'and meaning over its chips and speaker, its row taller than a short '
      "one's", (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    textAt(tester, 2);
    final long = word(1);
    await pump(
      tester,
      overrides: over(<StepWord>[
        word(0),
        (
          meaning: 'preventive check-up, to take part in a screening',
          word: WordWithState(
            word: long.word.word.copyWith(german: 'Vorsorgeuntersuchung'),
            state: null,
            status: WordStatus.todo,
          ),
        ),
      ]),
    );
    expect(tester.takeException(), isNull);
    final rows = find.byType(WordRow);
    expectAllLinesShown(tester, within: rows.at(1));
    expectNothingClipped(tester, within: rows);
    expectNoWordBroken(tester, within: rows);
    final headword = find.descendant(
      of: rows.at(1),
      matching: find.byType(SgHeadword),
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: rows.at(1),
              matching: find.byType(WordPlayButton),
            ),
          )
          .dy,
      greaterThanOrEqualTo(tester.getBottomLeft(headword).dy),
      reason: 'the chips and the speaker go under the words',
    );
    expect(
      tester.getSize(rows.at(1)).height,
      greaterThan(tester.getSize(rows.at(0)).height),
      reason: "no prototype holds a row to the first one's height",
    );
  });

  testWidgets('FR-L2-02 the list is built as it scrolls', (tester) async {
    await pump(
      tester,
      overrides: over(<StepWord>[for (var i = 0; i < 500; i++) word(i)]),
    );
    // Built rows, the cache around the viewport included.
    expect(
      find.byType(WordRow, skipOffstage: false).evaluate().length,
      lessThan(30),
    );
  });

  testWidgets('a row opens W1, and back finds the list where it was', (
    tester,
  ) async {
    await pump(
      tester,
      overrides: over(<StepWord>[for (var i = 0; i < 500; i++) word(i)]),
    );
    await tester.drag(find.byType(WordRow).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final first = tester
        .widgetList<WordRow>(find.byType(WordRow))
        .first
        .word
        .word
        .german;
    expect(first, isNot('Wort0'));
    await tester.tap(find.byType(WordRow).at(2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
      startsWith('w'),
    );
    // Closed by a tap on the scrim above the sheet.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(WordDetailView), findsNothing);
    expect(
      tester.widgetList<WordRow>(find.byType(WordRow)).first.word.word.german,
      first,
    );
  });

  for (final locale in <Locale>[Locale('bn'), Locale('en')]) {
    testWidgets('#815 FR-L2-02 a step not started, at 200 % on a 731 dp '
        'phone (${locale.languageCode}): every word can be scrolled to', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(411, 731) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        code: 'A1.1',
        overrides: over(<StepWord>[for (var i = 0; i < 30; i++) word(i)]),
        locale: locale,
        textScaler: const TextScaler.linear(2),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.byType(StartBanner), findsOneWidget);

      final last = find.byWidgetPredicate(
        (widget) => widget is WordRow && widget.word.word.uid == 'w29',
      );
      await tester.dragUntilVisible(
        last,
        find.byType(NestedScrollView),
        const Offset(0, -200),
      );
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('and after a trip to another tab', (tester) async {
    await pump(
      tester,
      overrides: over(<StepWord>[for (var i = 0; i < 500; i++) word(i)]),
    );
    await tester.drag(find.byType(WordRow).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    String top() =>
        tester.widgetList<WordRow>(find.byType(WordRow)).first.word.word.german;
    final first = top();
    await tester.tap(find.text(l10n.stepTabGrammar));
    await tester.pumpAndSettle();
    expect(find.byType(WordRow), findsNothing);
    await tester.tap(find.text(l10n.stepTabWords));
    await tester.pumpAndSettle();
    expect(top(), first);
  });

  testWidgets('a suspended word is greyed, not hidden', (tester) async {
    await pump(
      tester,
      overrides: over(<StepWord>[
        word(1),
        word(2, status: WordStatus.suspended),
      ]),
    );
    expect(rows(tester), 2);
    // By the meaning: the headword carries soft hyphens to break on.
    double opacity(String meaning) => tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.ancestor(
              of: find.text(meaning),
              matching: find.byType(WordRow),
            ),
            matching: find.byType(Opacity),
          ),
        )
        .fold(1, (value, widget) => value * widget.opacity);
    expect(opacity('meaning 2'), 0.5);
    expect(opacity('meaning 1'), 1);
    expect(find.text(l10n.wordStatusSuspended), findsOneWidget);
  });

  test("the category chips: the step's categories, the biggest first", () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final directory = tempDir('sg_categories');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    // A1.1 has Haus and Tür; a third word makes Arbeit (two words) bigger
    // than Essen (one), against both the id and the alphabet.
    await db.customStatement(
      "INSERT INTO c.categories (id, name) VALUES (2, 'Essen'), (3, 'Arbeit')",
    );
    await db.customStatement(
      'INSERT INTO c.words (uid, sublevel_code, level_code, seq, '
      'seq_in_sublevel, german, english, category_id, search_key, '
      "search_key_alt, kind) VALUES ('uid-buero', 'A1.1', 'A1', 3, 3, 'Büro', "
      "'office', 3, 'buero', 'buro', 'vocab')",
    );
    await db.customStatement(
      "UPDATE c.words SET category_id = 3 WHERE uid = '${ContentFixture.haus}'",
    );
    await db.customStatement(
      "UPDATE c.words SET category_id = 2 WHERE uid = '${ContentFixture.tuer}'",
    );
    expect(
      await ContentDao(db).stepCategories('A1.1'),
      <({int id, String name})>[
        (id: 3, name: 'Arbeit'),
        (id: 2, name: 'Essen'),
      ],
    );
  });

  testWidgets('no banner on the active step', (tester) async {
    await pump(tester);
    expect(find.byType(StartBanner), findsNothing);
  });

  testWidgets('FR-L2-03 a banner on a step that is not the active one', (
    tester,
  ) async {
    await pump(tester, code: 'A2.2');
    expect(find.text(l10n.stepStartBanner('A2.1', 'A2.2')), findsOneWidget);
    expect(find.text(l10n.stepStart), findsOneWidget);
  });

  testWidgets('FR-L2-03 Start: the current step completes today and this '
      'one opens, and the banner goes', (tester) async {
    late AppDatabase db;
    late SettingsRepository settings;
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = tempDir('sg_words');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A1.1', '2026-09-01', 7, 127)",
      );
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
      }
    }

    await pump(
      tester,
      code: 'A1.2',
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 24, 9)),
      ],
    );
    await settle();
    expect(find.text(l10n.stepStartBanner('A1.1', 'A1.2')), findsOneWidget);

    // Asked first, and Not now writes nothing.
    await tester.tap(find.text(l10n.stepStart));
    await tester.pumpAndSettle();
    expect(find.text(l10n.stepStartConfirmTitle('A1.2')), findsOneWidget);
    expect(find.text(l10n.stepStartConfirm('A1.1')), findsOneWidget);
    await tester.tap(find.text(l10n.stepStartCancel));
    await tester.pumpAndSettle();
    await settle();
    expect(find.byType(StartBanner), findsOneWidget);

    await tester.tap(find.text(l10n.stepStart));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.stepStart).last);
    await settle();

    final rows = await tester.runAsync(
      () => db
          .customSelect(
            'SELECT sublevel_code, completed_on FROM enrollments '
            'ORDER BY sublevel_code',
          )
          .get(),
    );
    expect(
      <(String, String?)>[
        for (final row in rows!)
          (
            row.read<String>('sublevel_code'),
            row.readNullable<String>('completed_on'),
          ),
      ],
      <(String, String?)>[('A1.1', '2026-09-24'), ('A1.2', null)],
    );
    expect(find.byType(StartBanner), findsNothing);
  });
}
