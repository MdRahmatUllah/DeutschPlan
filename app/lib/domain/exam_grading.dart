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

/// A word's two search keys, spaces gone so "SIM-Karten" meets "SIM-Karte":
/// expanded ("Tür" → tuer) and folded ("Werkstätten" → werkstatten).
(String, String) _keys(String text) => (
  searchKey(text, stripArticle: false).replaceAll(' ', ''),
  searchKeyAlt(text, stripArticle: false).replaceAll(' ', ''),
);

/// A verb's -en, or the -n of -ln and -rn (wandern, sammeln).
final RegExp _infinitive = RegExp(r'(?:en|(?<=[lr])n)$');

/// What may follow a verb target's stem: the present and past endings, the
/// infinitive's own, and an -en adjective's (offen → offene). Anything else
/// is another word: "sehr" is not sehen, "unter" not unten.
const Set<String> _verbEndings = <String>{
  '', 'e', 'st', 't', 'en', 'et', 'est', 'n', //
  'te', 'ten', 'test', 'tet',
  'ene', 'ener', 'enes', 'enem', 'enen',
};

/// A target as it is found: the prefix a word must start with, and whether
/// it is a verb's stem, which only verb endings may follow.
///
/// The prefix is the target's expanded key: compared with both of a word's
/// keys, that finds "Werkstätten" for Werkstatt and "Tuer" for Tür, but not
/// "schon" for schön. A lower-case target — a verb, since the course
/// capitalises nouns — loses its infinitive ending, never below three
/// letters, so "bringt" finds bringen and "sein" stays whole.
///
/// ponytail: a prefix, not a stemmer. Irregular and separable forms ("gibt"
/// for geben, "stellt … dar") are not found; a lemmatiser if learners miss
/// too many.
({String prefix, bool verb}) _target(String target) {
  final key = _keys(target).$1;
  final written = target.trim();
  final first = written.isEmpty ? '' : written[0];
  // On the target as written, not its key: "schön" keys to schoen, and its
  // "en" is an umlaut's.
  final ending = _infinitive.firstMatch(written.toLowerCase());
  final cut = ending == null ? 0 : ending.end - ending.start;
  if (first != first.toLowerCase() || cut == 0 || key.length - cut < 3) {
    return (prefix: key, verb: false);
  }
  return (prefix: key.substring(0, key.length - cut), verb: true);
}

/// Whether [word] is a form of [target].
bool _finds(String word, ({String prefix, bool verb}) target) {
  final (expanded, folded) = _keys(word);
  for (final key in <String>[expanded, folded]) {
    if (!key.startsWith(target.prefix)) continue;
    if (!target.verb ||
        _verbEndings.contains(key.substring(target.prefix.length))) {
      return true;
    }
  }
  return false;
}

/// FR-L12W-01: the [targets] [text] uses — a word of it that is a form of
/// the target: "Heizungen" uses Heizung, "bringt" uses bringen,
/// "Werkstätten" uses Werkstatt.
List<String> targetsUsed(String text, List<String> targets) {
  final words = textWords(text);
  return <String>[
    for (final target in targets)
      if (_target(target) case final found
          when found.prefix.isNotEmpty &&
              words.any((word) => _finds(word, found)))
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
