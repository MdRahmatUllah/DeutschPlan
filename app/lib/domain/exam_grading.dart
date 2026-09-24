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

/// A word, as the writing checks count them: letters and digits, with a
/// hyphen or an apostrophe inside — "E-Mail", "geht's" and "2020" are one
/// word each.
final RegExp _token = RegExp(
  r"[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*",
  unicode: true,
);

/// The words of [text].
List<String> textWords(String text) => <String>[
  for (final m in _token.allMatches(text)) m[0]!,
];

/// What a word and a target are compared on: both of search's keys, with
/// the spaces gone so "SIM-Karten" meets "SIM-Karte". The expanded key
/// matches "Tuer" to "Tür", the folded one "Werkstätten" to "Werkstatt".
(String, String) _keys(String text) => (
  searchKey(text, stripArticle: false).replaceAll(' ', ''),
  searchKeyAlt(text, stripArticle: false).replaceAll(' ', ''),
);

/// A verb's -en, or the -n of -ln and -rn (wandern, sammeln).
final RegExp _infinitive = RegExp(r'(?:en|(?<=[lr])n)$');

/// [key] without a verb's infinitive ending, never below three letters:
/// "sein" keeps its n.
String _cut(String key) {
  final ending = _infinitive.firstMatch(key);
  return ending == null || ending.start < 3
      ? key
      : key.substring(0, ending.start);
}

/// The prefixes a target is found by. A lower-case target — a verb, where
/// the course capitalises its nouns — loses its infinitive ending, so
/// "bringen" is found in "bringt".
///
/// ponytail: a prefix, not a stemmer. Irregular forms ("ist" for sein,
/// "hat" for haben) are not found; a lemmatiser if learners miss too many.
(String, String) _stems(String target) {
  final keys = _keys(target);
  final first = target.trim().isEmpty ? '' : target.trim()[0];
  if (first != first.toLowerCase()) return keys;
  return (_cut(keys.$1), _cut(keys.$2));
}

/// FR-L12W-01: the [targets] [text] uses — a word of it that starts with
/// the target's stem: "Heizungen" uses "Heizung", "bringt" uses "bringen",
/// "Werkstätten" uses "Werkstatt".
List<String> targetsUsed(String text, List<String> targets) {
  final words = <(String, String)>[
    for (final word in textWords(text)) _keys(word),
  ];
  return <String>[
    for (final target in targets)
      if (_stems(target) case (final expanded, final folded)
          when expanded.isNotEmpty &&
              words.any(
                (w) => w.$1.startsWith(expanded) || w.$2.startsWith(folded),
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
///
/// A rubric scores only what is there to assess: Writing's needs a text,
/// and Speaking's a recording — its [given] is the recording, and a section
/// skipped or a recording deleted is 0 (FR-L12S-01, FR-L12S-04).
double itemPoints(ExamItem item, {String? given, String? rubric}) {
  final ticks = rubricTicks(rubric);
  int ticked(int of) => ticks.take(of).where((t) => t).length;
  return switch (item) {
    WritingTask() =>
      writingAppPoints(item, given ?? '') +
          (textWords(given ?? '').isEmpty ? 0 : 0.5 * ticked(2)),
    SpeakingTask() => (given ?? '').trim().isEmpty ? 0 : ticked(4).toDouble(),
    // A blank answer needs no guard of its own: every check marks it wrong.
    _ => given == null ? 0 : verdictFor(item, given)!.score,
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
