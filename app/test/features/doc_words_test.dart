import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart' show AdaptiveSwitch;
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/documents/matcher.dart';
import 'package:sogda/domain/documents/tokens.dart' show docMaxChars;
import 'package:sogda/features/documents/doc_import_screen.dart'
    show docMaxPages;
import 'package:sogda/features/documents/doc_words_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import 'doc_words_fixtures.dart';
import 'settings_fixtures.dart';

/// D2 · The words in your text (#1230): `doc-words.md`.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// D2 over R1, with R2 as a page that says what it was given.
  Future<GoRouter> pump(
    WidgetTester tester,
    List<Override> overrides, {
    String location = '/search/document/7',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (_, _) => const Text('R1'),
          routes: <RouteBase>[
            GoRoute(
              path: 'document/:id',
              builder: (_, state) => DocWordsScreen(
                id: int.parse(state.pathParameters['id']!),
                cut: state.uri.queryParameters['cut'],
              ),
            ),
            GoRoute(
              path: 'add',
              builder: (_, state) =>
                  Text('R2 ${state.uri.queryParameters['german']}'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  /// Where the [nth] [word] is drawn: found in the text as laid out, not
  /// in its labels («Nachzahlung, new, B1»), which `find.textRange` reads.
  Offset wordAt(WidgetTester tester, String word, [int nth = 0]) {
    for (final element
        in find.byWidgetPredicate((w) => w is RichText).evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
      var at = -1;
      for (var i = 0; i <= nth; i++) {
        at = text.indexOf(word, at + 1);
        if (at < 0) break;
      }
      if (at < 0) continue;
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: at, extentOffset: at + word.length),
          )
          .first;
      return paragraph.localToGlobal(box.toRect().center);
    }
    throw StateError('$word is not drawn');
  }

  /// The document's paragraph, the one that holds [word].
  RenderParagraph paragraphWith(WidgetTester tester, String word) =>
      tester.allRenderObjects.whereType<RenderParagraph>().firstWhere(
        (p) => p.text.toPlainText(includeSemanticsLabels: false).contains(word),
      );

  /// How many [icon]s are drawn: D2's marks are glyphs in its text (#1339).
  int marks(WidgetTester tester, IconData icon) => tester.allRenderObjects
      .whereType<RenderParagraph>()
      .map(
        (p) =>
            String.fromCharCode(icon.codePoint)
                .allMatches(p.text.toPlainText(includeSemanticsLabels: false))
                .length,
      )
      .fold(0, (a, b) => a + b);

  Future<void> longPressWord(WidgetTester tester, String word) async {
    await tester.longPressAt(wordAt(tester, word));
    await tester.pumpAndSettle();
  }

  Future<void> tapWord(WidgetTester tester, String word) async {
    await tester.tapOnText(find.textRange.ofSubstring(word).first);
    await tester.pumpAndSettle();
  }

  testWidgets('FR-D2-01 each lemma is marked by its class: new words by '
      'level, outside the course, mine; known words and stop words plain', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, docWordsStub());

    expect(
      find.semantics.byLabel(l10n.docWordsSemNew('Nachzahlung', 'B1')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(l10n.docWordsSemNew('kontrollieren', 'A2')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(l10n.docWordsSemOutside('Wasserzähler')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(l10n.docWordsSemOutside('Heizkörper')),
      findsNothing,
    );
    expect(
      find.semantics.byLabel(l10n.docWordsSemMine('Heizkörper')),
      findsOne,
    );
    // «überweisen» is done: plain. «die» is a stop word: never marked.
    expect(find.semantics.byLabel(RegExp('^überweisen, ')), findsNothing);
    expect(find.semantics.byLabel(RegExp('^die, ')), findsNothing);
    // The header counts them.
    final match = docMatch(artboardLetter);
    int count(DocClass c) => match.words.where((w) => w.docClass == c).length;
    expect(
      find.text(
        l10n.docWordsSummary(
          count(DocClass.newInCourse),
          count(DocClass.probablyKnown),
          count(DocClass.outside),
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('FR-D2-01 probably-known words are marked only while the '
      'switch is on', (tester) async {
    final semantics = tester.ensureSemantics();
    final settings = StubSettings();
    await pump(tester, docWordsStub(settings: settings));
    expect(
      find.semantics.byLabel(l10n.docWordsSemProbable('Hausmeister')),
      findsNothing,
    );

    await settings.write(SettingKeys.docShowProbablyKnown, true);
    await tester.pumpAndSettle();
    expect(
      find.semantics.byLabel(l10n.docWordsSemProbable('Hausmeister')),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('FR-D2-02 Add on a course word queues it with its sentence, '
      'and the toast says it starts today', (tester) async {
    final documents = FakeDocuments();
    final plan = FakePlan();
    await pump(tester, docWordsStub(documents: documents, plan: plan));

    await tapWord(tester, 'Nachzahlung');
    expect(find.text(l10n.docWordsCardInText), findsOneWidget);
    await tester.tap(find.text(l10n.docWordsCardAdd));
    await tester.pumpAndSettle();

    expect(plan.added.single, <String>[uidOf('Nachzahlung')]);
    expect(
      documents.recorded.single.sentence,
      'Bitte überweisen Sie die Nachzahlung bis zum 15. November auf unser '
      'Konto.',
    );
    expect(find.text(l10n.docWordsAddedToday('Nachzahlung')), findsOneWidget);
  });

  testWidgets('FR-D2-02 a word past today\'s slots says the day it starts', (
    tester,
  ) async {
    await pump(tester, docWordsStub(plan: FakePlan(slots: 0)));
    await tapWord(tester, 'Nachzahlung');
    await tester.tap(find.text(l10n.docWordsCardAdd));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.docWordsAddedFrom('Nachzahlung', 'Monday')),
      findsOneWidget,
    );
  });

  testWidgets('FR-D2-03 Add all new adds every new course word in one go, '
      'under the cap, and says how many start today', (tester) async {
    final plan = FakePlan(slots: 2);
    await pump(tester, docWordsStub(plan: plan));
    final fresh = docMatch(artboardLetter).words
        .where((w) => w.docClass == DocClass.newInCourse && !w.ambiguous)
        .length;
    expect(find.text(l10n.docWordsCapNote(5, fresh - 2)), findsOneWidget);

    await tester.tap(find.text(l10n.docWordsAddAll(fresh)));
    await tester.pumpAndSettle();
    expect(plan.added.single, hasLength(fresh));
    expect(find.text(l10n.docWordsAddedMany(fresh, 2)), findsOneWidget);
    expect(
      find.text(l10n.docWordsAddAll(fresh)),
      findsNothing,
      reason: 'all added',
    );
  });

  testWidgets('FR-D2-04 I know this is W1\'s Mark known, with its Undo', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final actions = FakeActions();
    await pump(tester, docWordsStub(actions: actions));
    await tapWord(tester, 'Nachzahlung');
    await tester.tap(find.text(l10n.docWordsCardKnow));
    await tester.pumpAndSettle();

    expect(actions.known, <String>[uidOf('Nachzahlung')]);
    expect(
      find.semantics.byLabel(l10n.docWordsSemNew('Nachzahlung', 'B1')),
      findsNothing,
    );
    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();
    expect(actions.undone, 1);
    expect(
      find.semantics.byLabel(l10n.docWordsSemNew('Nachzahlung', 'B1')),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('FR-D2-05 a word outside the course opens R2 with its German', (
    tester,
  ) async {
    await pump(tester, docWordsStub());
    await tapWord(tester, 'Wasserzähler');
    expect(find.text(l10n.docWordsCardOutside), findsOneWidget);
    await tester.tap(find.text(l10n.docWordsCardAddMine));
    await tester.pumpAndSettle();
    expect(find.text('R2 Wasserzähler'), findsOneWidget);
  });

  testWidgets('FR-D2-06 a word that is already mine keeps the sentence, and '
      'offers no second word', (tester) async {
    final documents = FakeDocuments();
    await pump(tester, docWordsStub(documents: documents));
    await tapWord(tester, 'Heizkörper');
    expect(find.text(l10n.docWordsCardMine), findsOneWidget);
    expect(find.text(l10n.docWordsCardAddMine), findsNothing);
    await tester.tap(find.text(l10n.docWordsCardKeepSentence));
    await tester.pumpAndSettle();
    expect(documents.recorded.single.wordKey, 'custom:4');
    expect(
      documents.recorded.single.sentence,
      startsWith('Er will die Heizkörper'),
    );
    expect(find.text(l10n.docWordsSentenceKept('Heizkörper')), findsOneWidget);
  });

  testWidgets('FR-D2-07 reopening runs the matcher again and shows what was '
      'added', (tester) async {
    final semantics = tester.ensureSemantics();
    final documents = FakeDocuments(added: <String>{uidOf('Nachzahlung')});
    await pump(tester, docWordsStub(documents: documents));
    expect(documents.runs, 1);
    expect(
      find.semantics.byLabel(l10n.docWordsSemAdded('Nachzahlung')),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('an ambiguous word asks which it is before Add', (tester) async {
    // «Morgen» is A1.1, so for this A2 learner probably known: shown with
    // the switch on.
    final settings = StubSettings()
      ..put(SettingKeys.docShowProbablyKnown, true);
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Morgen kommt der Hausmeister.'),
        settings: settings,
      ),
    );
    await tapWord(tester, 'Morgen');
    expect(find.text(l10n.docWordsCardWhich), findsOneWidget);
    expect(find.text(l10n.docWordsCardAdd), findsNothing);
    await tester.tap(find.textContaining('morgen · '));
    await tester.pumpAndSettle();
    expect(find.text(l10n.docWordsCardAdd), findsOneWidget);
  });

  testWidgets('an ambiguous word\'s readings say their step and meaning, '
      'and its mark takes the lowest level (agent-3 on #1294)', (tester) async {
    final semantics = tester.ensureSemantics();
    final settings = StubSettings()
      ..put(SettingKeys.docShowProbablyKnown, true);
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Am Montag fällt der Unterricht aus.'),
        settings: settings,
      ),
    );
    expect(
      find.semantics.byLabel(
        l10n.docWordsSemTwoReadings(l10n.docWordsSemNew('fällt', 'A2')),
      ),
      findsOne,
    );
    await tapWord(tester, 'fällt');
    expect(find.text(l10n.docWordsCardWhich), findsOneWidget);
    expect(find.textContaining('ausfallen · A2.2 · '), findsOneWidget);
    expect(find.textContaining('ausfallen · C1.1 · '), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a long press adds a new word at once, and a word added '
      'already is left alone (agent-3 on #1294)', (tester) async {
    final plan = FakePlan();
    await pump(tester, docWordsStub(plan: plan));
    await longPressWord(tester, 'Nachzahlung');
    expect(plan.added, <List<String>>[
      <String>[uidOf('Nachzahlung')],
    ]);
    // Past the toast, then again on the word now added.
    await tester.pump(const Duration(seconds: 3));
    await longPressWord(tester, 'Nachzahlung');
    expect(plan.added, hasLength(1));
  });

  testWidgets('FR-D2-03 an Add that starts today takes a slot off the cap '
      'note (agent-3 on #1294)', (tester) async {
    await pump(tester, docWordsStub(plan: FakePlan(slots: 2)));
    final fresh = docMatch(artboardLetter).words
        .where((w) => w.docClass == DocClass.newInCourse && !w.ambiguous)
        .length;
    expect(find.text(l10n.docWordsCapNote(5, fresh - 2)), findsOneWidget);
    await tapWord(tester, 'Nachzahlung');
    await tester.tap(find.text(l10n.docWordsCardAdd));
    await tester.pumpAndSettle();
    // One fewer to add, and one fewer slot: the same words wait.
    expect(find.text(l10n.docWordsCapNote(5, fresh - 1 - 1)), findsOneWidget);
  });

  testWidgets('FR-D2-03 a level button that would add what Add all does is '
      'left out (agent-3 on #1294)', (tester) async {
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Die Kündigung und die Nebenkosten.'),
      ),
    );
    expect(find.text(l10n.docWordsAddAll(2)), findsOneWidget);
    expect(find.text(l10n.docWordsAddLevel('A2', 2)), findsNothing);
  });

  for (final scale in <double>[1, 2]) {
    testWidgets('#1339 a check, a "?" and the My-word chip stay on their '
        "word's line, at every width, at ${(scale * 100).round()} %", (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        docWordsStub(
          documents: FakeDocuments(
            body:
                'Am Montag fällt der Unterricht aus. Die Nachzahlung für den '
                'Heizkörper kommt morgen.',
            added: <String>{uidOf('Nachzahlung')},
          ),
        ),
      );
      // The line a character is drawn on: its box's top, the line's own.
      double line(RenderParagraph paragraph, int at) => paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: at, extentOffset: at + 1),
            boxHeightStyle: BoxHeightStyle.max,
          )
          .first
          .top;
      // Every width a line can end at the word, the mark or the chip.
      for (var width = 240.0; width <= 520; width += 2) {
        tester.view.physicalSize = Size(width * 3, 2400);
        await tester.pump();
        final paragraph = paragraphWith(tester, 'Heizkörper');
        final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        for (final icon in <IconData>[Icons.check, Icons.help_outline]) {
          final at = text.indexOf(String.fromCharCode(icon.codePoint));
          expect(at, greaterThan(0), reason: '$icon is drawn');
          expect(
            line(paragraph, at),
            line(paragraph, at - 1),
            reason: '$icon at $width',
          );
        }
        final word = text.indexOf('Heizkörper');
        final chip = text.lastIndexOf(
          l10n.docWordsLegendMine.split(' ').first,
          word,
        );
        // Chip and word wider than a line (200 % on a narrow phone) break
        // where they must; anything narrower stays on one line.
        final together = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: chip - 1,
                extentOffset: word + 'Heizkörper'.length,
              ),
            )
            .fold(0.0, (sum, box) => sum + box.right - box.left);
        if (together <= paragraph.size.width) {
          expect(
            <double>[line(paragraph, chip), line(paragraph, word - 1)],
            everyElement(line(paragraph, word)),
            reason: 'the chip at $width',
          );
        }
        // Its outline goes round its label, wherever the text moved it.
        Offset centre(int at) => paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1),
            )
            .first
            .toRect()
            .center;
        final ends = <Offset>[
          centre(chip),
          centre(chip + l10n.docWordsLegendMine.length - 1),
        ];
        expect(
          paragraph,
          paints..something(
            (method, arguments) =>
                method == #drawRRect &&
                ends.every((arguments[0] as RRect).contains),
          ),
          reason: 'the outline at $width',
        );
      }
    });
  }

  testWidgets('#1339 #1344 FR-D2-01 a screen reader stops only where there '
      'is something to say: the marks and the chip are drawn, not read, and '
      'no stop is a lone space or full stop', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(added: <String>{uidOf('Nachzahlung')}),
      ),
    );
    final heard = RegExp(r'[\p{L}\p{N}]', unicode: true);
    expect(
      find.semantics.byPredicate(
        (node) => node.label.isNotEmpty && !heard.hasMatch(node.label),
      ),
      findsNothing,
    );
    for (final drawn in <String>[
      String.fromCharCode(Icons.check.codePoint),
      String.fromCharCode(Icons.help_outline.codePoint),
      l10n.docWordsLegendMine.replaceAll(' ', '\u00a0'),
    ]) {
      expect(
        find.semantics.byPredicate((node) => node.label.contains(drawn)),
        findsNothing,
        reason: drawn,
      );
    }
    // The words say it instead.
    expect(
      find.semantics.byLabel(l10n.docWordsSemAdded('Nachzahlung')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(l10n.docWordsSemMine('Heizkörper')),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('back from R2, the document is read again, the word now mine '
      '(agent-3 on #1294)', (tester) async {
    final documents = FakeDocuments();
    final router = await pump(tester, docWordsStub(documents: documents));
    expect(documents.runs, 1);
    await tapWord(tester, 'Wasserzähler');
    await tester.tap(find.text(l10n.docWordsCardAddMine));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(documents.runs, 2);
  });

  testWidgets('back from R2, the cap note counts the adds of today once '
      '(agent-3 on #1294)', (tester) async {
    final plan = FakePlan(slots: 2);
    final router = await pump(tester, docWordsStub(plan: plan));
    final fresh = docMatch(artboardLetter).words
        .where((w) => w.docClass == DocClass.newInCourse && !w.ambiguous)
        .length;
    await tapWord(tester, 'Nachzahlung');
    await tester.tap(find.text(l10n.docWordsCardAdd));
    await tester.pumpAndSettle();
    expect(find.text(l10n.docWordsCapNote(5, fresh - 2)), findsOneWidget);
    await tapWord(tester, 'Wasserzähler');
    await tester.tap(find.text(l10n.docWordsCardAddMine));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    // Read again: one slot left (the plan's), one fewer word.
    expect(find.text(l10n.docWordsCapNote(5, fresh - 2)), findsOneWidget);
  });

  testWidgets('the card bolds the word where it stands, not inside another '
      'word (agent-3 on #1294)', (tester) async {
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Die Kontonummer steht auf dem Konto.'),
        // Konto is A1: probably known to this A2 learner.
        settings: StubSettings()..put(SettingKeys.docShowProbablyKnown, true),
      ),
    );
    // The second «Konto»: the first is inside «Kontonummer».
    await tester.tapAt(wordAt(tester, 'Konto', 1));
    await tester.pumpAndSettle();
    final bold = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final spans = <InlineSpan>[];
      w.text.visitChildren((span) {
        spans.add(span);
        return true;
      });
      final at = spans.indexWhere(
        (s) => s is TextSpan && s.style?.fontWeight == FontWeight.w700,
      );
      return at > 0 &&
          (spans[at] as TextSpan).text == 'Konto' &&
          (spans[at - 1] as TextSpan).text!.endsWith('auf dem ');
    });
    expect(bold, findsOneWidget);
  });

  testWidgets('#1309 the switch is one node with its label once, and the '
      'legend a node of its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, docWordsStub());
    final toggle = tester.getSemantics(find.byType(AdaptiveSwitch));
    expect(toggle.label, l10n.docWordsShowProbablyKnown);
    expect(toggle.label, isNot(contains(l10n.docWordsLegendMine)));
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label.contains(l10n.docWordsLegendMine) &&
            !node.label.contains(l10n.docWordsShowProbablyKnown),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  for (final (name, plan, message) in <(String, FakePlan, String Function())>[
    ('all start today', FakePlan(), () => l10n.docWordsAddedManyToday(2)),
    (
      'none starts today',
      FakePlan(slots: 0),
      () => l10n.docWordsAddedManyLater(2),
    ),
    (
      'no day can be said',
      FakePlan(paused: true),
      () => l10n.docWordsAddedManyWaiting(2),
    ),
  ]) {
    testWidgets('#1311 FR-D2-03 a bulk add says what happened: $name', (
      tester,
    ) async {
      await pump(
        tester,
        docWordsStub(
          documents: FakeDocuments(body: 'Die Kündigung und die Nebenkosten.'),
          plan: plan,
        ),
      );
      await tester.tap(find.text(l10n.docWordsAddAll(2)));
      await tester.pump();
      expect(find.text(message()), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('#1333 an ambiguous word wears a "?" and says it has two '
      'readings, until a reading is added', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Am Montag fällt der Unterricht aus.'),
      ),
    );
    expect(marks(tester, Icons.help_outline), 1);

    await tapWord(tester, 'fällt');
    await tester.tap(find.textContaining('ausfallen · A2.2 · '));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docWordsCardAdd));
    await tester.pumpAndSettle();
    expect(marks(tester, Icons.help_outline), 0);
    expect(marks(tester, Icons.check), 1);
    // Settled: it says added, no longer two readings.
    expect(find.semantics.byLabel(l10n.docWordsSemAdded('fällt')), findsOne);
    await tester.pump(const Duration(seconds: 3));
    semantics.dispose();
  });

  testWidgets('#1333 a text with no ambiguous word has no "?"', (tester) async {
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(body: 'Die Kündigung und die Nebenkosten.'),
      ),
    );
    expect(marks(tester, Icons.help_outline), 0);
  });

  for (final (name, plan, note)
      in <(String, FakePlan, String Function(int later))>[
        (
          'a cap of 0',
          FakePlan(slots: 0, capZero: true),
          (later) => l10n.docWordsCapZero(later),
        ),
        (
          'the backlog pause',
          FakePlan(slots: 0, paused: true),
          (_) => l10n.docWordsHeldByBacklog,
        ),
      ]) {
    testWidgets('#1334 BR-PLAN-11 under $name the note says the words wait, '
        'never that they start later', (tester) async {
      await pump(tester, docWordsStub(plan: plan));
      final fresh = docMatch(artboardLetter).words
          .where((w) => w.docClass == DocClass.newInCourse && !w.ambiguous)
          .length;
      // No slot today, so every new word is one of the others.
      expect(find.text(note(fresh)), findsOneWidget);
      expect(find.text(l10n.docWordsCapNote(5, fresh)), findsNothing);
      expect(find.text(l10n.docWordsCapNote(0, fresh)), findsNothing);
    });
  }

  testWidgets("#1315 FR-D2-03 a word today's plan has already takes no slot "
      'in the cap note', (tester) async {
    await pump(
      tester,
      docWordsStub(
        plan: FakePlan(slots: 2, planned: <String>{uidOf('Nachzahlung')}),
      ),
    );
    final fresh = docMatch(artboardLetter).words
        .where((w) => w.docClass == DocClass.newInCourse && !w.ambiguous)
        .length;
    expect(find.text(l10n.docWordsCapNote(5, fresh - 1 - 2)), findsOneWidget);
  });

  for (final (cut, note) in <(String, String Function())>[
    ('text', () => l10n.docImportCut(docMaxChars)),
    ('pages', () => l10n.docImportTooManyPages(docMaxPages)),
  ]) {
    testWidgets('#1320 FR-D1-02 D2 says what D1 cut ($cut), once it is open', (
      tester,
    ) async {
      await pump(
        tester,
        docWordsStub(),
        location: '/search/document/7?cut=$cut',
      );
      expect(find.text(note()), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(note()), findsNothing, reason: 'once, then gone');
    });
  }

  testWidgets('a text with nothing new says so', (tester) async {
    await pump(
      tester,
      docWordsStub(documents: FakeDocuments(body: 'Ich bin hier.')),
    );
    expect(find.text(l10n.docWordsEmpty), findsOneWidget);
    expect(find.textContaining(l10n.docWordsAddAll(0)), findsNothing);
  });
}
