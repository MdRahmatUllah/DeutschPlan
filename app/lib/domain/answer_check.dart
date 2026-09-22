/// BR-ANS-01…04. `docs/03-domain/answer-checking.md`.
///
/// Four checks over one comparison. Cloze cards, quizzes, exams and grammar
/// practice all call these, so the rule about what counts as right lives here
/// once rather than in four screens.
///
/// It is thin, and deliberately: `text_norm.dart` already folds case,
/// punctuation, umlauts and a leading article, and `edit_distance.dart`
/// already counts a typo. Nothing here re-implements either — the work is
/// deciding which comparison each question type asks for.
///
/// Plain Dart: no Flutter, no drift.
library;

import 'package:deutschplan/domain/edit_distance.dart';
import 'package:deutschplan/domain/text_norm.dart';

/// What an answer was worth. BR-ANS-04: *almost* scores 0.5.
enum Verdict {
  correct(1.0),
  almost(0.5),

  /// The noun was right and the article was not (BR-ANS-02). Scores zero, but
  /// the screen says which article it wanted — that is the whole reason it is
  /// not just [wrong].
  wrongArticle(0),

  wrong(0);

  const Verdict(this.score);

  /// BR-ANS-04: correct 1 · almost 0.5 · wrongArticle 0 · wrong 0.
  final double score;

  bool get isRight => this == Verdict.correct;
}

/// The shortest expected word that a single typo in is *almost* rather than
/// wrong (BR-ANS-01).
///
/// Below it a one-character edit is usually a different word — "Bett"/"Brett",
/// "Sohn"/"Sonne" — so forgiving it would mark a wrong answer right.
const int typoMinLength = 6;

/// DE→EN and DE→BN (BR-ANS-01).
///
/// [expected] is the `words.english` or `words.bangla` column as authored: one
/// string holding synonyms separated by `/` or `,`. Any one of them counts.
Verdict checkMeaning(String given, String expected) {
  final candidates = splitMeanings(expected);
  if (candidates.isEmpty) return Verdict.wrong;

  return _best(
    _stripInfinitiveTo(given),
    candidates.map(_stripInfinitiveTo),
    german: false,
  );
}

/// EN→DE, cloze and forms (BR-ANS-02).
///
/// [article] is `words.article`; it may also be carried on the front of
/// [german], which is how the source spreadsheets sometimes have it. Either
/// way the learner may type the word with or without it.
///
/// A right noun under the wrong article is [Verdict.wrongArticle], so the
/// caller can name the article it wanted instead of just saying no.
Verdict checkGerman(String given, String german, {String? article}) {
  final (givenArticle, givenWord) = _peelArticle(given);
  final (embedded, expectedWord) = _peelArticle(german);

  final expectedArticle = _clean(article ?? '').isEmpty
      ? embedded
      : _clean(article!);

  final verdict = _best(givenWord, <String>[expectedWord], german: true);

  // Only when the noun itself is right. A wrong article on a wrong word is
  // just wrong, and telling the learner about the article would bury the
  // thing they actually got wrong.
  if (verdict == Verdict.correct &&
      expectedArticle.isNotEmpty &&
      givenArticle.isNotEmpty &&
      givenArticle != expectedArticle) {
    return Verdict.wrongArticle;
  }

  return verdict;
}

/// The articles quiz (BR-ANS-03): exact der/die/das, no typo allowance.
///
/// Three options and four letters each — a near-miss here is a guess, and
/// there is nothing to be nearly right about.
Verdict checkArticle(String given, String article) =>
    _clean(given) == _clean(article) && _clean(article).isNotEmpty
    ? Verdict.correct
    : Verdict.wrong;

/// The forms quiz: [checkGerman] without the article logic.
///
/// A plural or a participle has no article of its own to get wrong, so a
/// leading one is simply part of what was typed.
Verdict checkForm(String given, String expectedForm) =>
    _best(given, <String>[expectedForm], german: true);

/// The synonyms in an authored meaning column, in order.
///
/// Exposed because the review screen lists them under a wrong answer, and a
/// second splitter there would drift from this one.
List<String> splitMeanings(String expected) => expected
    .split(RegExp(r'[/,;]'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

/// The best verdict [given] earns against any of [candidates].
///
/// Best, not first: "to go / to walk" against "wlak" is *almost* on the second
/// candidate, and stopping at the first wrong answer would mark it wrong.
Verdict _best(
  String given,
  Iterable<String> candidates, {
  required bool german,
}) {
  var best = Verdict.wrong;

  for (final candidate in candidates) {
    final verdict = _compare(given, candidate, german: german);
    if (verdict == Verdict.correct) return Verdict.correct;
    if (verdict == Verdict.almost) best = Verdict.almost;
  }
  return best;
}

/// One answer against one expected string.
///
/// [german] decides whether a leading article is stripped. It must be false
/// for a meaning: `text_norm` peels der/die/das, and `die` is an ordinary
/// English verb — with it on, "die out" keys to "out" and a learner who types
/// half the answer scores full marks.
Verdict _compare(String given, String expected, {required bool german}) {
  final key = searchKey(given, stripArticle: german);
  final alt = searchKeyAlt(given, stripArticle: german);
  final expectedKey = searchKey(expected, stripArticle: german);
  final expectedAlt = searchKeyAlt(expected, stripArticle: german);

  if (key.isEmpty || expectedKey.isEmpty) return Verdict.wrong;

  // Two keys, because BR-ANS-02 accepts ä, ae and a alike: "Tür" and "Tuer"
  // meet on the expanded key, "Tur" on the folded one.
  //
  // Each key against its own kind. Comparing them crosswise as well turns out
  // to accept nothing extra — the folded key is a coarsening of the expanded
  // one for exactly these letters, so `alt == alt` already covers it; I
  // checked against a list of German pairs and found none that distinguishes
  // the two. Written this way because it is the rule, not because it is
  // stricter.
  if (key == expectedKey || alt == expectedAlt) return Verdict.correct;

  // Both spellings get a shot at the typo — a learner typing "Baeuem" for
  // "Bäume" is one character out on the expanded key and two on the folded
  // one — but the length gate always comes from the folded key, which is the
  // closest thing here to a letter count.
  final gate = expectedAlt.split(' ');

  return _typo(key, expectedKey, gate) || _typo(alt, expectedAlt, gate)
      ? Verdict.almost
      : Verdict.wrong;
}

/// Splits a leading German article off, returning it and the rest.
///
/// Done before [searchKey], which strips the article itself — by then there is
/// nothing left to say the learner got it wrong. Returns an empty article when
/// there is none, and never eats the whole answer: "die" alone is the learner
/// answering an articles question, not an article on nothing.
(String, String) _peelArticle(String text) {
  final parts = _clean(text).split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.length < 2 || !germanArticles.contains(parts.first)) {
    return ('', text);
  }
  return (parts.first, parts.skip(1).join(' '));
}

String _clean(String text) => text.trim().toLowerCase();

/// Whether [given] is [expected] with one character mistyped, under BR-ANS-01.
///
/// The rule is about a *word*, not a phrase, and the word it is about is the
/// one that was mistyped — not the longest one in the answer. "look after" and
/// "look aftre" differ in a five-letter word, so that is wrong however long
/// "look after" is; "look understand" against "look understnad" differs in a
/// ten-letter one, so that is almost.
///
/// [gate] is the expected string's folded words, and the only thing lengths
/// are measured on. Taking them from [expected] instead would let the expanded
/// key decide: "Bäume" keys to "baeume", six characters for a five-letter
/// word, and a typo in it would be forgiven when BR-ANS-01 says it should not.
///
/// The lengths come from the expected side, never the given one. It is the
/// word the learner was reaching for, and judging by what they typed would let
/// a three-letter stab pass against a ten-letter answer.
bool _typo(String given, String expected, List<String> gate) {
  final typed = given.split(' ');
  final wanted = expected.split(' ');

  // A missing or extra space is a typo in its own right, and there is no one
  // word to attribute it to. Judged on the longest expected word, which is the
  // closest thing to "was this a long enough answer to mistype".
  if (typed.length != wanted.length) {
    return _longestWord(gate) >= typoMinLength &&
        editDistance(given, expected, limit: 1) == 1;
  }

  var mistyped = -1;
  for (var i = 0; i < wanted.length; i++) {
    if (typed[i] == wanted[i]) continue;
    if (mistyped >= 0) return false; // two words out is not one typo
    mistyped = i;
  }

  if (mistyped < 0) return false; // identical; the caller already said correct
  return gate[mistyped].length >= typoMinLength &&
      editDistance(typed[mistyped], wanted[mistyped], limit: 1) == 1;
}

int _longestWord(List<String> words) => words.fold(
  0,
  (longest, word) => word.length > longest ? word.length : longest,
);

/// Drops a leading "to " so "to go" and "go" are the same answer (BR-ANS-01).
///
/// Only at the front and only as a whole word: "tomato" keeps its "to", and
/// "point to it" keeps the one in the middle.
String _stripInfinitiveTo(String text) {
  final trimmed = text.trim();
  final match = RegExp(r'^to\s+', caseSensitive: false).firstMatch(trimmed);
  return match == null ? trimmed : trimmed.substring(match.end);
}
