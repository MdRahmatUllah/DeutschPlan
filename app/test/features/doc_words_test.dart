import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/documents/matcher.dart';
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
  Future<GoRouter> pump(WidgetTester tester, List<Override> overrides) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/search/document/7',
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (_, _) => const Text('R1'),
          routes: <RouteBase>[
            GoRoute(
              path: 'document/:id',
              builder: (_, state) =>
                  DocWordsScreen(id: int.parse(state.pathParameters['id']!)),
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
    for (final element in find.byType(RichText).evaluate()) {
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
      find.semantics.byLabel(l10n.docWordsSemNew('fällt', 'A2')),
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

  testWidgets('an added word keeps its check on its line: a word joiner '
      '(agent-3 on #1294)', (tester) async {
    final joined = 'Nachzahlung${String.fromCharCode(0x2060)}';
    await pump(
      tester,
      docWordsStub(
        documents: FakeDocuments(added: <String>{uidOf('Nachzahlung')}),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText(includeSemanticsLabels: false).contains(joined),
      ),
      findsOneWidget,
    );
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

  testWidgets('a text with nothing new says so', (tester) async {
    await pump(
      tester,
      docWordsStub(documents: FakeDocuments(body: 'Ich bin hier.')),
    );
    expect(find.text(l10n.docWordsEmpty), findsOneWidget);
    expect(find.textContaining(l10n.docWordsAddAll(0)), findsNothing);
  });
}
