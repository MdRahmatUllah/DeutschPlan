/// `docs/03-domain/grammar-practice.md`: one grammar topic into 3–5 practice
/// items, built from its rule, example and *watch out* — no hand-written
/// exercises — and checked against the rest of the course's German (#330).
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
/// examples use, to tell a real form from a made-up one ("warteen"); its
/// words and their forms, to tell another form of the answer's word from a
/// different word that looks like one ("bitter" is no form of *bitte*,
/// #406); and its example sentences, to practise a form in another sentence
/// than the gap fill's. [CourseText.none] knows no course: every form
/// passes, and there is no other sentence.
class CourseText {
  CourseText({
    Iterable<({String german, String? forms})> words =
        const <({String german, String? forms})>[],
    Iterable<String> texts = const <String>[],
    this.sentences = const <({String german, String english})>[],
  }) : _forms = <String>{
         for (final word in words)
           for (final form in _words('${word.german} ${word.forms ?? ''}'))
             form,
         for (final text in texts) ..._words(text),
         for (final sentence in sentences) ..._words(sentence.german),
       },
       _heads = <String>[for (final word in words) word.german],
       _listed = <String>[for (final word in words) word.forms ?? ''],
       _lemmas = _lemmaIndex(words),
       _byWord = _index(sentences);

  static final CourseText none = CourseText();

  final Set<String> _forms;

  /// The course's example sentences, with their English.
  final List<({String german, String english})> sentences;

  /// Whether [form] is German the course uses, as it writes it — "Sicht",
  /// not "sicht" (#406) — or capitalised to open a sentence. With no
  /// course, any form.
  bool knows(String form) =>
      _forms.isEmpty || _forms.contains(form) || _forms.contains(_lower(form));

  /// Each word the course lists, by its own words and forms: *heißen* under
  /// "heißen", "heißt" and "geheißen". Not the glue of a phrase or a
  /// perfect ("sich", "hat"), which every verb would share.
  final Map<String, Set<int>> _lemmas;

  static Map<String, Set<int>> _lemmaIndex(
    Iterable<({String german, String? forms})> words,
  ) {
    final index = <String, Set<int>>{};
    for (final (i, word) in words.indexed) {
      for (final form in _words('${word.german} ${word.forms ?? ''}')) {
        if (!_glue.contains(form)) (index[form] ??= <int>{}).add(i);
      }
    }
    return index;
  }

  Set<int> _lemmasOf(String form) => <int>{
    ...?_lemmas[form],
    ...?_lemmas[_lower(form)],
  };

  /// Each word's headword and its listed forms, by the index [_lemmas]
  /// gives.
  final List<String> _heads;
  final List<String> _listed;

  /// The words [form] can be a form of: those that list it, else, when the
  /// course writes it at all, the one its regular ending points to by its
  /// headword — not every phrase that lists it ("Es tut mir leid" for
  /// "leide") — a verb's ("spreche" → *sprechen*), a du imperative's, its er
  /// form less -t ("sprich" → "spricht" → *sprechen*), else an adjective's
  /// ("heißer" → *heiß*, not *heißen*).
  Set<int> _wordsOf(String form) {
    final listed = _lemmasOf(form);
    if (listed.isNotEmpty || !knows(form)) return listed;
    final ending = RegExp(r'(en|er|es|em|st|e|n|t|s)$').firstMatch(form);
    final end = ending?.group(0) ?? '';
    final root = form.substring(0, form.length - end.length);
    Set<int> headed(String head) => <int>{
      for (final i in _lemmasOf(head))
        if (_heads[i].toLowerCase() == head.toLowerCase()) i,
    };
    final verb = <int>{
      if (const <String>{'e', 'st', 't', 'en', 'n'}.contains(end)) ...<int>{
        ...headed('${root}en'),
        ...headed('${root}n'),
      },
      if (!form.endsWith('t'))
        for (final i in _lemmasOf('${form}t'))
          if (_heads[i].endsWith('n')) i,
    };
    if (verb.isNotEmpty) return verb;
    return <int>{
      if (const <String>{'', 'e', 'er', 'es', 'em', 'en'}.contains(end))
        ...headed(root),
    };
  }

  /// The words [form] can be, by headword: not a phrase ("Bescheid
  /// wissen"), and a separable verb under its base when the course lists
  /// both ("spricht" is *sprechen*'s, not also *ansprechen*'s).
  Set<String> _readingsOf(String form) {
    final heads = <String>{
      for (final i in _wordsOf(form))
        if (!_heads[i].contains(' ')) _heads[i],
    };
    return <String>{
      for (final head in heads)
        if (!heads.any((base) => base != head && head.endsWith(base))) head,
    };
  }

  /// Whether [form] is another form of [answer]'s word: of the same word
  /// the course lists (#406). An answer two words write alike ("weiß" of
  /// *wissen*, and the colour) takes a form of both, so none of the other's.
  /// With no course, any form is.
  bool sameWord(String answer, String form) {
    if (_lemmas.isEmpty) return true;
    final its = <String>{for (final i in _wordsOf(form)) _heads[i]};
    final readings = _readingsOf(answer);
    return readings.length > 1
        ? its.containsAll(readings)
        : its.any(
            <String>{for (final i in _wordsOf(answer)) _heads[i]}.contains,
          );
  }

  /// The forms the course lists for [answer]'s word, as it writes them: its
  /// headword, and each listed form's verb or word, not its glue ("hat",
  /// "am") nor its separable prefix ("räumt auf"). Those of both words two
  /// write alike, as [sameWord]. None with no course.
  Iterable<String> formsOf(String answer) {
    final readings = _readingsOf(answer);
    final byHead = <String, Set<String>>{};
    for (final i in _wordsOf(answer)) {
      if (!readings.contains(_heads[i])) continue;
      (byHead[_heads[i]] ??= <String>{_heads[i]}).addAll(<String>[
        for (final listed in _listed[i].split('·'))
          ?_words(listed).where((word) => !_glue.contains(word)).firstOrNull,
      ]);
    }
    return byHead.isEmpty
        ? const <String>[]
        : byHead.values.reduce((a, b) => a.intersection(b));
  }

  final Map<String, List<int>> _byWord;

  /// The sentences by the words in them, split as *Pick the form* blanks
  /// them — a token's letters — so each one listed has the word to blank:
  /// "konnte/könnte" is one token, and lists under neither (#386).
  static Map<String, List<int>> _index(
    List<({String german, String english})> sentences,
  ) {
    final index = <String, List<int>>{};
    for (final (i, sentence) in sentences.indexed) {
      for (final word in _tokens(sentence.german).map(_bare).toSet()) {
        (index[word] ??= <int>[]).add(i);
      }
    }
    return index;
  }

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
  final sentences = _sentences(example, german: !_blank(source.exampleDe));
  final translations = _blank(source.exampleDe)
      ? <String>[]
      : _sentences(source.exampleEn, german: false);
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
  // #515: the forms a *Pick the form* has asked. A set never drills one
  // twice ("spreche" in two sentences): a short set rather than a repeat.
  final asked = <String>{};
  bool askedAlready(String word) => asked.contains(_bare(word).toLowerCase());
  PickTheForm pick(List<String> words, int at, String english) {
    final (pickBefore, form, pickAfter) = _blankAt(words, at);
    asked.add(_bare(form).toLowerCase());
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
      if (at < 0 || askedAlready(words[at])) continue;
      used.add(other);
      return pick(words, at, translationOf(other));
    }
    return null;
  }

  // A word of [tokens] in another sentence of the course.
  PickTheForm? borrowFrom(List<String> tokens, {required bool cued}) {
    int rank(int at) => _rank(tokens, at, cues, tags);
    final ranked =
        <int>[
          for (var i = 0; i < tokens.length; i++)
            if (_bare(tokens[i]).length >= 2 &&
                (!cued || rank(i) > 0) &&
                askable(_bare(tokens[i])))
              i,
        ]..sort((a, b) {
          // The longer of two alike, as the gap is chosen.
          final byRank = rank(b).compareTo(rank(a));
          return byRank != 0
              ? byRank
              : _bare(tokens[b]).length.compareTo(_bare(tokens[a]).length);
        });
    for (final i in ranked) {
      final form = _bare(tokens[i]);
      if (askedAlready(form)) continue;
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
      // Found: the index splits sentences as this does.
      final at = words.indexWhere((word) => _bare(word) == form);
      return pick(words, at, sentence.english);
    }
    return null;
  }

  // [cued]: a word the rule or *watch out* points at, which practises it in
  // the borrowed sentence too, before any word ("Die Steuer-ID kommt per
  // Post." practises no indirect question, #406); either before an example's
  // word with made-up forms only.
  PickTheForm? fromCourse({required bool cued}) {
    // The gap's sentence's words first, then the example's other ones'.
    for (final order in sentenceOrder) {
      if (borrowFrom(_tokens(sentences[order]), cued: cued) case final item?) {
        return item;
      }
    }
    return null;
  }

  // With no course, or a rule in English (a topic with no example), there
  // may be no other sentence: another word of the gap's, the gap's last.
  PickTheForm? elsewhere() =>
      fromExample(real: true) ??
      fromCourse(cued: true) ??
      fromCourse(cued: false) ??
      fromExample(real: false);
  PickTheForm? besideGap() {
    final at = target(<String>[
      for (var i = 0; i < tokens.length; i++) i == gap ? '' : tokens[i],
    ]);
    final chosen = at != gap && _bare(tokens[at]).length > 1 ? at : gap;
    return askedAlready(tokens[chosen])
        ? null
        : pick(tokens, chosen, translation);
  }

  // A topic with no German example practises its English rule: a form of
  // "sentence" to pick is no German, so it asks gap fills only (#386).
  final german = !_blank(source.exampleDe);
  if (german) {
    if ((elsewhere() ?? besideGap()) case final item?) items.add(item);
  }

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

  // At least three where the sentences allow: gap fills from those not
  // asked yet, then, with a German example, another pick-the-form away from
  // the gap's.
  for (final other in sentenceOrder) {
    if (items.length >= 3) break;
    if (used.contains(other)) continue;
    used.add(other);
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
        translation: translationOf(other),
      ),
    );
  }
  if (items.length < 3 && german) {
    if ((elsewhere() ?? besideGap()) case final item?) {
      items.add(item);
    } else {
      // ponytail: no other form to ask, which happens only without the
      // course (a failed read, CourseText.none): the old repeat, so the set
      // keeps FR-L15-01's three. The real course always has another (#515).
      asked.clear();
      if ((elsewhere() ?? besideGap()) case final item?) items.add(item);
    }
  }
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
  final german = _sentences(exampleDe, german: true);
  final english = _blank(exampleEn)
      ? <String>[]
      : _sentences(exampleEn, german: false);
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

/// The example's sentences (#406): split after . ! ? before a capital, and
/// on " / " only between whole sentences ("Wie heißen Sie? / Wie heißt
/// du?"), not between two forms of one ("dass er komme / kommt."). German
/// not after a number's dot, an ordinal ("der 17. September"), nor before a
/// number, which follows an abbreviation ("§ 5 Abs. 2 vorliegen"); English
/// before one too ("… September. 3 October …"), and after one ("built in
/// 1990. The office …").
List<String> _sentences(String text, {required bool german}) => <String>[
  for (final part in text.split(
    german
        ? RegExp(r'(?<![0-9]\.)(?<=[.!?])\s+(?=[A-ZÄÖÜ„])')
        : RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])'),
  ))
    for (final sentence in _alternatives(part.trim()))
      if (sentence.isNotEmpty) sentence,
];

/// [sentence] split at " / " when each side is a sentence of its own: a
/// capital, and three words at least.
List<String> _alternatives(String sentence) {
  final sides = sentence.split(RegExp(r'\s+/\s+'));
  bool whole(String side) =>
      _tokens(side).length >= 3 && RegExp('^[A-ZÄÖÜ„]').hasMatch(side);
  return sides.length > 1 && sides.every(whole) ? sides : <String>[sentence];
}

/// A sentence's tokens, punctuation left on the word it follows.
List<String> _tokens(String sentence) =>
    sentence.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();

/// [word] as it would be written inside a sentence: "Könnten" → "könnten".
String _lower(String word) =>
    word.isEmpty ? word : '${word[0].toLowerCase()}${word.substring(1)}';

/// A phrase's or a perfect's glue, which is no word of its own there.
const Set<String> _glue = <String>{
  'sich', 'hat', 'ist', 'sind', 'haben', 'sein', 'wird', 'der', 'die', //
  'das', 'ein', 'eine', 'zu', 'etw', 'jdn', 'jdm', 'am',
};

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

/// A preposition and article in one, and the preposition it is.
const Map<String, String> _contractions = <String, String>{
  'vom': 'von', 'zum': 'zu', 'zur': 'zu', 'im': 'in', 'ins': 'in', //
  'am': 'an', 'ans': 'an', 'beim': 'bei', 'aufs': 'auf',
};

/// The separable prefixes, which a verb leaves at the end of its clause.
const Set<String> _prefixes = <String>{
  'ab', 'an', 'auf', 'aus', 'ein', 'mit', 'nach', 'vor', 'zu', 'zurück', //
  'weg', 'her', 'hin', 'los', 'fest', 'weiter', 'teil',
};

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
  // "vom" is *von* the rule names, in a topic about prepositions: the
  // English rules' "in" and "an" are no cue (#406).
  var rank =
      (cues[lower] ?? 0) +
      (tags.contains('preposition') ? cues[_contractions[lower]] ?? 0 : 0);
  // "ab" closing "hängt … ab" is its *abhängen* (#406); not "an" of
  // "anderen".
  final closes = at == tokens.length - 1 || _bare(tokens[at]) != tokens[at];
  if (closes &&
      _prefixes.contains(lower) &&
      cues.keys.any(
        (cue) =>
            cue.length >= lower.length + 4 &&
            cue.startsWith(lower) &&
            cue.endsWith('en'),
      )) {
    rank++;
  }
  if (lower.length >= 4) {
    final stem = lower.substring(0, 4);
    if (cues.keys.any((cue) => cue != lower && cue.startsWith(stem))) rank++;
  }
  // Not an article in a topic about prepositions, not cases: "Ich bewerbe
  // mich um [die] Stelle" practises *um* (#406).
  final articles = _families.take(3).any((family) => family.contains(lower));
  if (tags.intersection(errorTags).isNotEmpty &&
      _families.any((family) => family.contains(lower)) &&
      !(articles && tags.contains('preposition') && !tags.contains('case'))) {
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
/// prepositions, *am*/*im*/*um*, the da- and wo-compounds. Their other
/// members are the wrong forms, but a topic about forms isn't about them.
/// Not the question words: "[Wo] kann man hier parken?" takes *warum* and
/// *wann* too, and an item has one right answer (#386).
const List<List<String>> _choices = <List<String>>[
  <String>['auf', 'an', 'in', 'über', 'unter', 'für', 'mit', 'von', 'zu'],
  <String>['bei', 'nach', 'aus', 'vor', 'seit', 'gegen', 'ohne', 'durch'],
  <String>['am', 'im', 'um', 'vom', 'zum', 'beim'],
  <String>['darauf', 'daran', 'darüber', 'dafür', 'damit', 'davon', 'dazu'],
  <String>['worauf', 'woran', 'worüber', 'wofür', 'womit', 'wovon', 'wozu'],
];

/// [word]'s wrong forms, in the order they are best: its classes' other
/// members, the forms the rule or *watch out* names, then endings and
/// umlauts changed, and the forms the course lists for its word. [real] are
/// those the course uses as forms of the same word (all, with no course), in
/// those groups; [made] the changed ones the course never writes, which may
/// be no German, but are never another word (#330: "warteen"; #406:
/// "bitter").
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
  // The rule's forms of the same word, and *watch out*'s error as it is.
  bool alike(String other) =>
      other.length > 2 &&
      other.toLowerCase().startsWith(stem) &&
      course.knows(other);
  final named = <String>{
    for (final other in _words(source.rule))
      if (alike(other) && course.sameWord(word, other)) other,
    for (final other in _words(source.watchOut))
      if (alike(other)) other,
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
    // The forms the course lists for the answer's word: "wartet" for
    // *Warten*, "spricht" for *Sprich* (#406).
    fresh(<String>[
      for (final form in course.formsOf(word))
        capital ? '${form[0].toUpperCase()}${form.substring(1)}' : form,
    ]),
    // Changed endings the course writes, of the same word: not "bitter"
    // for *bitte*, nor "sprecher" for *spreche* (#406).
    fresh(
      changed.where(
        (form) => course.knows(form) && course.sameWord(word, form),
      ),
    ),
  ];
  // Made-up forms are no German, never another word's (#406: "weiße" for
  // *weiß* of *wissen*).
  return (
    real: real,
    made: fresh(changed.where((form) => !course.knows(form))),
  );
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
