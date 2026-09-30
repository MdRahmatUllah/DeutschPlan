import 'dart:math';

import 'package:sogda/domain/answer_check.dart';
import 'package:sogda/domain/compare_set.dart';
import 'package:sogda/domain/fsrs.dart';
import 'package:sogda/domain/plan_engine.dart' show PlanDate, daysBetween;

/// What a quiz asks (`quiz-engine.md`). What `QuizArgs` and
/// `quiz_attempts.direction` carry is [askWire]'s: a meaning direction with
/// its language, the others by their names.
enum QuizDirection {
  /// German → a meaning language, the item's [QuizItem.lang] (#1120).
  toMeaning,

  /// A meaning language → German.
  fromMeaning,
  articles,
  listening,
  forms,

  /// A round-robin of the others, per word, skipping those that don't apply.
  mixed,

  /// W2's *Quiz these* (FR-W2-03): which member of a near-synonym set a
  /// sentence is missing, picked from the members' tiles. Built from the
  /// set, never a word at a time, so no mix rotates into it.
  compare;

  static QuizDirection parse(String wire) => QuizDirection.values.firstWhere(
    (direction) => direction.name == wire,
    orElse: () => throw ArgumentError.value(wire, 'direction'),
  );
}

/// A quiz's direction and, for a meaning direction, its language (#1120).
typedef QuizAsk = ({QuizDirection direction, String? lang});

/// [direction] as `QuizArgs` and `quiz_attempts` carry it: `de>ru` is German
/// → Russian, `ru>de` Russian → German, and the others are their names.
String askWire(QuizDirection direction, [String? lang]) => switch (direction) {
  QuizDirection.toMeaning => 'de>$lang',
  QuizDirection.fromMeaning => '$lang>de',
  _ => direction.name,
};

/// [wire] read back. Before #1120 the meaning directions were `deEn`,
/// `deBn` and `enDe`, which asked German → English, German → Bangla and the
/// learner's meaning language → German: a stored quiz and its *Retry* ask
/// the same, [primary] giving the learner's first language (asked only for
/// `enDe`). Throws on a wire no direction has.
QuizAsk parseAsk(String wire, {required String Function() primary}) =>
    switch (wire) {
      'deEn' => (direction: QuizDirection.toMeaning, lang: 'en'),
      'deBn' => (direction: QuizDirection.toMeaning, lang: 'bn'),
      'enDe' => (direction: QuizDirection.fromMeaning, lang: primary()),
      _ when wire.startsWith('de>') && wire.length > 3 => (
        direction: QuizDirection.toMeaning,
        lang: wire.substring(3),
      ),
      _ when wire.endsWith('>de') && wire.length > 3 => (
        direction: QuizDirection.fromMeaning,
        lang: wire.substring(0, wire.length - 3),
      ),
      _ => (direction: QuizDirection.parse(wire), lang: null),
    };

/// Where a quiz's words come from (BR-QUIZ-01).
enum QuizSource {
  /// The step in `ref`'s learned words: the default.
  stepLearned,
  allLearned,

  /// The category whose id is `ref`.
  category,

  /// The words whose uids `ref` lists, comma-separated: L9's *Retry
  /// mistakes*. With [QuizDirection.compare], the set word whose uid `ref`
  /// is: W2's *Quiz these*.
  compareSet;

  static QuizSource parse(String wire) => QuizSource.values.firstWhere(
    (source) => source.name == wire,
    orElse: () => throw ArgumentError.value(wire, 'source'),
  );
}

/// Which form a forms item asks for.
enum FormLabel { plural, thirdPerson, perfekt, comparative, superlative }

/// A word as the builder sees it: what it asks on, and what it ranks on.
class QuizWord {
  const QuizWord({
    required this.uid,
    required this.german,
    required this.english,
    required this.step,
    this.article,
    this.pos,
    this.bangla,
    this.forms,
    this.synonyms,
    this.stability = 0,
    this.lastReview,
    this.meanings = const <String, String>{},
  });

  final String uid;
  final String german;
  final String english;

  /// The sublevel code, e.g. `A1.1`.
  final String step;
  final String? article;
  final String? pos;
  final String? bangla;

  /// The authored `forms` cell: `Häuser`, `-en`, `geht · ist gegangen`,
  /// `älter · am ältesten`.
  final String? forms;

  /// The authored `synonyms_register` cell: German near-synonyms and notes.
  final String? synonyms;
  final double stability;

  /// The local day it was last reviewed; null for a word never reviewed.
  final PlanDate? lastReview;

  /// Its meanings in the course's languages beyond English and Bangla, by
  /// code (#1120): what a quiz in them asks. Empty when none is chosen.
  final Map<String, String> meanings;

  /// Its meaning in [lang]: its own English and Bangla, the others from
  /// [meanings]; null where it has none.
  String? meaningIn(String lang) => switch (lang) {
    'en' => english,
    'bn' => bangla,
    _ => meanings[lang],
  };

  /// "der Mietvertrag", or "arbeiten".
  String get headword => article == null ? german : '$article $german';

  /// A phrase with no article of its own: a leading "Das" or "den" is one of
  /// its words, typed like the rest (`checkGerman`'s phrase, #687 AN-10).
  bool get isPhrase => pos == 'phrase' && article == null;

  /// This word as an EN → DE answer.
  GermanAnswer get answer => (german: headword, phrase: isPhrase);
}

/// What the builder needs from the database. Pure Dart, like the plan
/// engine's `PlanStore`, so every choice it makes is testable without one.
abstract interface class QuizStore {
  /// The learned words (learning or done, so never suspended) of [source].
  Future<List<QuizWord>> learned(QuizSource source, {String? ref});

  /// Every word of [step], whatever its status: the distractor pool.
  Future<List<QuizWord>> stepWords(String step);

  /// W2's set word [uid] with its members' words; null for none.
  Future<CompareSet?> compareSet(String uid);

  /// The course's words by meaning cell, English or Bangla, for the cells
  /// two words or more share: EN → DE's other right answers (#832).
  Future<Map<String, List<QuizWord>>> sharedMeanings();
}

/// One question.
class QuizItem {
  const QuizItem({
    required this.ord,
    required this.wordUid,
    required this.direction,
    required this.prompt,
    required this.expected,
    this.options = const <String>[],
    this.form,
    this.hint,
    this.phrase = false,
    this.also = const <GermanAnswer>[],
    this.lang,
  });

  /// 1-based, as `quiz_answers.ord`.
  final int ord;
  final String wordUid;

  /// Never [QuizDirection.mixed]: a mixed quiz's items each have their own.
  final QuizDirection direction;

  /// The meaning language of a [QuizDirection.toMeaning] or
  /// [QuizDirection.fromMeaning] item (#1120); null for the others.
  final String? lang;

  /// What is shown: the headword (DE → a meaning, listening — where the
  /// runner plays it), the meaning (a meaning → DE), the noun without its
  /// article (articles), or the infinitive / singular / base form (forms,
  /// with [form]).
  final String prompt;

  /// What `answer_check` compares against: a meaning list for DE → a
  /// meaning, a headword for a meaning → DE and listening, `der|die|das`, or
  /// the form.
  final String expected;

  /// Four tiles for the multiple-choice layout — [expected] and three
  /// distractors in a seeded order — on the meaning directions. Empty for
  /// the others, whose answers are typed or fixed.
  final List<String> options;

  /// Which form a forms item asks for.
  final FormLabel? form;

  /// The second meaning language's meaning under a meaning → DE prompt, for
  /// a learner who reads two (`quiz.md`: "EN/BN prompt"); null otherwise.
  final String? hint;

  /// A meaning → DE and listening: [expected] is a phrase whose leading
  /// article-like word is typed like the rest ([QuizWord.isPhrase]).
  final bool phrase;

  /// A meaning → DE: the course's other words whose meaning cell is
  /// [prompt], each as right as [expected] ("you": du, dich, Sie; #832).
  final List<GermanAnswer> also;

  /// Whether the runner asks with the tiles rather than a field: DE →
  /// বাংলা, since typing Bangla needs a Bangla keyboard, which a learner of
  /// German can't be assumed to have; and a compare item, whose tiles are
  /// its set's members. The other meaning items are typed, as `quiz.md`
  /// lays them out: a learner who reads Russian or Polish has its keyboard.
  bool get tiles =>
      direction == QuizDirection.compare ||
      direction == QuizDirection.toMeaning &&
          lang == 'bn' &&
          options.length == 4;
}

class Quiz {
  const Quiz({
    required this.direction,
    required this.source,
    required this.seed,
    required this.items,
    this.sourceRef,
    this.lang,
  });

  final QuizDirection direction;

  /// A meaning direction's language (#1120).
  final String? lang;
  final QuizSource source;
  final String? sourceRef;
  final int seed;
  final List<QuizItem> items;
}

/// Builds a quiz (`docs/03-domain/quiz-engine.md`, #81).
class QuizBuilder {
  QuizBuilder(
    this._store, {
    Fsrs? fsrs,
    this.languages = const <String>['en', 'bn'],
  }) : assert(languages.length == 1 || languages.length == 2),
       _fsrs = fsrs ?? Fsrs();

  final QuizStore _store;
  final Fsrs _fsrs;

  /// The learner's meaning languages, primary first (#1081). A mixed quiz
  /// asks German → each and the primary → German (#339), whose prompt has
  /// the second's meaning under it (#387).
  final List<String> languages;

  /// A mixed quiz's turns: German → the primary, → the second language (a
  /// turn a learner with one skips), the primary → German, then the others.
  List<QuizAsk> get rotation => <QuizAsk>[
    (direction: QuizDirection.toMeaning, lang: languages.first),
    (
      direction: QuizDirection.toMeaning,
      lang: languages.length > 1 ? languages[1] : null,
    ),
    (direction: QuizDirection.fromMeaning, lang: languages.first),
    (direction: QuizDirection.articles, lang: null),
    (direction: QuizDirection.listening, lang: null),
    (direction: QuizDirection.forms, lang: null),
  ];

  /// [length] questions at most — fewer when fewer words qualify. The same
  /// [seed] over the same progress builds the same quiz, which is what lets
  /// `quiz_attempts.seed` rebuild it. [lang] is a meaning direction's
  /// language (#1120).
  Future<Quiz> build({
    required QuizDirection direction,
    required QuizSource source,
    required int length,
    required int seed,
    required PlanDate today,
    String? sourceRef,
    String? lang,
  }) async {
    if (direction == QuizDirection.compare) {
      final set = await _store.compareSet(sourceRef ?? '');
      return Quiz(
        direction: direction,
        source: source,
        sourceRef: sourceRef,
        seed: seed,
        lang: lang,
        items: set == null
            ? const <QuizItem>[]
            : compareQuizItems(
                compareMembers(set),
                setUid: set.word.uid,
                seed: seed,
                length: length,
              ),
      );
    }
    final random = Random(seed);
    final learned = await _store.learned(source, ref: sourceRef);
    final eligible = direction == QuizDirection.mixed
        ? learned
        : learned.where((word) => applies(direction, word, lang)).toList();
    final picked = pickWords(
      eligible,
      length: length,
      today: today,
      fsrs: _fsrs,
      random: random,
    );

    final shared = await _store.sharedMeanings();
    final pools = <String, List<QuizWord>>{};
    Future<List<QuizWord>> poolFor(String step) async =>
        pools[step] ??= await _store.stepWords(step);

    final items = <QuizItem>[];
    for (final (i, word) in picked.indexed) {
      final asked = direction == QuizDirection.mixed
          ? mixedDirection(i, word, rotation)
          : (direction: direction, lang: lang);
      items.add(
        await _item(
          i + 1,
          word,
          asked,
          random,
          () async => <QuizWord>[...await poolFor(word.step), ...learned],
          shared,
        ),
      );
    }
    return Quiz(
      direction: direction,
      source: source,
      sourceRef: sourceRef,
      seed: seed,
      lang: lang,
      items: items,
    );
  }

  Future<QuizItem> _item(
    int ord,
    QuizWord word,
    QuizAsk ask,
    Random random,
    Future<List<QuizWord>> Function() pool,
    Map<String, List<QuizWord>> shared,
  ) async {
    Future<List<String>> tiles(String Function(QuizWord) value) async {
      final wrong = distractors(word, await pool(), value, random);
      return <String>[value(word), ...wrong]..shuffle(random);
    }

    final direction = ask.direction;
    switch (direction) {
      case QuizDirection.toMeaning:
        final lang = ask.lang!;
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          lang: lang,
          prompt: word.headword,
          expected: word.meaningIn(lang)!,
          options: await tiles((w) => w.meaningIn(lang) ?? ''),
        );
      case QuizDirection.fromMeaning:
        // #387: in the learner's meaning language, as the exam's Reverse,
        // English where the word has none in it; and, for a learner who
        // reads two, the other one's meaning under it.
        final lang = ask.lang!;
        final asked = word.meaningIn(lang);
        final prompt = (asked ?? '').trim().isNotEmpty ? asked! : word.english;
        final other = languages.length == 2 && languages.contains(lang)
            ? languages.firstWhere((l) => l != lang)
            : null;
        final hint = other == null ? null : word.meaningIn(other);
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          lang: lang,
          prompt: prompt,
          expected: word.headword,
          options: await tiles((w) => w.headword),
          hint: hint,
          phrase: word.isPhrase,
          also: otherAnswers(
            word,
            prompt,
            shared,
            hint: other == null || hint == null
                ? null
                : (lang: other, text: hint),
          ),
        );
      case QuizDirection.articles:
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.german,
          expected: word.article!,
        );
      case QuizDirection.listening:
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.headword,
          expected: word.headword,
          phrase: word.isPhrase,
        );
      case QuizDirection.forms:
        final forms = parseForms(word);
        final (label, form) = forms[random.nextInt(forms.length)];
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.german,
          expected: form,
          form: label,
        );
      case QuizDirection.mixed:
        throw StateError('a mixed item takes the direction it rotated to');
      case QuizDirection.compare:
        throw StateError('a compare item is built from its set');
    }
  }
}

/// FR-L8-02: [given] against [item], checked the way its direction asks
/// (`quiz-engine.md`'s table): meanings for DE → EN and DE → বাংলা, German
/// with BR-ANS-02's article rules for EN → DE and listening, the article
/// alone, or the form.
Verdict grade(QuizItem item, String given) => switch (item.direction) {
  // A tile is the answer or it isn't. Its text is the whole meaning cell,
  // which `checkMeaning` would split into synonyms and match none of.
  _ when item.tiles => given == item.expected ? Verdict.correct : Verdict.wrong,
  QuizDirection.toMeaning => checkMeaning(given, item.expected),
  QuizDirection.fromMeaning || QuizDirection.listening => checkGerman(
    given,
    item.expected,
    phrase: item.phrase,
    also: item.also,
  ),
  QuizDirection.articles => checkArticle(given, item.expected),
  QuizDirection.forms => checkForm(given, item.expected),
  QuizDirection.compare =>
    given == item.expected ? Verdict.correct : Verdict.wrong,
  QuizDirection.mixed => throw StateError('an item has its own direction'),
};

/// A meaning → DE's other right answers when [word] is asked by [prompt]:
/// the course's other words whose meaning cell it is, from
/// [QuizStore.sharedMeanings] (#832). Under a [hint] (a learner who reads
/// two languages), only those whose meaning in its language it is too:
/// "you" over তুমি is du, not Sie.
List<GermanAnswer> otherAnswers(
  QuizWord word,
  String prompt,
  Map<String, List<QuizWord>> shared, {
  ({String lang, String text})? hint,
}) => <GermanAnswer>[
  for (final other in shared[prompt] ?? const <QuizWord>[])
    if (other.uid != word.uid &&
        (hint == null || other.meaningIn(hint.lang) == hint.text))
      other.answer,
];

/// Item [index] of a mixed quiz: the next of [rotation]'s turns that
/// applies to [word]; a meaning turn without a language is skipped. The
/// meaning → DE turn always applies, so there is always one.
QuizAsk mixedDirection(int index, QuizWord word, List<QuizAsk> rotation) {
  for (var k = 0; k < rotation.length; k++) {
    final ask = rotation[(index + k) % rotation.length];
    final meaning =
        ask.direction == QuizDirection.toMeaning ||
        ask.direction == QuizDirection.fromMeaning;
    if (meaning && ask.lang == null) continue;
    if (applies(ask.direction, word, ask.lang)) return ask;
  }
  return rotation.firstWhere((a) => a.direction == QuizDirection.fromMeaning);
}

/// Whether [word] can be asked in [direction] (`quiz-engine.md`: articles
/// needs an article, forms a parsable `forms` cell, German → a meaning
/// language the word's meaning in [lang]).
bool applies(QuizDirection direction, QuizWord word, [String? lang]) =>
    switch (direction) {
      QuizDirection.fromMeaning || QuizDirection.listening => true,
      QuizDirection.mixed => true,
      QuizDirection.compare => false,
      QuizDirection.toMeaning =>
        lang != null && (word.meaningIn(lang) ?? '').trim().isNotEmpty,
      QuizDirection.articles => const <String>{
        'der',
        'die',
        'das',
      }.contains(word.article),
      QuizDirection.forms => parseForms(word).isNotEmpty,
    };

/// The `(label, form)` pairs in [word]'s `forms` cell.
///
/// - A noun (or any word with an article): one form, its plural. `Häuser`
///   is the plural itself; `-en` is an ending on the singular. Some C1/C2
///   nouns carry their article inside `german` (#287), so `pos` counts too.
/// - A verb or phrase: `geht · ist gegangen`, the 3rd person and Perfekt.
/// - An adjective or adverb: `älter · am ältesten`, comparative and
///   superlative.
///
/// Anything else is not asked. content.db's four verb cells with three parts
/// (`erklärt · erläutert · legt dar`) are synonym sets, not forms.
List<(FormLabel, String)> parseForms(QuizWord word) {
  final parts = (word.forms ?? '')
      .split('·')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if ((word.article != null || word.pos == 'noun') && parts.length == 1) {
    final plural = parts.single.startsWith('-')
        ? '${word.german}${parts.single.substring(1)}'
        : parts.single;
    return <(FormLabel, String)>[(FormLabel.plural, plural)];
  }
  if (parts.length != 2) return const <(FormLabel, String)>[];
  return switch (word.pos) {
    'verb' || 'phrase' => <(FormLabel, String)>[
      (FormLabel.thirdPerson, parts[0]),
      (FormLabel.perfekt, parts[1]),
    ],
    'adj' || 'adv' => <(FormLabel, String)>[
      (FormLabel.comparative, parts[0]),
      (FormLabel.superlative, parts[1]),
    ],
    _ => const <(FormLabel, String)>[],
  };
}

/// Up to [length] of [eligible], preferring the lowest retrievability so a
/// quiz doubles as revision, in a seeded order.
///
/// The words are ranked by retrievability on [today] and the quiz is drawn,
/// shuffled, from the weakest twice-[length]: the same words don't come back
/// every time, and the ones most likely forgotten always dominate.
// ponytail: a fixed 2× window; weight by retrievability if quizzes feel samey.
List<QuizWord> pickWords(
  List<QuizWord> eligible, {
  required int length,
  required PlanDate today,
  required Fsrs fsrs,
  required Random random,
}) {
  if (length <= 0 || eligible.isEmpty) return const <QuizWord>[];
  double recall(QuizWord word) => word.lastReview == null
      ? 0
      : fsrs.retrievability(
          daysBetween(word.lastReview!, today),
          word.stability,
        );
  final ranked =
      <(double, QuizWord)>[for (final word in eligible) (recall(word), word)]
        ..sort((a, b) {
          final byRecall = a.$1.compareTo(b.$1);
          return byRecall != 0 ? byRecall : a.$2.uid.compareTo(b.$2.uid);
        });
  final window = <QuizWord>[
    for (final (_, word) in ranked.take(length * 2)) word,
  ]..shuffle(random);
  return window.take(length).toList();
}

/// Three wrong answers for [answer]'s multiple-choice tiles, as [value] shows
/// them: the same part of speech and step where the [pool] allows, never a
/// synonym of the answer, never two alike.
List<String> distractors(
  QuizWord answer,
  List<QuizWord> pool,
  String Function(QuizWord) value,
  Random random, {
  int count = 3,
}) {
  // Rank first, check late (#291): the pool is a step plus every learned
  // word — thousands late in the course — and the synonym check is regex
  // work. Ranking is cheap; the checks run only until [count] are found.
  final candidates = <QuizWord>[
    for (final word in pool)
      if (word.uid != answer.uid) word,
  ]..shuffle(random);
  // Stably sorted by closeness, so among equally close words the order is
  // the seed's and the same quiz gets the same tiles.
  int closeness(QuizWord word) =>
      (word.pos == answer.pos ? 0 : 2) + (word.step == answer.step ? 0 : 1);
  final ranked = <(int, int, QuizWord)>[
    for (final (i, word) in candidates.indexed) (closeness(word), i, word),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));

  final seen = <String>{value(answer).trim().toLowerCase()};
  final meanings = _meanings(answer);
  final picked = <String>[];
  for (final (_, _, word) in ranked) {
    final shown = value(word).trim().toLowerCase();
    if (shown.isEmpty || seen.contains(shown)) continue;
    if (_synonyms(answer, meanings, word)) continue;
    seen.add(shown);
    picked.add(value(word));
    if (picked.length == count) break;
  }
  return picked;
}

/// [w]'s meanings as a synonym check compares them: lower case, no "to ".
Set<String> _meanings(QuizWord w) => senses(w.english);

/// Whether [a] (whose [meanings] are given) and [b] would both be right: a
/// meaning they share, or one named in the other's synonyms cell.
bool _synonyms(QuizWord a, Set<String> meanings, QuizWord b) {
  if (meanings.intersection(_meanings(b)).isNotEmpty) return true;
  if (_sameBangla(a.bangla, b.bangla)) return true;
  // #1120: a Russian or Polish tile that reads as the answer, alike.
  for (final MapEntry(key: lang, value: cell) in a.meanings.entries) {
    if (_sameBangla(cell, b.meanings[lang])) return true;
  }
  bool names(QuizWord w, QuizWord other) =>
      _hasWords(w.synonyms ?? '', other.german);
  return names(a, b) || names(b, a);
}

/// Whether two Bangla meanings would read as one (#339): an alternative
/// they share (#387: "না" beside "না / নয়"), the same once a qualifier in
/// brackets is dropped from one that has it and the other has none —
/// "সাজানো" beside "সাজানো (ঘর)". Two qualified ones stay apart:
/// "তোমাকে (accusative)" and "তোমাকে (dative)" are the test.
bool _sameBangla(String? a, String? b) {
  // Only "/": a comma can sit inside a qualifier's brackets.
  Iterable<String> alternatives(String? s) =>
      (s ?? '').split('/').map((p) => p.trim()).where((p) => p.isNotEmpty);
  for (final x in alternatives(a)) {
    for (final y in alternatives(b)) {
      if (x == y) return true;
      final bareX = x.replaceAll(_qualifier, '').trim();
      final bareY = y.replaceAll(_qualifier, '').trim();
      if (bareX == bareY && (bareX == x || bareY == y)) return true;
    }
  }
  return false;
}

final RegExp _qualifier = RegExp(r'\s*\([^)]*\)');

/// Whether [phrase]'s words appear in [text] as whole words, in order: "an"
/// is not named by "das Anliegen".
bool _hasWords(String text, String phrase) {
  List<String> words(String s) =>
      s.toLowerCase().split(_nonWord).where((w) => w.isNotEmpty).toList();
  final haystack = words(text);
  final needle = words(phrase);
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var all = true;
    for (var j = 0; j < needle.length && all; j++) {
      all = haystack[i + j] == needle[j];
    }
    if (all) return true;
  }
  return false;
}

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}-]+', unicode: true);
