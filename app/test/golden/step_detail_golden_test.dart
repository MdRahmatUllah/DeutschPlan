// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/learn/step_detail_screen.dart';
import 'package:sogda/features/learn/step_words.dart';
import 'package:sogda/router/routes.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L2 · Step detail — #113. The header and the inner tabs; each tab's
/// contents arrive with #114, #115, #116 and M4.
void main() {
  // The StepDetail artboard: A2.1, started 19 Aug, 184 · 60 · 296.
  goldenTest(
    'step_detail',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1'),
    ),
  );

  // L10 · The ExamHub artboard (#127): A1.2, completed 18 Aug, on its Exams
  // tab — Mock 1 passed at 78 %, Mock 2 at 62 %, Mock 3 not sat.
  goldenTest(
    'exam_hub',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A1.2', tab: StepTab.exams),
    ),
  );

  // L10 locked · The ExamHubLocked artboard (#128): A2.1, current, its
  // mocks unlocking at 90 %.
  goldenTest(
    'exam_hub_locked',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.exams),
    ),
  );

  // The StepGrammar artboard: two due, two scheduled, six not learned.
  goldenTest(
    'step_grammar',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.grammar),
    ),
  );

  // The QuizSetup artboard under its sheet: the five tiles and the last
  // quiz, 16 / 20.
  goldenTest(
    'step_quiz',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.quiz),
    ),
  );

  // A step with fewer than ten learned words: the tiles closed, and why.
  goldenTest(
    'step_quiz_locked',
    modes: const <GoldenMode>[GoldenMode.light],
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.2', tab: StepTab.quiz),
    ),
  );

  // #1119: the Words tab with Russian first and English second.
  goldenTest(
    'step_detail_ru_meanings',
    builder: (context) => ProviderScope(
      overrides: todayStub(null, null, null, null, null, _russianWords()),
      child: const StepDetailScreen(code: 'A2.1'),
    ),
  );

  // A step that is not the active one: the Words tab's Start banner
  // (FR-L2-03) over the words.
  goldenTest(
    'step_detail_not_started',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.2'),
    ),
  );

  // iOS draws the tabs as a segmented control and centres the code in the
  // bar, with a labelled back chevron.
  goldenTest(
    'step_detail_ios',
    modes: const <GoldenMode>[GoldenMode.light, GoldenMode.dark],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1'),
    ),
  );
}

/// #1119: L2's artboard words with Russian first and English second.
List<StepWord> _russianWords() => withMeanings(
  const Meanings(
    MeaningChoice('ru', 'en'),
    CourseMeanings(<String, Map<String, WordMeaningText>>{
      'a21-0': <String, WordMeaningText>{
        'ru': (meaning: 'счёт', pronunciation: null),
      },
      'a21-1': <String, WordMeaningText>{
        'ru': (meaning: 'договор аренды', pronunciation: null),
      },
      'a21-2': <String, WordMeaningText>{
        'ru': (meaning: 'коммунальные платежи', pronunciation: null),
      },
      'a21-3': <String, WordMeaningText>{
        'ru': (meaning: 'арендодатель', pronunciation: null),
      },
      'a21-4': <String, WordMeaningText>{
        'ru': (meaning: 'залог', pronunciation: null),
      },
      'a21-5': <String, WordMeaningText>{
        'ru': (meaning: 'переезжать', pronunciation: null),
      },
    }),
  ),
  <WordWithState>[for (final row in artboardWords()) row.word],
);
