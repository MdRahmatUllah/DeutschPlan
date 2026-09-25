import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/features/exam/exam_review_screen.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_result_fixtures.dart';
import 'today_fixtures.dart' show artboardTopic;

/// L14 · Exam review — #136 (`exam-results.md`, FR-L14-01).
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late int backs;
  late List<String> opened;

  Future<void> pump(WidgetTester tester, {StubExamResult? stub}) async {
    backs = 0;
    opened = <String>[];
    tester.view
      ..physicalSize = const Size(390, 900) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...examResultStub(stub),
          studyBackProvider.overrideWith(
            (ref, uid) async => (
              examples: <StudyExample>[
                (
                  german: 'Die Wohnung hat drei Zimmer.',
                  english: 'The flat has three rooms.',
                ),
              ],
              tip: (en: 'Every "-ung" noun is "die".', bn: null),
            ),
          ),
          examReviewTopicProvider.overrideWith(
            (ref, uid) async => artboardTopic(),
          ),
          examGenderTopicProvider.overrideWith(
            (ref, step) async => artboardTopic(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: ExamReviewView(
            attemptId: 7,
            onBack: () => backs++,
            onOpenWord: (_, uid) => opened.add(uid),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  String header(int number, String section) =>
      l10n.examReviewHeader(number, section).toUpperCase();

  testWidgets('the filters count the paper: All · 40, Wrong only · 9, '
      'Flagged · 3', (tester) async {
    await pump(tester);
    expect(find.text(l10n.examReviewAll(40)), findsOneWidget);
    expect(find.text(l10n.examReviewWrong(9)), findsOneWidget);
    expect(find.text(l10n.examNavFlagged(3)), findsOneWidget);
    expect(find.text(header(1, l10n.examSectionVocabulary)), findsOneWidget);

    await tap(tester, l10n.examReviewWrong(9));
    expect(find.text(header(1, l10n.examSectionVocabulary)), findsNothing);
    expect(
      find.text(header(9, l10n.examSectionVocabulary)),
      findsOneWidget,
      reason: 'Vocabulary scored 8 of 10: Q9 and Q10 are wrong',
    );

    await tap(tester, l10n.examNavFlagged(3));
    expect(find.text(header(3, l10n.examSectionVocabulary)), findsOneWidget);
    expect(find.text(header(9, l10n.examSectionVocabulary)), findsNothing);
  });

  testWidgets('FR-L14-01 a wrong word: the answers, its first example and '
      'Open word', (tester) async {
    await pump(tester);
    await tap(tester, l10n.examReviewWrong(9));
    expect(find.text(l10n.examReviewWrongOne), findsWidgets);
    expect(find.text('das Wort9'), findsOneWidget);
    expect(find.text('word 9'), findsOneWidget, reason: 'the right answer');
    expect(find.text('Die Wohnung hat drei Zimmer.'), findsWidgets);
    // Q9's, the first card.
    await tester.tap(find.text(l10n.examReviewOpenWord).first);
    await tester.pumpAndSettle();
    expect(opened, <String>['v9']);
  });

  testWidgets('FR-L14-01 an Articles question: its rule of thumb, and See '
      'rule opens the gender topic', (tester) async {
    await pump(tester);
    await tap(tester, l10n.examNavFlagged(3));
    await tester.scrollUntilVisible(find.text('___ Wohnung'), 300);
    expect(find.text('Every "-ung" noun is "die".'), findsOneWidget);
    await tester.tap(find.text(l10n.practiceSeeRule).last);
    await tester.pumpAndSettle();
    expect(find.text(artboardTopic().topic.topic), findsOneWidget);
  });

  testWidgets('FR-L14-01 a grammar question: its rule, in its first sentence', (
    tester,
  ) async {
    await pump(tester);
    final grammar = find.text(header(35, l10n.examSectionGrammar));
    await tester.scrollUntilVisible(grammar, 500);
    expect(
      find.textContaining('To ask politely, use könnte or würde'),
      findsWidgets,
    );
  });

  testWidgets('a filter with nothing says so', (tester) async {
    final none = StubExamResult();
    none.result0 = (
      attempt: none.result0.attempt,
      rows: <ExamResultRow>[
        for (final row in none.result0.rows)
          (
            ord: row.ord,
            item: row.item,
            given: row.given,
            points: row.points,
            rubric: row.rubric,
            flagged: false,
          ),
      ],
      previous: null,
      passPercent: 60,
      missed: none.result0.missed,
    );
    await pump(tester, stub: none);
    await tap(tester, l10n.examNavFlagged(0));
    expect(find.text(l10n.examReviewNone), findsOneWidget);
  });

  testWidgets('back, the button or the system, returns to L13', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backs, 2);
    semantics.dispose();
  });
}
