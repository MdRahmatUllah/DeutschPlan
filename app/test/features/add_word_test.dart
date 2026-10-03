import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/search_repository.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/plan_engine.dart' show DailyPlan;
import 'package:sogda/features/search/add_word_screen.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import '../core/text_clipping.dart' show AndroidTextScaler;
import '../db/content_fixture.dart';

/// R2 · Add / edit my word (#143, spec key R07): `add-word.md`, over the
/// content fixture (das Haus, die Tür in A1.1; die Straße in A1.2).
void main() {
  late AppLocalizations l10n;
  late AppDatabase db;
  late SettingsRepository settings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  /// R2 pushed over a page that says "R1", so a pop is seen. [seed] writes
  /// to the new database first and gives edit mode its word's id.
  Future<void> pump(
    WidgetTester tester, {
    String? german,
    Future<int> Function()? seed,
    Locale? locale,
    TextScaler? textScaler,
    bool edit = true,
    // D2's *Add as my word* (#1233, #1278).
    List<String> meanings = const <String>[],
    List<String> meaningsHere = const <String>[],
    String? example,
    String? where,
    WordRepository Function()? words,
    List<Override> overrides = const <Override>[],
  }) async {
    int? id;
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = tempDir('sg_add_word');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      id = await seed?.call();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          if (words != null)
            wordRepositoryProvider.overrideWith((_) => words()),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddWordScreen(
                        german: german,
                        id: edit ? id : null,
                        meanings: meanings,
                        meaningsHere: meaningsHere,
                        example: example,
                        where: where,
                      ),
                    ),
                  ),
                  child: const Text('R1'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('R1'));
    await tester.pumpAndSettle();
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
  );

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.enterText(
      find.descendant(of: field(label), matching: find.byType(TextField)),
      text,
    );
    await tester.pump(AddWordScreen.debounce);
    await settle(tester);
  }

  SgButton button(WidgetTester tester, String label) =>
      tester.widget<SgButton>(find.widgetWithText(SgButton, label));

  testWidgets('#691 EX-13 the German takes 80 characters, searched as R1 '
      'searches, and the meaning 200', (tester) async {
    await pump(tester);
    await enter(tester, l10n.addWordGerman, 'Haus' * 50);
    await enter(tester, l10n.addWordMeaning, 'house ' * 50);
    TextField at(String label) => tester.widget<TextField>(
      find.descendant(of: field(label), matching: find.byType(TextField)),
    );
    expect(
      at(l10n.addWordGerman).controller!.text,
      hasLength(SearchRepository.maxQueryLength),
    );
    expect(at(l10n.addWordMeaning).controller!.text, hasLength(200));
  });

  testWidgets('#590 in bn at 200 %, the keyboard up in SQA room, the German '
      "field focused sits under the status bar, not behind it: R2's list runs "
      'under it', (tester) async {
    // A word already in the course, so its match shows under the field, as
    // on the AddWord artboard: the reveal then scrolls the most.
    await pump(
      tester,
      german: 'Haus',
      locale: const Locale('bn'),
      textScaler: const AndroidTextScaler(2),
    );
    await tester.pump(AddWordScreen.debounce);
    await tester.pumpAndSettle();
    // Its meaning and where it was seen typed first, as the artboard has
    // them: the list scrolls down to them, and back up to the German.
    await tester.enterText(find.byType(TextField).at(1), 'house');
    await tester.enterText(find.byType(TextField).at(2), 'a sign');
    await tester.pumpAndSettle();
    tester.view
      ..padding = const FakeViewPadding(top: 24 * 3)
      // Gboard's top on SQA's 411 × 731 phone: 731 − 335.
      ..viewInsets = const FakeViewPadding(bottom: (844 - 396) * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final german = find.byType(TextField).first;
    await tester.showKeyboard(german);
    await tester.pumpAndSettle();
    final rect = tester.getRect(german);
    expect(rect.top, greaterThanOrEqualTo(24), reason: 'under the status bar');
    expect(rect.bottom, lessThanOrEqualTo(396), reason: 'above the keyboard');
  });

  testWidgets('#515 on focus, the German field scrolls up with its umlaut '
      'row and the next field above the keyboard', (tester) async {
    await pump(tester);
    // A short phone, and a keyboard with its suggestion bar: 290 dp left.
    tester.view.physicalSize = const Size(390, 640) * 3;
    await tester.pumpAndSettle();
    final german = find.descendant(
      of: field(l10n.addWordGerman),
      matching: find.byType(TextField),
    );
    await tester.tap(german);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 350 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const keyboardTop = 640.0 - 350;
    expect(tester.getRect(german).bottom, lessThanOrEqualTo(keyboardTop));
    expect(
      tester.getRect(find.byType(SgUmlautBar)).bottom,
      lessThanOrEqualTo(keyboardTop),
      reason: 'the umlaut row, whole',
    );
    final meaning = find.descendant(
      of: field(l10n.addWordMeaning),
      matching: find.byType(TextField),
    );
    expect(
      tester.getRect(meaning).bottom,
      lessThanOrEqualTo(keyboardTop),
      reason: 'and the next field',
    );
  });

  group('FR-R2-01 the live check', () {
    testWidgets('a course word says so, with its step and headword', (
      tester,
    ) async {
      await pump(tester);
      await enter(tester, l10n.addWordGerman, 'Haus');
      expect(find.text('${l10n.addWordInCourse('A1.1')} '), findsOneWidget);
      expect(find.text('das Haus', findRichText: true), findsOneWidget);
    });

    testWidgets('a word the course lacks shows nothing', (tester) async {
      await pump(tester);
      await enter(tester, l10n.addWordGerman, 'Pfandflasche');
      expect(find.text(l10n.addWordLogIt), findsNothing);
    });

    testWidgets('waits for the typing to stop', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.descendant(
          of: field(l10n.addWordGerman),
          matching: find.byType(TextField),
        ),
        'Haus',
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The database gets real time to answer, but the clock stands still:
      // settling would run it past the debounce.
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.addWordLogIt), findsNothing);
      await tester.pump(AddWordScreen.debounce);
      await settle(tester);
      expect(find.text(l10n.addWordLogIt), findsOneWidget);
    });
  });

  testWidgets('#694 CC-3 FR-R2-02 a Log it that fails to save says so; Retry '
      'logs it once', (tester) async {
    late _FailingWords words;
    await pump(
      tester,
      german: 'Haus',
      words: () => words = _FailingWords(db, settings),
    );
    await tester.tap(find.text(l10n.addWordLogIt));
    await settle(tester);
    expect(find.text(l10n.saveAnswerFailed), findsOneWidget);
    expect(find.text(l10n.addWordLogged('das Haus')), findsNothing);

    await tester.tap(find.text(l10n.retry));
    await settle(tester);
    expect(words.logged, 1);
    expect(find.text(l10n.addWordLogged('das Haus')), findsOneWidget);
  });

  testWidgets('FR-R2-02 Log it counts one more sighting, making the row as '
      'To do, and saves no word of my own', (tester) async {
    await pump(tester, german: 'Haus');
    Future<WordStateData?> haus() => tester
        .runAsync(
          () =>
              (db.select(db.wordState)
                    ..where((t) => t.wordUid.equals(ContentFixture.haus)))
                  .getSingleOrNull(),
        )
        .then((row) => row);

    await tester.tap(find.text(l10n.addWordLogIt));
    await settle(tester);
    expect((await haus())!.timesLogged, 1);
    expect((await haus())!.status, 'todo');
    expect(find.text(l10n.addWordLogged('das Haus')), findsOneWidget);

    await tester.tap(find.text(l10n.addWordLogIt));
    await settle(tester);
    expect((await haus())!.timesLogged, 2);
    expect(
      await tester.runAsync(() => db.select(db.customWords).get()),
      isEmpty,
    );
  });

  group('#669 FR-R2-01 a word already one of mine', () {
    Future<int> saved() => db
        .into(db.customWords)
        .insert(
          CustomWordsCompanion.insert(
            createdAt: '2026-09-20T10:00:00Z',
            german: 'Brötchen',
            meaning: 'bread roll',
            article: const Value('das'),
          ),
        );
    Future<List<CustomWord>> mine(WidgetTester tester) => tester
        .runAsync(() => db.select(db.customWords).get())
        .then((rows) => rows!);

    testWidgets('typed again, it says so with Open and Log it, and neither '
        'Save saves it twice', (tester) async {
      await pump(tester, german: 'Brötchen', seed: saved, edit: false);
      await tester.tap(find.bySemanticsLabel('das'));
      await tester.pump();
      await enter(tester, l10n.addWordMeaning, 'bread roll');
      expect(find.textContaining(l10n.searchNoneMine), findsOneWidget);
      expect(find.text(l10n.addWordOpen), findsOneWidget);
      expect(button(tester, l10n.addWordSave).onPressed, isNull);
      expect(button(tester, l10n.addWordSaveRevise).onPressed, isNull);
    });

    testWidgets('keyed as search keys it: another case, a bare vowel', (
      tester,
    ) async {
      await pump(tester, german: 'brotchen', seed: saved, edit: false);
      expect(find.textContaining(l10n.searchNoneMine), findsOneWidget);
    });

    /// [german] saved (with [article]), and then what [seed] saves; R2 over
    /// [typed] with [picked].
    Future<void> beside(
      WidgetTester tester, {
      required String german,
      String? article,
      required String typed,
      String? picked,
      Future<int> Function()? seed,
    }) async {
      await pump(
        tester,
        german: typed,
        edit: false,
        seed: () async {
          final id = await db
              .into(db.customWords)
              .insert(
                CustomWordsCompanion.insert(
                  createdAt: '2026-09-20T10:00:00Z',
                  german: german,
                  meaning: 'saved',
                  article: Value(article),
                ),
              );
          return await seed?.call() ?? id;
        },
      );
      if (picked != null) {
        await tester.tap(find.bySemanticsLabel(picked));
        await tester.pump();
      }
      await enter(tester, l10n.addWordMeaning, 'new');
    }

    for (final (saved, article, typed, picked)
        in <(String, String?, String, String?)>[
          ('schon', null, 'schön', null),
          ('zahlen', null, 'zählen', null),
          ('See', 'der', 'See', 'die'),
          ('Leiter', 'der', 'Leiter', 'die'),
        ]) {
      testWidgets('#841 ${[?picked, typed].join(' ')} beside '
          '${[?article, saved].join(' ')}: shown, and saved', (tester) async {
        await beside(
          tester,
          german: saved,
          article: article,
          typed: typed,
          picked: picked,
        );
        expect(find.textContaining(l10n.searchNoneMine), findsOneWidget);
        expect(button(tester, l10n.addWordSave).onPressed, isNotNull);
        expect(button(tester, l10n.addWordSaveRevise).onPressed, isNotNull);
        await tester.tap(find.text(l10n.addWordSave));
        await settle(tester);
        expect(await mine(tester), hasLength(2));
      });
    }

    testWidgets('#841 the same word is still refused: its key, spelt either '
        'way, and its article', (tester) async {
      await beside(
        tester,
        german: 'Tür',
        article: 'die',
        typed: 'Tuer',
        picked: 'die',
      );
      expect(button(tester, l10n.addWordSave).onPressed, isNull);
      expect(button(tester, l10n.addWordSaveRevise).onPressed, isNull);
    });

    testWidgets('#841 with schön and schon both saved, schön is refused', (
      tester,
    ) async {
      // My words list the newest first: schon, then schön.
      await beside(
        tester,
        german: 'schön',
        typed: 'schön',
        seed: () => db
            .into(db.customWords)
            .insert(
              CustomWordsCompanion.insert(
                createdAt: '2026-09-21T10:00:00Z',
                german: 'schon',
                meaning: 'already',
              ),
            ),
      );
      expect(button(tester, l10n.addWordSave).onPressed, isNull);
    });

    testWidgets('Log it counts one more sighting of it, and saves no second '
        'word', (tester) async {
      await pump(tester, german: 'Brötchen', seed: saved, edit: false);
      await tester.tap(find.text(l10n.addWordLogIt));
      await settle(tester);
      expect((await mine(tester)).single.timesSeen, 2);
      expect(find.text(l10n.addWordLogged('das Brötchen')), findsOneWidget);
    });
  });

  group('FR-R2-03 Save', () {
    testWidgets('waits for the German and the meaning', (tester) async {
      await pump(tester);
      expect(button(tester, l10n.addWordSave).onPressed, isNull);
      await enter(tester, l10n.addWordGerman, 'Pfandflasche');
      expect(button(tester, l10n.addWordSave).onPressed, isNull);
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      expect(button(tester, l10n.addWordSave).onPressed, isNotNull);
    });

    testWidgets('saves the word with its article, meaning and where seen, '
        'and goes back', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await tester.tap(find.bySemanticsLabel('das'));
      await tester.pump();
      await enter(tester, l10n.addWordMeaning, ' deposit bottle ');
      await enter(tester, l10n.addWordWhere, 'Rewe receipt');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);

      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      final row = rows!.single;
      expect(row.article, 'das');
      expect(row.german, 'Pfandflasche');
      expect(row.meaning, 'deposit bottle');
      expect(row.whereSeen, 'Rewe receipt');
      expect(row.example, isNull, reason: 'optional, and left empty');
      expect(row.matchedUid, isNull);
      expect(find.text('R1'), findsOneWidget, reason: 'back to R1');
    });

    String meaningField(WidgetTester tester) => tester
        .widget<TextField>(
          find.descendant(
            of: field(l10n.addWordMeaning),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    testWidgets('#1233 #1278 FR-D2-05 from a document: the German, its '
        'sentence and the document, and Hy-MT2\'s meanings offered, never '
        'filled in: the bare word\'s, then the sentence\'s as «here»', (
      tester,
    ) async {
      await pump(
        tester,
        german: 'Bänke',
        meanings: <String>['bench'],
        meaningsHere: <String>['on the benches'],
        example: 'Die Eltern saßen auf den Bänken.',
        where: 'Stadtnachrichten',
      );
      expect(meaningField(tester), isEmpty, reason: 'a suggestion only');
      expect(find.text('Stadtnachrichten'), findsOneWidget);
      expect(find.text(l10n.addWordMachineTranslated), findsOneWidget);
      expect(find.text('bench'), findsOneWidget);
      expect(
        find.text(l10n.addWordMeaningHere('on the benches')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('bench')).dx,
        lessThan(
          tester
              .getTopLeft(find.text(l10n.addWordMeaningHere('on the benches')))
              .dx,
        ),
        reason: "the bare word's first",
      );

      await tester.tap(find.text(l10n.addWordMeaningHere('on the benches')));
      await tester.pump();
      expect(meaningField(tester), 'on the benches', reason: 'the text alone');
      await tester.tap(find.text('bench'));
      await tester.pump();
      expect(meaningField(tester), 'bench');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);

      final row = (await tester.runAsync(
        () => db.select(db.customWords).get(),
      ))!.single;
      expect(row.meaning, 'bench');
      expect(row.example, 'Die Eltern saßen auf den Bänken.');
      expect(row.whereSeen, 'Stadtnachrichten');
      expect(row.mt, 1, reason: 'picked, machine-translated');
    });

    testWidgets('#1233 a sentence longer than the field comes in fitted, '
        'around its word, so the first edit there cuts nothing', (
      tester,
    ) async {
      const sentence =
          'Bitte reichen Sie bis zum 15. November die folgenden Unterlagen '
          'ein: eine Kopie des Personalausweises, die letzten drei '
          'Gehaltsabrechnungen, eine Bescheinigung über die Höhe der Miete '
          'und, falls vorhanden, den Bescheid über das Wohngeld sowie die '
          'Mietschuldenfreiheitsbescheinigung.';
      await pump(
        tester,
        german: 'Wohngeld',
        meanings: <String>['housing benefit'],
        example: sentence,
      );
      final example = find.descendant(
        of: field(l10n.addWordExample),
        matching: find.byType(TextField),
      );
      String text() => tester.widget<TextField>(example).controller!.text;
      final filled = text();
      expect(filled.length, lessThanOrEqualTo(AddWordScreen.fieldLength));
      expect(filled, contains('Wohngeld'));
      expect(filled, startsWith('…'));

      await enter(tester, l10n.addWordExample, '$filled!');
      expect(
        text(),
        filled.length < AddWordScreen.fieldLength ? '$filled!' : filled,
        reason: 'an edit keeps what was there',
      );
    });

    testWidgets('#1233 BR-DOC-07 a meaning the learner edits is theirs: the '
        'label goes, and it is saved as not machine-translated', (
      tester,
    ) async {
      await pump(tester, german: 'Bänke', meanings: <String>['bench']);
      await tester.tap(find.text('bench'));
      await tester.pump();
      await enter(tester, l10n.addWordMeaning, 'park bench');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final row = (await tester.runAsync(
        () => db.select(db.customWords).get(),
      ))!.single;
      expect(row.mt, 0);
    });

    testWidgets('#1233 from R1, with no suggestions: no chips, no label, '
        'and a meaning typed in is the learner\'s', (tester) async {
      await pump(tester, german: 'Bänke');
      expect(find.text(l10n.addWordMachineTranslated), findsNothing);
      await enter(tester, l10n.addWordMeaning, 'bench');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final row = (await tester.runAsync(
        () => db.select(db.customWords).get(),
      ))!.single;
      expect(row.mt, 0);
    });

    testWidgets('a word that is in the course keeps which one', (tester) async {
      await pump(tester, german: 'Haus');
      await enter(tester, l10n.addWordMeaning, 'house');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows!.single.matchedUid, ContentFixture.haus);
    });

    testWidgets('a match found for an earlier spelling is not kept', (
      tester,
    ) async {
      await pump(tester, german: 'Haus');
      await enter(tester, l10n.addWordMeaning, 'house slipper');
      // Changed, and saved before the check has caught up.
      await tester.enterText(
        find.descendant(
          of: field(l10n.addWordGerman),
          matching: find.byType(TextField),
        ),
        'Hausschuh',
      );
      await tester.pump();
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows!.single.german, 'Hausschuh');
      expect(rows.single.matchedUid, isNull);
    });

    testWidgets('a save that fails says so and stays', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await tester.runAsync(() => db.close());
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.addWordSave));
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(find.text(l10n.addWordSaveFailed), findsOneWidget);
      expect(find.byType(AddWordScreen), findsOneWidget);
    });

    testWidgets('Save and add to revision schedules it too, due today, and '
        'goes back (#363)', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await tester.ensureVisible(find.text(l10n.addWordSaveRevise));
      await tester.tap(find.text(l10n.addWordSaveRevise));
      await settle(tester);

      final id = (await tester.runAsync(
        () => db.select(db.customWords).getSingle(),
      ))!.id;
      final state = await tester.runAsync(
        () => (db.select(
          db.wordState,
        )..where((t) => t.wordUid.equals('custom:$id'))).getSingleOrNull(),
      );
      expect(state!.status, 'learning');
      expect(state.due, isNotNull);
      expect(
        find.text(l10n.addWordSavedRevise('Pfandflasche')),
        findsOneWidget,
      );
      expect(find.text('R1'), findsOneWidget, reason: 'back to R1');
    });

    testWidgets('#811 FR-R2-03 backed out of while Save and add to revision '
        "is still saving: the word is saved, and Today's plan read again", (
      tester,
    ) async {
      final gate = Completer<void>();
      var plans = 0;
      await pump(
        tester,
        german: 'Pfandflasche',
        words: () => _GatedWords(db, settings, gate.future),
        overrides: <Override>[
          todayPlanProvider.overrideWith((_) {
            plans++;
            return Completer<DailyPlan>().future;
          }),
        ],
      );
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AddWordScreen)),
      );
      container.listen(todayPlanProvider, (_, _) {});
      expect(plans, 1);

      await tester.ensureVisible(find.text(l10n.addWordSaveRevise));
      await tester.tap(find.text(l10n.addWordSaveRevise));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AddWordScreen), findsNothing, reason: 'left');

      await tester.runAsync(() async {
        gate.complete();
        await pumpEventQueue();
      });
      await settle(tester);

      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows, hasLength(1));
      container.read(todayPlanProvider);
      expect(plans, 2, reason: "Today's plan is read again");
    });

    testWidgets('a double tap saves once', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.addWordSave));
        await tester.tap(find.text(l10n.addWordSave), warnIfMissed: false);
        await pumpEventQueue();
      });
      await settle(tester);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows, hasLength(1));
    });
  });

  // #1263: Back never loses a word typed in; an untouched R2 just goes.
  group('#1263 FR-R2-03 leaving with text that is not saved', () {
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('untouched, Back leaves at once, the German from the search '
        'included', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await back(tester);
      expect(find.text('R1'), findsOneWidget);
      expect(find.text(l10n.addWordDiscardTitle), findsNothing);
    });

    testWidgets('typed in, Back asks; Keep editing stays with the text, Leave '
        'goes and saves nothing', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await back(tester);
      expect(find.text(l10n.addWordDiscardTitle), findsOneWidget);
      expect(find.text(l10n.addWordDiscardBody), findsOneWidget);

      await tester.tap(find.text(l10n.addWordDiscardKeep));
      await tester.pumpAndSettle();
      expect(find.byType(AddWordScreen), findsOneWidget);
      expect(find.text('deposit bottle'), findsOneWidget);

      await back(tester);
      await tester.tap(find.text(l10n.addWordDiscard));
      await settle(tester);
      expect(find.text('R1'), findsOneWidget);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows, isEmpty);
    });

    testWidgets("the header's back asks too, for any field and the article", (
      tester,
    ) async {
      await pump(tester);
      await enter(tester, l10n.addWordExample, 'Ich gebe die Flasche zurück.');
      await tester.tap(find.byType(AdaptiveBackButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.addWordDiscardTitle), findsOneWidget);
      await tester.tap(find.text(l10n.addWordDiscardKeep));
      await tester.pumpAndSettle();

      await enter(tester, l10n.addWordExample, '');
      await back(tester);
      expect(find.text('R1'), findsOneWidget, reason: 'emptied again');

      await tester.tap(find.text('R1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('der'));
      await tester.pump();
      await back(tester);
      expect(find.text(l10n.addWordDiscardTitle), findsOneWidget);
    });

    testWidgets('Save still goes back without asking', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      expect(find.text(l10n.addWordDiscardTitle), findsNothing);
      expect(find.text('R1'), findsOneWidget);
    });

    testWidgets('edit mode: the word as loaded leaves at once, a change asks', (
      tester,
    ) async {
      Future<int> saved() => db
          .into(db.customWords)
          .insert(
            CustomWordsCompanion.insert(
              createdAt: '2026-09-20T10:00:00Z',
              german: 'Quittung',
              meaning: 'receipt',
            ),
          );
      await pump(tester, seed: saved);
      expect(find.text('Quittung'), findsOneWidget);
      await back(tester);
      expect(find.text('R1'), findsOneWidget);

      await tester.tap(find.text('R1'));
      await tester.pumpAndSettle();
      await settle(tester);
      await enter(tester, l10n.addWordMeaning, 'receipt, till slip');
      await back(tester);
      expect(find.text(l10n.addWordDiscardTitle), findsOneWidget);
    });
  });

  group('edit mode', () {
    testWidgets('#1233 BR-DOC-07 a word saved machine-translated keeps its '
        'label while its meaning stands, and loses it once edited', (
      tester,
    ) async {
      await pump(
        tester,
        seed: () => db
            .into(db.customWords)
            .insert(
              CustomWordsCompanion.insert(
                createdAt: '2026-10-02T10:00:00Z',
                german: 'Bänke',
                meaning: 'benches',
                mt: const Value(1),
              ),
            ),
      );
      expect(find.text(l10n.addWordMachineTranslated), findsOneWidget);
      await enter(tester, l10n.addWordMeaning, 'park benches');
      expect(find.text(l10n.addWordMachineTranslated), findsNothing);
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final row = (await tester.runAsync(
        () => db.select(db.customWords).get(),
      ))!.single;
      expect(row.mt, 0);
    });

    Future<int> saved() => db
        .into(db.customWords)
        .insert(
          CustomWordsCompanion.insert(
            createdAt: '2026-09-20T10:00:00Z',
            german: 'Quittung',
            meaning: 'receipt',
            article: const Value('die'),
            whereSeen: const Value('Bäckerei'),
          ),
        );

    testWidgets('the word as saved, changed in place', (tester) async {
      await pump(tester, seed: saved);
      expect(find.text('Quittung'), findsOneWidget);
      expect(find.text('receipt'), findsOneWidget);
      expect(find.text('Bäckerei'), findsOneWidget);

      await enter(tester, l10n.addWordMeaning, 'receipt, till slip');
      await tester.tap(find.text(l10n.addWordSave));
      await settle(tester);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows, hasLength(1), reason: 'changed, not added');
      expect(rows!.single.meaning, 'receipt, till slip');
    });

    testWidgets('offers Save and add to revision until the word is in it '
        '(#363)', (tester) async {
      await pump(tester, seed: saved);
      expect(find.text(l10n.addWordSaveRevise), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.addWordSaveRevise));
      await tester.tap(find.text(l10n.addWordSaveRevise));
      await settle(tester);
      await tester.tap(find.text('R1'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AddWordScreen), findsOneWidget);
      expect(find.text(l10n.addWordSaveRevise), findsNothing);
    });

    testWidgets('Delete asks first, then the word goes', (tester) async {
      await pump(tester, seed: saved);
      await tester.ensureVisible(find.text(l10n.addWordDelete));
      await tester.tap(find.text(l10n.addWordDelete));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.addWordDeleteTitle('die Quittung')),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.addWordDeleteKeep));
      await settle(tester);
      expect(
        await tester.runAsync(() => db.select(db.customWords).get()),
        hasLength(1),
      );

      await tester.tap(find.text(l10n.addWordDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.addWordDelete).last);
      await settle(tester);
      expect(
        await tester.runAsync(() => db.select(db.customWords).get()),
        isEmpty,
      );
      expect(find.text('R1'), findsOneWidget);
    });
  });

  testWidgets('the umlaut row shows while the German field is typed in', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(SgUmlautBar), findsNothing);
    await tester.tap(
      find.descendant(
        of: field(l10n.addWordGerman),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();
    expect(find.byType(SgUmlautBar), findsOneWidget);
  });

  testWidgets("#390 R2's Raspberry stays behind the status bar when the form "
      'scrolls', (tester) async {
    await pump(tester);
    final scaffold = tester.widget<AdaptiveScaffold>(
      find
          .descendant(
            of: find.byType(AddWordScreen),
            matching: find.byType(AdaptiveScaffold),
          )
          .first,
    );
    expect(
      scaffold.statusBarColour,
      tester.element(find.byType(AddWordScreen)).tokens.color.die,
    );
  });
}

/// A *Log it* whose first write fails (#694).
class _FailingWords extends WordRepository {
  _FailingWords(super.db, super.settings);

  int failures = 1;
  int logged = 0;

  @override
  Future<void> logSighting(String uid) async {
    if (failures > 0) {
      failures--;
      throw StateError('disk I/O error');
    }
    logged++;
    await super.logSighting(uid);
  }
}

/// A save that waits for [gate]: the page can be left while it runs (#811).
class _GatedWords extends WordRepository {
  _GatedWords(super.db, super.settings, this.gate);

  final Future<void> gate;

  @override
  Future<int> saveMyWord(
    MyWordDraft word, {
    required DateTime now,
    int? id,
    String? matchedUid,
    String? reviseFrom,
  }) async {
    await gate;
    return super.saveMyWord(
      word,
      now: now,
      id: id,
      matchedUid: matchedUid,
      reviseFrom: reviseFrom,
    );
  }
}
