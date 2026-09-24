/// `docs/03-domain/grammar-practice.md`: one grammar topic into 3–5 practice
/// items, built only from its rule, example and *watch out* — no hand-written
/// exercises.
///
/// Plain Dart: no Flutter, no drift. L15 hands it a [GrammarSource] and a
/// seed, and checks the answers with `answer_check.dart`.
library;

import 'dart:convert';
import 'dart:math' as math;

/// What the generator reads of a topic.
class GrammarSource {
  const GrammarSource({
    required this.uid,
    required this.topic,
    required this.rule,
    required this.exampleDe,
    required this.exampleEn,
    required this.watchOut,
    required this.tags,
    required this.levelCode,
  });

  final String uid;
  final String topic;
  final String rule;
  final String exampleDe;
  final String exampleEn;
  final String watchOut;

  /// `grammar_topics.tags`, the pipeline's keywords: they decide which item
  /// types apply.
  final List<String> tags;
  final String levelCode;
}

/// One practice item.
sealed class GrammarItem {
  const GrammarItem();
}

/// A sentence with one word blanked, typed in (`checkGerman`).
final class GapFill extends GrammarItem {
  const GapFill({
    required this.before,
    required this.after,
    required this.answer,
    required this.translation,
  });

  final String before;
  final String after;
  final String answer;
  final String translation;
}

/// The same blank with three forms to pick from (exact).
final class PickTheForm extends GrammarItem {
  const PickTheForm({
    required this.before,
    required this.after,
    required this.options,
    required this.answer,
  });

  final String before;
  final String after;
  final List<String> options;
  final String answer;
}

/// A sentence with one wrong word, tapped (token index).
final class SpotTheError extends GrammarItem {
  const SpotTheError({
    required this.tokens,
    required this.wrong,
    required this.correction,
  });

  final List<String> tokens;
  final int wrong;
  final String correction;
}

/// A sentence's words as shuffled chips, put back in order (sequence).
final class OrderTheSentence extends GrammarItem {
  const OrderTheSentence({required this.chips, required this.answer});

  final List<String> chips;
  final List<String> answer;
}

/// C1/C2: which rule fits the topic, of four (exact).
final class RuleRecall extends GrammarItem {
  const RuleRecall({
    required this.question,
    required this.options,
    required this.answer,
  });

  final String question;
  final List<String> options;
  final int answer;
}

/// BR-FSRS-05: all correct → Good (3), one wrong → Hard (2), more → Again
/// (1). The topic is rated once, on the last item.
int practiceRating({required int items, required int correct}) {
  final wrong = items - correct;
  if (wrong <= 0) return 3;
  return wrong == 1 ? 2 : 1;
}

/// FR-L15-01's seed: the same items for a topic all day, new ones tomorrow.
/// FNV-1a over the bytes, so it does not depend on `String.hashCode`.
int practiceSeed(String uid, String day) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode('$uid|$day')) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The word-order tags: *Order the sentence* only suits these.
const Set<String> wordOrderTags = <String>{'word-order', 'nebensatz', 'v2'};

/// Tags about a form going wrong: *Spot the error* suits these.
const Set<String> errorTags = <String>{
  'verb-form',
  'case',
  'adjective',
  'pronoun',
  'preposition',
  'gender',
  'negation',
  'tense',
  'subjunctive',
  'passive',
};

/// The most a topic yields.
const int maxItems = 5;

/// [source]'s items, seeded. [siblings] are other topics' rules at the same
/// level, the wrong options of a *Rule recall*.
List<GrammarItem> generateItems(
  GrammarSource source, {
  required int seed,
  List<String> siblings = const <String>[],
}) {
  final random = math.Random(seed);
  // The review and exam-strategy topics have no example ("—"): their rule
  // is what there is to practise.
  final example = _blank(source.exampleDe) ? source.rule : source.exampleDe;
  final sentences = _sentences(example);
  final translations = _blank(source.exampleDe)
      ? <String>[]
      : _sentences(source.exampleEn);
  // The rule's words, not *watch out*'s: its English ("Kann ich …") would
  // point the gap at "Ich".
  final ruleWords = _words(source.rule)
      .map((word) => word.toLowerCase())
      .where((word) => word.length > 2)
      .toSet();

  final items = <GrammarItem>[];
  final sentenceOrder = List<int>.generate(sentences.length, (i) => i)
    ..shuffle(random);

  // Every topic: a gap fill and a pick-the-form, on the first sentence the
  // shuffle offers. The pipeline tags every topic with both, so these are
  // not asked of the tags.
  final first = sentenceOrder.first;
  final tokens = _tokens(sentences[first]);
  final target = _target(tokens, ruleWords);
  final translation = sentences.length == translations.length
      ? translations[first]
      : _blank(source.exampleEn)
      ? ''
      : source.exampleEn;
  final (before, answer, after) = _blankAt(tokens, target);
  final distractors = _distractors(answer, source, random);

  items.add(
    GapFill(
      before: before,
      after: after,
      answer: answer,
      translation: translation,
    ),
  );
  items.add(
    PickTheForm(
      before: before,
      after: after,
      options: (<String>[answer, ...distractors.take(2)]..shuffle(random)),
      answer: answer,
    ),
  );

  final tags = source.tags.toSet();
  if (tags.intersection(errorTags).isNotEmpty) {
    final error =
        _errorFrom(source.watchOut, tokens) ??
        (
          target: target,
          form: tokens[target].replaceFirst(answer, distractors.first),
        );
    items.add(
      SpotTheError(
        tokens: <String>[
          for (var i = 0; i < tokens.length; i++)
            i == error.target ? error.form : tokens[i],
        ],
        wrong: error.target,
        correction: tokens[error.target],
      ),
    );
  }

  if (tags.intersection(wordOrderTags).isNotEmpty) {
    final words = _tokens(sentences[first]);
    if (words.length >= 3) {
      final chips = List<String>.of(words);
      // A shuffle that leaves the sentence as it was is no exercise.
      for (var tries = 0; tries < 5 && _same(chips, words); tries++) {
        chips.shuffle(random);
      }
      if (!_same(chips, words)) {
        items.add(OrderTheSentence(chips: chips, answer: words));
      }
    }
  }

  if ((source.levelCode == 'C1' || source.levelCode == 'C2') &&
      siblings.where((rule) => rule != source.rule).length >= 3) {
    final right = _firstClause(source.rule);
    final wrong =
        (siblings.where((rule) => rule != source.rule).toList()
              ..shuffle(random))
            .take(3)
            .map(_firstClause);
    final options = <String>[right, ...wrong]..shuffle(random);
    items.add(
      RuleRecall(
        question: source.topic,
        options: options,
        answer: options.indexOf(right),
      ),
    );
  }

  // At least three: a second gap fill from another sentence if the example
  // has one, else a pick-the-form on another of its words.
  if (items.length < 3 && sentenceOrder.length > 1) {
    final second = _tokens(sentences[sentenceOrder[1]]);
    final (secondBefore, secondAnswer, secondAfter) = _blankAt(
      second,
      _target(second, ruleWords),
    );
    items.add(
      GapFill(
        before: secondBefore,
        after: secondAfter,
        answer: secondAnswer,
        translation: sentences.length == translations.length
            ? translations[sentenceOrder[1]]
            : '',
      ),
    );
  }
  if (items.length < 3) {
    final at = _target(<String>[
      for (var i = 0; i < tokens.length; i++) i == target ? '' : tokens[i],
    ], ruleWords);
    if (at != target && _bare(tokens[at]).length > 1) {
      final (otherBefore, other, otherAfter) = _blankAt(tokens, at);
      items.add(
        PickTheForm(
          before: otherBefore,
          after: otherAfter,
          options: <String>[
            other,
            ..._distractors(other, source, random).take(2),
          ]..shuffle(random),
          answer: other,
        ),
      );
    }
  }
  return items.take(maxItems).toList();
}

/// The example's sentences: split after . ! ? before a capital, and on " / ".
List<String> _sentences(String text) => <String>[
  for (final part in text.split(RegExp(r'(?<=[.!?])\s+(?=[A-ZÄÖÜ„])|\s+/\s+')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// A sentence's tokens, punctuation left on the word it follows.
List<String> _tokens(String sentence) =>
    sentence.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();

/// The letters of [text]'s words.
Iterable<String> _words(String text) =>
    RegExp(r"[A-Za-zÄÖÜäöüß'-]+")
        .allMatches(text)
        .map((match) => match.group(0)!);

String _bare(String token) =>
    token.replaceAll(RegExp(r"^[^A-Za-zÄÖÜäöüß]+|[^A-Za-zÄÖÜäöüß]+$"), '');

/// [tokens] with the word at [at] taken out: the text before it, the word,
/// and the text after it, its own punctuation included — "Sie?" is the
/// answer "Sie" and a "?" after the gap.
(String, String, String) _blankAt(List<String> tokens, int at) {
  final token = tokens[at];
  final word = _bare(token);
  final start = token.indexOf(word);
  final lead = token.substring(0, start);
  final trail = token.substring(start + word.length);
  return (
    <String>[...tokens.sublist(0, at), if (lead.isNotEmpty) lead].join(' '),
    word,
    '$trail ${tokens.sublist(at + 1).join(' ')}'.trim(),
  );
}

/// Whether a field is empty or the pipeline's "—".
bool _blank(String text) => !RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(text);

/// Whether [word] is a form the rule names: the same word, or one sharing
/// its first four letters — "Könnten" for the rule's "könnte".
bool _named(String word, Set<String> ruleWords) {
  final lower = word.toLowerCase();
  if (ruleWords.contains(lower)) return true;
  if (lower.length < 4) return false;
  final stem = lower.substring(0, 4);
  return ruleWords.any((rule) => rule.length >= 4 && rule.startsWith(stem));
}

/// The token to blank: the longest form the rule names, else the longest.
int _target(List<String> tokens, Set<String> ruleWords) {
  var best = -1;
  var bestLength = 0;
  for (final pass in <bool>[true, false]) {
    for (var i = 0; i < tokens.length; i++) {
      final word = _bare(tokens[i]);
      if (word.length < 2) continue;
      if (pass && (word.length < 3 || !_named(word, ruleWords))) continue;
      if (word.length > bestLength) {
        best = i;
        bestLength = word.length;
      }
    }
    if (best >= 0) return best;
  }
  return 0;
}

/// Closed word classes, where a wrong form is best another member: the
/// articles, *ein* and *kein*, the possessives, *sein*, *haben*, *werden*,
/// and the old *dass*/*das* trap.
const List<List<String>> _families = <List<String>>[
  <String>['der', 'die', 'das', 'den', 'dem', 'des'],
  <String>['ein', 'eine', 'einen', 'einem', 'einer', 'eines'],
  <String>['kein', 'keine', 'keinen', 'keinem', 'keiner', 'keines'],
  <String>['mein', 'meine', 'meinen', 'meinem', 'meiner', 'meines'],
  <String>['dein', 'deine', 'deinen', 'deinem', 'deiner', 'deines'],
  <String>['sein', 'seine', 'seinen', 'seinem', 'seiner', 'seines'],
  <String>['ihr', 'ihre', 'ihren', 'ihrem', 'ihrer', 'ihres'],
  <String>['unser', 'unsere', 'unseren', 'unserem', 'unserer', 'unseres'],
  <String>['bin', 'bist', 'ist', 'sind', 'seid', 'war', 'waren'],
  <String>['habe', 'hast', 'hat', 'haben', 'habt', 'hatte', 'hatten'],
  <String>['werde', 'wirst', 'wird', 'werden', 'werdet', 'wurde', 'wurden'],
  <String>['dass', 'das', 'was'],
  <String>['hätte', 'hättest', 'hätten', 'hättet', 'hatte', 'habe'],
  <String>['wäre', 'wärst', 'wären', 'wärt', 'war', 'sei'],
  <String>['würde', 'würdest', 'würden', 'würdet', 'wurde', 'werde'],
  <String>['könnte', 'könntest', 'könnten', 'konnte', 'kann', 'können'],
];

/// Two or more wrong forms for [answer]: its word class's other members,
/// other inflections the rule or *watch out* names, then endings and
/// umlauts changed.
List<String> _distractors(
  String answer,
  GrammarSource source,
  math.Random random,
) {
  final bare = _bare(answer);
  final lower = bare.toLowerCase();
  final stem = lower.length > 3 ? lower.substring(0, 3) : lower;
  final family = <String>[
    for (final members in _families)
      if (members.contains(lower))
        for (final member in members)
          if (member != lower)
            bare[0] == bare[0].toUpperCase()
                ? '${member[0].toUpperCase()}${member.substring(1)}'
                : member,
  ]..shuffle(random);
  final named = <String>{
    for (final word in _words('${source.rule} ${source.watchOut}'))
      if (word.toLowerCase() != lower &&
          word.length > 2 &&
          word.toLowerCase().startsWith(stem))
        word,
  }.toList()..shuffle(random);

  // ponytail: endings changed by rule can make a non-word ("geschlosse")
  // for a participle; a lemma table from the pipeline would fix that.
  final made = <String>{};
  final ending = RegExp(r'(en|er|es|em|st|e|n|t|s)$').firstMatch(bare);
  final root = ending == null ? bare : bare.substring(0, ending.start);
  for (final end in <String>['e', 'en', 'er', 'es', 'em', 't', 'st', '']) {
    final form = '$root$end';
    if (form.toLowerCase() != lower && form.length > 1) made.add(form);
  }
  const umlauts = <String, String>{
    'a': 'ä',
    'o': 'ö',
    'u': 'ü',
    'ä': 'a',
    'ö': 'o',
    'ü': 'u',
  };
  for (final MapEntry(key: plain, value: marked) in umlauts.entries) {
    if (bare.contains(plain)) made.add(bare.replaceFirst(plain, marked));
  }
  final extra = made.toList()..shuffle(random);
  return <String>{...family, ...named, ...extra}
      .where((form) => form.toLowerCase() != lower)
      .map((form) => answer.replaceFirst(bare, form))
      .toList();
}

/// *Watch out*'s error in the sentence: a word it names that is another form
/// of one of the sentence's words.
({int target, String form})? _errorFrom(String watchOut, List<String> tokens) {
  final named = _words(watchOut).toList();
  for (var i = 0; i < tokens.length; i++) {
    final word = _bare(tokens[i]).toLowerCase();
    if (word.length < 3) continue;
    for (final candidate in named) {
      final other = candidate.toLowerCase();
      if (other != word &&
          other.length > 2 &&
          other.substring(0, 3) == word.substring(0, 3) &&
          !tokens.any((token) => _bare(token).toLowerCase() == other)) {
        return (
          target: i,
          form: tokens[i].replaceFirst(_bare(tokens[i]), candidate),
        );
      }
    }
  }
  return null;
}

/// A rule's first sentence, as a recall option.
String _firstClause(String rule) =>
    rule.split(RegExp(r'(?<=[.;:])\s')).first.trim();

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
