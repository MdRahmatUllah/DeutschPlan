/// `docs/03-domain/exam-generator.md` (Grading on submit) and
/// `exam-writing-speaking.md`: a mock exam's points, item by item (#84).
///
/// Plain Dart: no Flutter, no drift. `ExamRepository.grade` feeds it the
/// stored rows and writes back what it returns.
library;

import 'dart:convert';

import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart' show GapFill;
import 'package:deutschplan/domain/text_norm.dart';

/// BR-ANS-04: correct 1, almost 0.5, anything else 0.
double verdictPoints(Verdict verdict) => switch (verdict) {
  Verdict.correct => 1,
  Verdict.almost => 0.5,
  Verdict.wrongArticle || Verdict.wrong => 0,
};

/// The verdict [given] earns on a question item; null for Writing and
/// Speaking, which have no single right answer.
Verdict? verdictFor(ExamItem item, String given) => switch (item) {
  WordQuestion(:final section, :final expected) => switch (section) {
    ExamSection.vocabulary => checkMeaning(given, expected),
    ExamSection.articles => checkArticle(given, expected),
    ExamSection.wordForms => checkForm(given, expected),
    // Reverse and Listening: the headword, article optional.
    _ => checkGerman(given, expected),
  },
  GapQuestion(:final answer) => checkGerman(given, answer),
  GrammarQuestion(:final item, :final expected) => switch (item) {
    GapFill() => checkGerman(given, expected),
    // Tapped or put in order: right or not, nothing to be nearly right about.
    _ => given.trim() == expected ? Verdict.correct : Verdict.wrong,
  },
  WritingTask() || SpeakingTask() => null,
};

final RegExp _token = RegExp(r'\p{L}+', unicode: true);

/// The words of [text], as the writing checks count them.
List<String> textWords(String text) => <String>[
  for (final m in _token.allMatches(text)) m[0]!,
];

/// FR-L12W-01: the [targets] [text] uses — a word whose search key starts
/// with the target's, so "Heizungen" uses "Heizung".
List<String> targetsUsed(String text, List<String> targets) {
  final keys = <String>[
    for (final word in textWords(text)) searchKey(word, stripArticle: false),
  ];
  return <String>[
    for (final target in targets)
      if (keys.any(
        (key) => key.startsWith(searchKey(target, stripArticle: false)),
      ))
        target,
  ];
}

/// FR-L12W-03's app points: 1 for at least 6 targets used, 1 for at least
/// the level's minimum length.
double writingAppPoints(WritingTask task, String text) =>
    (targetsUsed(text, task.targets).length >= 6 ? 1 : 0) +
    (textWords(text).length >= task.minWords ? 1 : 0);

/// The rubric ticks in `self_rubric_json`: a JSON list of booleans.
List<bool> rubricTicks(String? json) => json == null
    ? const <bool>[]
    : (jsonDecode(json) as List<Object?>).map((t) => t == true).toList();

/// What an item earns: [given] checked by `answer_check`; Writing its app
/// points plus 2 × 0.5 for its rubric; Speaking 4 × 1 for its rubric.
double itemPoints(ExamItem item, {String? given, String? rubric}) {
  final ticks = rubricTicks(rubric);
  int ticked(int of) => ticks.take(of).where((t) => t).length;
  return switch (item) {
    WritingTask() => writingAppPoints(item, given ?? '') + 0.5 * ticked(2),
    SpeakingTask() => ticked(4).toDouble(),
    // A blank answer needs no guard of its own: every check marks it wrong.
    _ => given == null ? 0 : verdictPoints(verdictFor(item, given)!),
  };
}

/// A graded paper: each item's points in paper order, their sum, the most
/// there were, and whether that passes.
typedef PaperScore = ({
  List<double> points,
  double total,
  double max,
  bool passed,
});

/// BR-EXAM-04: [answers] graded, passed at [passPercent] or more of the
/// paper's points.
PaperScore scorePaper(
  List<({ExamItem item, String? given, String? rubric})> answers, {
  required int passPercent,
}) {
  final points = <double>[
    for (final a in answers)
      itemPoints(a.item, given: a.given, rubric: a.rubric),
  ];
  final total = points.fold(0.0, (sum, p) => sum + p);
  final max = answers.fold(0.0, (sum, a) => sum + a.item.section.points);
  return (
    points: points,
    total: total,
    max: max,
    passed: max > 0 && total * 100 >= passPercent * max,
  );
}
