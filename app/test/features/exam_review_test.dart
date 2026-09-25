import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/exam/exam_review_screen.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_result_fixtures.dart';
import 'settings_fixtures.dart';
import 'today_fixtures.dart' show artboardTopic;

/// L14 · Exam review — #136 (`exam-results.md`, FR-L14-01). The review
/// fixture: the artboard paper's nine wrong, plus Q3, Q21, Q32 and Q36.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late int backs;
  late List<String> opened;

  const gender = (
    en: 'Every "-ung" noun is "die".',
    bn: 'প্রতিটি -ung বিশেষ্য "die"।',
  );

  Future<void> pump(
    WidgetTester tester, {
    ExamResult? result,
    StudyTip? tip = gender,
    MeaningLanguage meaning = MeaningLanguage.english,
  }) async {
    backs = 0;
    opened = <String>[];
    tester.view
      ..physicalSize = const Size(390, 900) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...examResultStub(StubExamResult(result: result ?? reviewResult())),
          settingsProvider.overrideWithValue(
            StubSettings()..put(SettingKeys.meaningLanguage, meaning),
          ),
          studyBackProvider.overrideWith(
            (ref, uid) async => (
              examples: <StudyExample>[
                (
                  german: 'Die Wohnung hat drei Zimmer.',
                  english: 'The flat has three rooms.',
                ),
              ],
              tip: tip,
            ),
          ),
          examReviewTopicProvider.overrideWith(
            (ref, uid) async => artboardTopic(),
          ),
          examGenderTopicProvider.overrideWith((ref) async => artboardTopic()),
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

  testWidgets('the filters count the paper: All · 40, Wrong only · 13, '
      'Flagged · 3', (tester) async {
    await pump(tester);
    expect(find.text(l10n.examReviewAll(40)), findsOneWidget);
    expect(find.text(l10n.examReviewWrong(13)), findsOneWidget);
    expect(find.text(l10n.examNavFlagged(3)), findsOneWidget);
    expect(find.text(header(1, l10n.examSectionVocabulary)), findsOneWidget);

    await tap(tester, l10n.examReviewWrong(13));
    expect(find.text(header(1, l10n.examSectionVocabulary)), findsNothing);
    expect(find.text(header(3, l10n.examSectionVocabulary)), findsOneWidget);

    await tap(tester, l10n.examNavFlagged(3));
    expect(find.text(header(3, l10n.examSectionVocabulary)), findsOneWidget);
    expect(find.text(header(9, l10n.examSectionVocabulary)), findsNothing);
  });

  testWidgets('FR-L14-01 a wrong word: the answers, its first example and '
      'Open word', (tester) async {
    await pump(tester);
    await tap(tester, l10n.examReviewWrong(13));
    expect(find.text(l10n.examReviewWrongOne), findsWidgets);
    expect(find.text('house'), findsOneWidget);
    expect(find.text('flat, apartment'), findsWidgets);
    expect(find.text('Die Wohnung hat drei Zimmer.'), findsWidgets);
    // Q3's, the first card.
    await tester.tap(find.text(l10n.examReviewOpenWord).first);
    await tester.pumpAndSettle();
    expect(opened, <String>['wohnung']);
  });

  testWidgets('FR-L14-01 an Articles question: its gender tip, and See rule '
      'opens the der/die/das topic', (tester) async {
    await pump(tester);
    await tap(tester, l10n.examReviewWrong(13));
    await tester.scrollUntilVisible(find.text('___ Rechnung'), 300);
    await tester.pumpAndSettle(); // its gender topic
    expect(find.text(gender.en), findsWidgets);
    await tester.tap(find.text(l10n.practiceSeeRule).first);
    await tester.pumpAndSettle();
    expect(find.text(artboardTopic().topic.topic), findsOneWidget);
  });

  testWidgets('an Articles question without a gender tip falls back to the '
      "word's example and Open word", (tester) async {
    await pump(tester, tip: (en: '"Chef" is the boss, not a cook.', bn: null));
    await tap(tester, l10n.examReviewWrong(13));
    await tester.scrollUntilVisible(find.text('___ Rechnung'), 300);
    await tester.pumpAndSettle(); // its gender topic
    expect(find.textContaining('boss'), findsNothing);
  });

  testWidgets('a Bangla learner reads the tip in Bangla', (tester) async {
    await pump(tester, meaning: MeaningLanguage.bangla);
    await tap(tester, l10n.examReviewWrong(13));
    await tester.scrollUntilVisible(find.text('___ Rechnung'), 300);
    await tester.pumpAndSettle(); // its gender topic
    expect(find.text(gender.bn), findsWidgets);
  });

  testWidgets('FR-L14-01 a grammar gap: its spaces and its rule', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.examReviewWrong(13));
    final gap = find.text('Wir gehen spazieren, ___ es regnet.');
    await tester.scrollUntilVisible(gap, 300);
    expect(find.text('obwohl'), findsOneWidget);
    expect(
      find.textContaining('To ask politely, use könnte or würde'),
      findsWidgets,
    );
  });

  testWidgets('an index answer shows its word; almost and no answer say so', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.examReviewWrong(13));
    await tester.scrollUntilVisible(find.text('die Wohnug'), 300);
    expect(find.text(l10n.examReviewAlmost), findsOneWidget);
    await tester.scrollUntilVisible(find.text(l10n.examReviewNoAnswer), 300);
    await tester.scrollUntilVisible(find.text('Ich habe gegangen.'), 300);
    expect(find.text('gegangen.'), findsOneWidget, reason: 'index 2, the word');
    expect(find.text('bin'), findsOneWidget);
  });

  testWidgets('a right card says so and shows no correction', (tester) async {
    await pump(tester);
    expect(find.text(header(1, l10n.examSectionVocabulary)), findsOneWidget);
    expect(find.text(l10n.examReviewRight), findsWidgets);
    expect(find.text('word 1'), findsNothing, reason: 'no "Correct" line');
  });

  testWidgets('a filter with nothing says so', (tester) async {
    final none = reviewResult();
    await pump(
      tester,
      result: (
        attempt: none.attempt,
        rows: <ExamResultRow>[
          for (final row in none.rows)
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
        missed: none.missed,
      ),
    );
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
