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

/// What the course says beyond one topic (#330): every form its words and
/// examples use, to tell a real form from a made-up one ("warteen"), and its
/// example sentences, to practise a form in another sentence than the gap
/// fill's. [CourseText.none] knows no course: every form passes, and there is
/// no other sentence.
class CourseText {
  CourseText({
    Iterable<String> texts = const <String>[],
    this.sentences = const <({String german, String english})>[],
  }) : _forms = <String>{
         for (final text in texts)
           for (final word in _words(text)) word.toLowerCase(),
         for (final sentence in sentences)
           for (final word in _words(sentence.german)) word.toLowerCase(),
       };

  static final CourseText none = CourseText();

  final Set<String> _forms;

  /// The course's example sentences, with their English.
  final List<({String german, String english})> sentences;

  /// Whether [form] is German the course uses; with no course, any form.
  bool knows(String form) =>
      _forms.isEmpty || _forms.contains(form.toLowerCase());

  late final Map<String, List<int>> _byWord = () {
    final index = <String, List<int>>{};
    for (final (i, sentence) in sentences.indexed) {
      for (final word in _words(sentence.german).toSet()) {
        (index[word] ??= <int>[]).add(i);
      }
    }
    return index;
  }();

  /// The sentences with [form], as it is written, as a word of their own.
  List<({String german, String english})> sentencesWith(String form) =>
      <({String german, String english})>[
        for (final i in _byWord[form] ?? const <int>[]) sentences[i],
      ];
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
    this.translation = '',
  });

  final String before;
  final String after;
  final List<String> options;
  final String answer;
  final String translation;
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
/// level, the wrong options of a *Rule recall*; [course] what tells a real
/// form from a made-up one, and gives *Pick the form* its sentence when the
/// example has only the gap fill's (#330).
List<GrammarItem> generateItems(
  GrammarSource source, {
  required int seed,
  List<String> siblings = const <String>[],
  CourseText? course,
}) {
  final text = course ?? CourseText.none;
  final random = math.Random(seed);
  // The review and exam-strategy topics have no example ("—"): their rule
  // is what there is to practise.
  final example = _blank(source.exampleDe) ? source.rule : source.exampleDe;
  final sentences = _sentences(example);
  final translations = _blank(source.exampleDe)
      ? <String>[]
      : _sentences(source.exampleEn);
  final cues = _cues(source);
  final tags = <String>{
    ...source.tags,
    // "Sie vs du": a pronoun its title names is its point.
    for (final word in _words(source.topic)) 'title:${word.toLowerCase()}',
  };
  // A word *Pick the form* can ask: one with two real wrong forms.
  bool askable(String word) =>
      _wrongForms(word, source, text).real.expand((group) => group).length >= 2;
  int target(List<String> tokens, {bool real = false}) =>
      _target(tokens, cues, tags, real ? askable : null);

  final items = <GrammarItem>[];
  final sentenceOrder = List<int>.generate(sentences.length, (i) => i)
    ..shuffle(random);

  // Every topic: a gap fill and a pick-the-form, on the first sentence the
  // shuffle offers. The pipeline tags every topic with both, so these are
  // not asked of the tags.
  final first = sentenceOrder.first;
  final tokens = _tokens(sentences[first]);
  final gap = target(tokens);
  String translationOf(int sentence) => sentences.length == translations.length
      ? translations[sentence]
      : _blank(source.exampleEn)
      ? ''
      : source.exampleEn;
  final translation = translationOf(first);
  final (before, answer, after) = _blankAt(tokens, gap);
  final distractors = _distractors(answer, source, text, random);

  items.add(
    GapFill(
      before: before,
      after: after,
      answer: answer,
      translation: translation,
    ),
  );

  // #330: *Pick the form* in another sentence than the gap fill's, whose
  // feedback would answer it: the example's next sentence, else one of the
  // course's with a form of the gap's sentence. Its word has two real wrong
  // forms, where one does.
  final used = <int>{first};
  final borrowed = <String>{};
  PickTheForm pick(List<String> words, int at, String english) {
    final (pickBefore, form, pickAfter) = _blankAt(words, at);
    return PickTheForm(
      before: pickBefore,
      after: pickAfter,
      options: <String>[
        form,
        ..._distractors(form, source, text, random).take(2),
      ]..shuffle(random),
      answer: form,
      translation: english,
    );
  }

  PickTheForm? fromExample({required bool real}) {
    for (final other in sentenceOrder.skip(1)) {
      if (used.contains(other)) continue;
      final words = _tokens(sentences[other]);
      final at = target(words, real: real);
      if (at < 0) continue;
      used.add(other);
      return pick(words, at, translationOf(other));
    }
    return null;
  }

  PickTheForm? fromCourse() {
    int rank(int at) => _rank(tokens, at, cues, tags);
    final ranked = <int>[
      for (var i = 0; i < tokens.length; i++)
        if (_bare(tokens[i]).length >= 2 && askable(_bare(tokens[i]))) i,
    ]..sort((a, b) => rank(b).compareTo(rank(a)));
    for (final i in ranked) {
      final form = _bare(tokens[i]);
      final elsewhere = <({String german, String english})>[
        for (final sentence in text.sentencesWith(form))
          if (!sentences.contains(sentence.german.trim()) &&
              !borrowed.contains(sentence.german))
            sentence,
      ];
      if (elsewhere.isEmpty) continue;
      final sentence = elsewhere[random.nextInt(elsewhere.length)];
      borrowed.add(sentence.german);
      final words = _tokens(sentence.german);
      final at = words.indexWhere((word) => _bare(word) == form);
      return pick(words, at, sentence.english);
    }
    return null;
  }

  // With no course, or a rule in English (a topic with no example), there
  // may be no other sentence: another word of the gap's, the gap's last.
  PickTheForm? elsewhere() =>
      fromExample(real: true) ?? fromCourse() ?? fromExample(real: false);
  PickTheForm besideGap() {
    final at = target(<String>[
      for (var i = 0; i < tokens.length; i++) i == gap ? '' : tokens[i],
    ]);
    return pick(
      tokens,
      at != gap && _bare(tokens[at]).length > 1 ? at : gap,
      translation,
    );
  }

  items.add(elsewhere() ?? besideGap());

  if (tags.intersection(errorTags).isNotEmpty) {
    final error =
        _errorFrom(source.watchOut, tokens) ??
        (
          target: gap,
          form: tokens[gap].replaceFirst(answer, distractors.first),
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

  if (source.levelCode == 'C1' || source.levelCode == 'C2') {
    final right = _recallOption(source.rule);
    // Distinct from the right one and from each other: two rules can open
    // alike, and a question with its answer twice has two right answers.
    final wrong = <String>{
      for (final rule in siblings)
        if (_recallOption(rule) != right) _recallOption(rule),
    }.toList()..shuffle(random);
    if (wrong.length >= 3) {
      final options = <String>[right, ...wrong.take(3)]..shuffle(random);
      items.add(
        RuleRecall(
          question: source.topic,
          options: options,
          answer: options.indexOf(right),
        ),
      );
    }
  }

  // At least three: a second gap fill from a sentence not asked yet if the
  // example has one, else another pick-the-form away from the gap's.
  if (items.length < 3) {
    for (final other in sentenceOrder) {
      if (used.contains(other)) continue;
      final second = _tokens(sentences[other]);
      final (secondBefore, secondAnswer, secondAfter) = _blankAt(
        second,
        target(second),
      );
      items.add(
        GapFill(
          before: secondBefore,
          after: secondAfter,
          answer: secondAnswer,
          translation: sentences.length == translations.length
              ? translations[other]
              : '',
        ),
      );
      break;
    }
  }
  if (items.length < 3) items.add(elsewhere() ?? besideGap());
  return items.take(maxItems).toList();
}

/// The example as L4 lists it: each German sentence with its translation
/// when the two split alike, else the whole example as one. Empty for a
/// topic with none ("—").
List<({String german, String? english})> examplePairs(
  String exampleDe,
  String exampleEn,
) {
  if (_blank(exampleDe)) return const <({String german, String? english})>[];
  final german = _sentences(exampleDe);
  final english = _blank(exampleEn) ? <String>[] : _sentences(exampleEn);
  if (german.length == english.length) {
    return <({String german, String? english})>[
      for (var i = 0; i < german.length; i++)
        (german: german[i], english: english[i]),
    ];
  }
  return <({String german, String? english})>[
    (german: exampleDe.trim(), english: _blank(exampleEn) ? null : exampleEn),
  ];
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

/// How often the topic's rule and *watch out* name each word, in lower case
/// and without the hyphen of "an-": what the gap is chosen by.
Map<String, int> _cues(GrammarSource source) {
  final cues = <String, int>{};
  for (final word in _words('${source.rule} ${source.watchOut}')) {
    final cue = word.toLowerCase().replaceAll(RegExp(r"^[-']+|[-']+$"), '');
    if (cue.length >= 2) cues[cue] = (cues[cue] ?? 0) + 1;
  }
  return cues;
}

/// The pronouns: a rule's examples name them ("Ich stehe um 7 auf"), but
/// they are seldom its point — a topic tagged `pronoun` is the exception.
const Set<String> _pronouns = <String>{
  'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'man', //
  'mich', 'dich', 'mir', 'dir', 'ihn', 'ihm', 'uns', 'euch',
};

/// How well the word at [at] practises the topic (#330): each time the rule
/// or *watch out* names it, one more for a form they name ("Könnten" for
/// "könnte"), two for an inflecting class's member when the topic is about
/// forms (the case-marked "meines"), less three for a pronoun the topic
/// isn't about (its tags or title name it).
int _rank(
  List<String> tokens,
  int at,
  Map<String, int> cues,
  Set<String> tags,
) {
  final lower = _bare(tokens[at]).toLowerCase();
  var rank = cues[lower] ?? 0;
  if (lower.length >= 4) {
    final stem = lower.substring(0, 4);
    if (cues.keys.any((cue) => cue != lower && cue.startsWith(stem))) rank++;
  }
  if (tags.intersection(errorTags).isNotEmpty &&
      _families.any((family) => family.contains(lower))) {
    rank += 2;
  }
  if (_pronouns.contains(lower) &&
      !tags.contains('pronoun') &&
      !tags.contains('title:$lower')) {
    rank -= 3;
  }
  return rank;
}

/// The token to blank: the best practice of the topic ([_rank]), the longer
/// of two alike. With [eligible], only a word it lets through, and -1 for
/// none.
int _target(
  List<String> tokens,
  Map<String, int> cues,
  Set<String> tags, [
  bool Function(String word)? eligible,
]) {
  var best = -1;
  var bestRank = 0;
  var bestLength = 0;
  for (var i = 0; i < tokens.length; i++) {
    final word = _bare(tokens[i]);
    if (word.length < 2) continue;
    if (eligible != null && !eligible(word)) continue;
    final rank = _rank(tokens, i, cues, tags);
    if (best < 0 ||
        rank > bestRank ||
        (rank == bestRank && word.length > bestLength)) {
      best = i;
      bestRank = rank;
      bestLength = word.length;
    }
  }
  return best < 0 && eligible == null ? 0 : best;
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
  <String>['ich', 'mich', 'mir'],
  <String>['du', 'dich', 'dir'],
  <String>['er', 'ihn', 'ihm'],
  <String>['wir', 'uns'],
];

/// Closed sets a word is chosen from rather than inflected (#330): the
/// prepositions, *am*/*im*/*um*, the da- and wo-compounds, the question
/// words. Their other members are the wrong forms, but a topic about forms
/// isn't about them.
const List<List<String>> _choices = <List<String>>[
  <String>['auf', 'an', 'in', 'über', 'unter', 'für', 'mit', 'von', 'zu'],
  <String>['bei', 'nach', 'aus', 'vor', 'seit', 'gegen', 'ohne', 'durch'],
  <String>['am', 'im', 'um', 'vom', 'zum', 'beim'],
  <String>['darauf', 'daran', 'darüber', 'dafür', 'damit', 'davon', 'dazu'],
  <String>['worauf', 'woran', 'worüber', 'wofür', 'womit', 'wovon', 'wozu'],
  <String>['wann', 'wo', 'wer', 'wie', 'warum', 'woher', 'wohin', 'ob'],
];

/// [word]'s wrong forms, in the order they are best: its classes' other
/// members, the forms the rule or *watch out* names, then endings and
/// umlauts changed. [real] are those the course uses (all, with no course),
/// in those three groups; [made] the rest, which may be no German at all
/// (#330: "warteen").
({List<List<String>> real, List<String> made}) _wrongForms(
  String word,
  GrammarSource source,
  CourseText course,
) {
  final lower = word.toLowerCase();
  final capital = word[0] == word[0].toUpperCase();
  final stem = lower.length > 3 ? lower.substring(0, 3) : lower;
  final members = <String>{
    for (final set in <List<String>>[..._families, ..._choices])
      if (set.contains(lower))
        for (final member in set)
          capital ? '${member[0].toUpperCase()}${member.substring(1)}' : member,
  };
  final named = <String>{
    for (final other in _words('${source.rule} ${source.watchOut}'))
      if (other.length > 2 &&
          other.toLowerCase().startsWith(stem) &&
          course.knows(other))
        other,
  };

  final changed = <String>{};
  final ending = RegExp(r'(en|er|es|em|st|e|n|t|s)$').firstMatch(word);
  final root = ending == null ? word : word.substring(0, ending.start);
  for (final end in <String>['e', 'en', 'er', 'es', 'em', 't', 'st', '']) {
    if ('$root$end'.length > 1) changed.add('$root$end');
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
    if (word.contains(plain)) changed.add(word.replaceFirst(plain, marked));
  }
  final seen = <String>{lower};
  List<String> fresh(Iterable<String> forms) => <String>[
    for (final form in forms)
      if (seen.add(form.toLowerCase())) form,
  ];
  // A member the course uses first: *würdet* is German, but "würde" is
  // what a learner has met.
  final real = <List<String>>[
    fresh(members.where(course.knows)),
    fresh(members),
    fresh(named),
    fresh(changed.where(course.knows)),
  ];
  return (real: real, made: fresh(changed));
}

/// Two or more wrong forms for [answer], shuffled, the real ones first: the
/// made ones only fill in for a word with too few.
List<String> _distractors(
  String answer,
  GrammarSource source,
  CourseText course,
  math.Random random,
) {
  final bare = _bare(answer);
  final (:real, :made) = _wrongForms(bare, source, course);
  return <String>[
    for (final group in <List<String>>[...real, made])
      ...group..shuffle(random),
  ].map((form) => answer.replaceFirst(bare, form)).toList();
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

/// A rule's first sentence as a recall option, cut at a word past 90
/// characters. Not at a colon: many C1/C2 rules open with a label —
/// "Features:", "Teil 1:" — that says nothing on its own.
String _recallOption(String rule) {
  final sentence = rule.split(RegExp(r'(?<=[.!?;])\s')).first.trim();
  if (sentence.length <= 90) return sentence;
  final cut = sentence.substring(0, 90);
  final space = cut.lastIndexOf(' ');
  return '${cut.substring(0, space > 0 ? space : 90)}…';
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
