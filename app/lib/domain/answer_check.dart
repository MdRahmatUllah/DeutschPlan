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

  return _best(_stripInfinitiveTo(given), candidates.map(_stripInfinitiveTo));
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

  final verdict = _best(givenWord, <String>[expectedWord]);

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
    _best(given, <String>[expectedForm]);

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
Verdict _best(String given, Iterable<String> candidates) {
  var best = Verdict.wrong;

  for (final candidate in candidates) {
    final verdict = _compare(given, candidate);
    if (verdict == Verdict.correct) return Verdict.correct;
    if (verdict == Verdict.almost) best = Verdict.almost;
  }
  return best;
}

/// One answer against one expected string.
Verdict _compare(String given, String expected) {
  final key = searchKey(given);
  final alt = searchKeyAlt(given);
  final expectedKey = searchKey(expected);
  final expectedAlt = searchKeyAlt(expected);

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

  // BR-ANS-01, and the length is the expected word's: it is the word the
  // learner was reaching for, and judging by what they typed would let a
  // five-letter guess pass against a ten-letter answer.
  if (expectedKey.length < typoMinLength) return Verdict.wrong;

  final distance = editDistance(key, expectedKey, limit: 1) == 1
      ? 1
      : editDistance(alt, expectedAlt, limit: 1);

  return distance == 1 ? Verdict.almost : Verdict.wrong;
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

/// Drops a leading "to " so "to go" and "go" are the same answer (BR-ANS-01).
///
/// Only at the front and only as a whole word: "tomato" keeps its "to", and
/// "point to it" keeps the one in the middle.
String _stripInfinitiveTo(String text) {
  final trimmed = text.trim();
  final match = RegExp(r'^to\s+', caseSensitive: false).firstMatch(trimmed);
  return match == null ? trimmed : trimmed.substring(match.end);
}
