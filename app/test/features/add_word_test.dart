import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/search/add_word_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import '../core/text_clipping.dart' show AndroidTextScaler;

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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
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
  }) async {
    int? id;
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = Directory.systemTemp.createTempSync('dp_add_word');
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
                      builder: (_) => AddWordScreen(german: german, id: id),
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

  DpButton button(WidgetTester tester, String label) =>
      tester.widget<DpButton>(find.widgetWithText(DpButton, label));

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
      tester.getRect(find.byType(DpUmlautBar)).bottom,
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.addWordLogIt), findsNothing);
      await tester.pump(AddWordScreen.debounce);
      await settle(tester);
      expect(find.text(l10n.addWordLogIt), findsOneWidget);
    });
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
        await Future<void>.delayed(const Duration(milliseconds: 80));
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

    testWidgets('a double tap saves once', (tester) async {
      await pump(tester, german: 'Pfandflasche');
      await enter(tester, l10n.addWordMeaning, 'deposit bottle');
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.addWordSave));
        await tester.tap(find.text(l10n.addWordSave), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await settle(tester);
      final rows = await tester.runAsync(() => db.select(db.customWords).get());
      expect(rows, hasLength(1));
    });
  });

  group('edit mode', () {
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
    expect(find.byType(DpUmlautBar), findsNothing);
    await tester.tap(
      find.descendant(
        of: field(l10n.addWordGerman),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();
    expect(find.byType(DpUmlautBar), findsOneWidget);
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
