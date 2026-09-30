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

import 'package:sogda/domain/edit_distance.dart';
import 'package:sogda/domain/text_norm.dart';

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
/// [expected] is a meaning cell as authored: one string holding synonyms
/// separated by `/` (and in English's and Bangla's, `,`: [splitMeanings] in
/// [lang]). Any one of them counts, or the whole cell as shown, with or
/// without a bracketed note ([meaningAnswers], #645).
///
/// Several meanings typed, as a list or a card shows them, in any order ("hi /
/// hello"), are right when each is one of the cell's, and *almost* when each
/// is at least almost. One that is not makes the whole answer wrong (#678).
Verdict checkMeaning(String given, String expected, {String? lang}) {
  final candidates = meaningAnswers(
    expected,
    lang: lang,
  ).map(_stripInfinitiveTo).toList();
  if (candidates.isEmpty) return Verdict.wrong;

  final whole = _best(_stripInfinitiveTo(given), candidates, german: false);
  final parts = splitMeanings(given, lang: lang);
  if (whole == Verdict.correct || parts.length < 2) return whole;

  var listed = Verdict.correct;
  for (final part in parts) {
    final verdict = _best(_stripInfinitiveTo(part), candidates, german: false);
    if (verdict == Verdict.wrong) return whole;
    if (verdict == Verdict.almost) listed = Verdict.almost;
  }
  return listed.score > whole.score ? listed : whole;
}

/// EN→DE, cloze and forms (BR-ANS-02).
///
/// [article] is `words.article`; it may also be carried on the front of
/// [german], which is how the source spreadsheets sometimes have it. Either
/// way the learner may type the word with or without it.
///
/// A right noun under the wrong article is [Verdict.wrongArticle], so the
/// caller can name the article it wanted instead of just saying no.
///
/// [german] may hold alternatives and a note, as some headwords and forms
/// cells do: "prima / super / klasse", "hat/ist aufgebrochen", "denn
/// (Partikel)". Any one alternative counts, and the note may be left out
/// (#645).
///
/// [phrase]: a phrase with no article of its own, whose leading der, die,
/// das, den, dem or des is one of its words: "Das stimmt nicht" wants all
/// three, and "die Tisch decken" for "den Tisch decken" is wrong, not a
/// wrong article (#687 AN-10).
///
/// [also]: EN → DE's other right answers, the course's other words whose
/// meaning cell is the prompt ("you" is du, dich and Sie, #832). One of them
/// counts only when it is right: a near miss or a wrong article is judged
/// against [german], the word asked, which the feedback names.
Verdict checkGerman(
  String given,
  String german, {
  String? article,
  bool phrase = false,
  List<GermanAnswer> also = const <GermanAnswer>[],
}) {
  final verdict = _checkGerman(given, german, article: article, phrase: phrase);
  if (verdict == Verdict.correct) return verdict;
  for (final other in also) {
    if (_checkGerman(given, other.german, phrase: other.phrase) ==
        Verdict.correct) {
      return Verdict.correct;
    }
  }
  return verdict;
}

/// A German answer as EN → DE takes it: the headword, article and all, and
/// whether it is a phrase typed whole ([checkGerman]'s `phrase`).
typedef GermanAnswer = ({String german, bool phrase});

Verdict _checkGerman(
  String given,
  String german, {
  String? article,
  bool phrase = false,
}) {
  if (phrase) {
    return _best(given, germanForms(german), german: true, article: false);
  }
  var best = Verdict.wrong;
  for (final form in germanForms(german)) {
    final verdict = _checkGermanForm(given, form, article: article);
    if (verdict == Verdict.correct) return verdict;
    // Almost beats a wrong article, which beats wrong: each says more.
    if (verdict.score > best.score || best == Verdict.wrong) best = verdict;
  }
  return best;
}

Verdict _checkGermanForm(String given, String german, {String? article}) {
  final (givenArticle, givenWord) = _peelArticle(given);
  final (embedded, expectedWord) = _peelArticle(german);

  final expectedArticle = _clean(article ?? '').isEmpty
      ? embedded
      : _clean(article!);

  final verdict = _best(givenWord, <String>[expectedWord], german: true);

  if (expectedArticle.isEmpty ||
      givenArticle.isEmpty ||
      givenArticle == expectedArticle) {
    return verdict;
  }
  // A wrong article costs the point (BR-ANS-02). On a right noun the feedback
  // names the article it wanted. On a misspelt one it is just wrong: a typo
  // must never score more than the spelling it got wrong (#614), and naming
  // the article would bury what the learner actually got wrong.
  return verdict == Verdict.correct ? Verdict.wrongArticle : Verdict.wrong;
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
/// leading one is simply part of what was typed. Alternatives and a note
/// count as in [checkGerman]: "hat/ist aufgebrochen" takes either (#645).
///
/// #682: the superlative is asked as "Superlative of alt" and the course's
/// form is "am ältesten". The stem alone, "ältesten", is the superlative
/// with the "am" the prompt never named: almost, which counts, and the
/// feedback shows the whole form.
Verdict checkForm(String given, String expectedForm) {
  final verdict = _best(given, germanForms(expectedForm), german: true);
  final form = expectedForm.trim();
  if (verdict != Verdict.wrong || !form.startsWith('am ')) return verdict;
  // #682: the stem alone is *almost*, "am" being its one fault: a typo on
  // top of it is two, and wrong (#995).
  return _best(given, germanForms(form.substring(3)), german: true) ==
          Verdict.correct
      ? Verdict.almost
      : Verdict.wrong;
}

/// The synonyms in an authored meaning column, in order.
///
/// Split at `/`, `,` and `;`, but never inside brackets, where they belong to
/// the note: "stop (bus/tram)" is one meaning, not "stop (bus" and "tram)"
/// (#645).
///
/// A comma separates synonyms in English's and Bangla's cells only ([lang]
/// null, `en` or `bn`), which were written with it ("house, home"). The
/// course's other languages separate theirs with ` / ` alone, as their
/// workbooks are written (#1107), so a comma in them is the language's own:
/// Russian's «тем, что», Polish's «…, że …». Split there, a lone «что» would
/// be graded right (#775).
///
/// Exposed because the review screen lists them under a wrong answer, and a
/// second splitter there would drift from this one.
List<String> splitMeanings(String expected, {String? lang}) =>
    _splitOutsideBrackets(
      expected,
      lang == null || lang == 'en' || lang == 'bn'
          ? const <String>{'/', ',', ';'}
          : const <String>{'/', ';'},
    );

/// A meaning cell's synonyms as two words' meanings are compared: lower
/// case, without "to ". Two words that share one would both be right, so
/// neither is the other's distractor (quizzes, placement #680).
Set<String> senses(String cell, {String? lang}) => <String>{
  for (final meaning in splitMeanings(cell, lang: lang))
    _stripInfinitiveTo(meaning).toLowerCase(),
};

/// Every way a meaning cell may be answered: the cell as shown ("the bill,
/// please" is one phrase, not two synonyms) and each of its synonyms, each
/// with and without its bracketed note.
///
/// The one rule for what a meaning is: [checkMeaning] grades by it, and
/// Search's exact tier matches by it, so the two can't disagree (#645).
///
/// A hyphen may be left out: "email" is "e-mail" (#699). Only in a meaning:
/// German's "Email" is enamel, not "E-Mail".
Set<String> meaningAnswers(String cell, {String? lang}) => <String>{
  for (final meaning in <String>[cell, ...splitMeanings(cell, lang: lang)])
    for (final answer in _withoutAside(meaning)) ...<String>{
      answer,
      answer.replaceAll('-', ''),
    },
};

/// Every way [german] may be typed: its alternatives, each with and without a
/// bracketed note, and each in-word slash taken either way.
///
/// "circa / etwa / rund" is three answers; "hat/ist aufgebrochen" is "hat
/// aufgebrochen" and "ist aufgebrochen"; "hat gehabt (hatte)" is "hat gehabt"
/// and itself. Only the text outside the note is split: written out whole,
/// "Haltestelle (Bus / Tram)" is one answer, never "Tram)".
List<String> germanForms(String german) {
  final written = german.trim();
  final bare = written.replaceAll(_aside, '').trim();
  return <String>{
    for (final alternative in bare.split(_spacedSlash))
      ..._eachSlashedWord(alternative.trim()),
    written,
  }.where((form) => form.isNotEmpty).toList();
}

/// "a / b": alternatives of the whole. An in-word "a/b" is [_eachSlashedWord]'s.
final RegExp _spacedSlash = RegExp(r'\s+/\s+');

/// A bracketed note, and the space before it.
final RegExp _aside = RegExp(r'\s*\([^)]*\)');

/// [text] as written, and without its bracketed notes when it has any: what
/// the note adds may be typed, or left out.
Set<String> _withoutAside(String text) =>
    <String>{text.trim(), text.replaceAll(_aside, '').trim()}..remove('');

/// "hat/ist aufgebrochen" → "hat aufgebrochen", "ist aufgebrochen": each word
/// holding a slash taken each way.
Iterable<String> _eachSlashedWord(String text) {
  var forms = <String>[''];
  for (final word in text.split(RegExp(r'\s+'))) {
    // ponytail: every combination, uncapped; a cell holds one or two slashed
    // words, so a handful of forms. Cap it if content ever grows more.
    final options = word.contains('/') && word.length > 1
        ? word.split('/').where((option) => option.isNotEmpty)
        : <String>[word];
    forms = <String>[
      for (final form in forms)
        for (final option in options) form.isEmpty ? option : '$form $option',
    ];
  }
  return forms;
}

List<String> _splitOutsideBrackets(String text, Set<String> separators) {
  final parts = <String>[];
  final part = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if (char == '(') depth++;
    if (char == ')' && depth > 0) depth--;
    if (depth == 0 && separators.contains(char)) {
      parts.add(part.toString());
      part.clear();
    } else {
      part.write(char);
    }
  }
  parts.add(part.toString());
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

/// The best verdict [given] earns against any of [candidates].
///
/// Best, not first: "go / walking" against "walkign" is *almost* on the
/// second candidate, and stopping at the first wrong answer would mark it
/// wrong.
Verdict _best(
  String given,
  Iterable<String> candidates, {
  required bool german,
  bool article = true,
}) {
  var best = Verdict.wrong;

  for (final candidate in candidates) {
    final verdict = _compare(
      given,
      candidate,
      german: german,
      article: article,
    );
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
/// half the answer scores full marks. [article] false keeps it for a German
/// phrase too, whose leading "das" is a word of it (#687 AN-10).
Verdict _compare(
  String givenText,
  String expectedText, {
  required bool german,
  bool article = true,
}) {
  // #1120: a meaning in Polish or Russian, typed without its marks.
  final given = german ? givenText : foldMeaning(givenText);
  final expected = german ? expectedText : foldMeaning(expectedText);
  final strip = german && article;
  final key = searchKey(given, stripArticle: strip);
  final alt = searchKeyAlt(given, stripArticle: strip);
  final expectedKey = searchKey(expected, stripArticle: strip);
  final expectedAlt = searchKeyAlt(expected, stripArticle: strip);

  if (key.isEmpty || expectedKey.isEmpty) return Verdict.wrong;

  // Two keys: "Tür" and "Tuer" meet on the expanded key, "Tur" only on the
  // folded one. The folded key is a coarsening of the expanded one for
  // exactly the umlauts, so comparing crosswise adds nothing.
  if (key == expectedKey) return Verdict.correct;

  // BR-ANS-02: "ae" is the umlaut typed without its key, and right. A bare
  // vowel may be another word or form, the very thing a question can test:
  // "hatte" for "hätte", "Mutter" for "Mütter", "schon" for "schön". So in
  // German it is *almost*: the feedback shows the umlaut, and a different form
  // is never marked right (#675).
  if (alt == expectedAlt) return german ? Verdict.almost : Verdict.correct;

  // Both spellings get a shot at the typo — a learner typing "Baeuem" for
  // "Bäume" is one character out on the expanded key and two on the folded
  // one — but the length gate always comes from the folded key, which is the
  // closest thing here to a letter count. With ß as one letter, not the fold's
  // "ss": "Größe" is five letters, and a typo in it is wrong (#699). Keyed
  // with any article and cut to the key's words, which drop only an article.
  final words = expectedAlt.split(' ').length;
  final letters = searchKeyAlt(
    expected.toLowerCase().replaceAll('ß', 's'),
    stripArticle: false,
  ).split(' ');
  final gate = letters.sublist(letters.length - words);

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
