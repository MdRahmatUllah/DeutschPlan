import 'dart:math';

import 'package:deutschplan/domain/answer_check.dart' show splitMeanings;
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_engine.dart' show PlanDate, daysBetween;

/// What a quiz asks (`quiz-engine.md`). The wire names are what `QuizArgs`
/// and `quiz_attempts.direction` carry.
enum QuizDirection {
  deEn,
  deBn,
  enDe,
  articles,
  listening,
  forms,

  /// A round-robin of the others, per word, skipping those that don't apply.
  mixed;

  static QuizDirection parse(String wire) => QuizDirection.values.firstWhere(
    (direction) => direction.name == wire,
    orElse: () => throw ArgumentError.value(wire, 'direction'),
  );
}

/// Where a quiz's words come from (BR-QUIZ-01).
enum QuizSource {
  /// The step in `ref`'s learned words: the default.
  stepLearned,
  allLearned,

  /// The category whose id is `ref`.
  category,

  /// The words whose uids `ref` lists, comma-separated: W2's *Quiz these*.
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

  /// "der Mietvertrag", or "arbeiten".
  String get headword => article == null ? german : '$article $german';
}

/// What the builder needs from the database. Pure Dart, like the plan
/// engine's `PlanStore`, so every choice it makes is testable without one.
abstract interface class QuizStore {
  /// The learned words (learning or done, so never suspended) of [source].
  Future<List<QuizWord>> learned(QuizSource source, {String? ref});

  /// Every word of [step], whatever its status: the distractor pool.
  Future<List<QuizWord>> stepWords(String step);
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
  });

  /// 1-based, as `quiz_answers.ord`.
  final int ord;
  final String wordUid;

  /// Never [QuizDirection.mixed]: a mixed quiz's items each have their own.
  final QuizDirection direction;

  /// What is shown: the headword (deEn, deBn, listening — where the runner
  /// plays it), the meaning (enDe), the noun without its article (articles),
  /// or the infinitive / singular / base form (forms, with [form]).
  final String prompt;

  /// What `answer_check` compares against: a meaning list for deEn/deBn, a
  /// headword for enDe and listening, `der|die|das`, or the form.
  final String expected;

  /// Four tiles for the multiple-choice layout — [expected] and three
  /// distractors in a seeded order — on the meaning directions (deEn, deBn,
  /// enDe). Empty for the others, whose answers are typed or fixed.
  final List<String> options;

  /// Which form a forms item asks for.
  final FormLabel? form;
}

class Quiz {
  const Quiz({
    required this.direction,
    required this.source,
    required this.seed,
    required this.items,
    this.sourceRef,
  });

  final QuizDirection direction;
  final QuizSource source;
  final String? sourceRef;
  final int seed;
  final List<QuizItem> items;
}

/// Builds a quiz (`docs/03-domain/quiz-engine.md`, #81).
class QuizBuilder {
  QuizBuilder(this._store, {Fsrs? fsrs}) : _fsrs = fsrs ?? Fsrs();

  final QuizStore _store;
  final Fsrs _fsrs;

  /// [length] questions at most — fewer when fewer words qualify. The same
  /// [seed] over the same progress builds the same quiz, which is what lets
  /// `quiz_attempts.seed` rebuild it.
  Future<Quiz> build({
    required QuizDirection direction,
    required QuizSource source,
    required int length,
    required int seed,
    required PlanDate today,
    String? sourceRef,
  }) async {
    final random = Random(seed);
    final learned = await _store.learned(source, ref: sourceRef);
    final eligible = direction == QuizDirection.mixed
        ? learned
        : learned.where((word) => applies(direction, word)).toList();
    final picked = pickWords(
      eligible,
      length: length,
      today: today,
      fsrs: _fsrs,
      random: random,
    );

    final pools = <String, List<QuizWord>>{};
    Future<List<QuizWord>> poolFor(String step) async =>
        pools[step] ??= await _store.stepWords(step);

    final items = <QuizItem>[];
    for (final (i, word) in picked.indexed) {
      final asked = direction == QuizDirection.mixed
          ? mixedDirection(i, word)
          : direction;
      items.add(
        await _item(
          i + 1,
          word,
          asked,
          random,
          () async => <QuizWord>[...await poolFor(word.step), ...learned],
        ),
      );
    }
    return Quiz(
      direction: direction,
      source: source,
      sourceRef: sourceRef,
      seed: seed,
      items: items,
    );
  }

  Future<QuizItem> _item(
    int ord,
    QuizWord word,
    QuizDirection direction,
    Random random,
    Future<List<QuizWord>> Function() pool,
  ) async {
    Future<List<String>> tiles(String Function(QuizWord) value) async {
      final wrong = distractors(word, await pool(), value, random);
      return <String>[value(word), ...wrong]..shuffle(random);
    }

    switch (direction) {
      case QuizDirection.deEn:
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.headword,
          expected: word.english,
          options: await tiles((w) => w.english),
        );
      case QuizDirection.deBn:
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.headword,
          expected: word.bangla!,
          options: await tiles((w) => w.bangla ?? ''),
        );
      case QuizDirection.enDe:
        return QuizItem(
          ord: ord,
          wordUid: word.uid,
          direction: direction,
          prompt: word.english,
          expected: word.headword,
          options: await tiles((w) => w.headword),
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
    }
  }
}

/// The directions a mixed quiz rotates through, in order.
const List<QuizDirection> rotation = <QuizDirection>[
  QuizDirection.deEn,
  QuizDirection.deBn,
  QuizDirection.enDe,
  QuizDirection.articles,
  QuizDirection.listening,
  QuizDirection.forms,
];

/// Item [index] of a mixed quiz: the rotation's next direction that applies
/// to [word]. DE → EN always does, so there is always one.
QuizDirection mixedDirection(int index, QuizWord word) {
  for (var k = 0; k < rotation.length; k++) {
    final direction = rotation[(index + k) % rotation.length];
    if (applies(direction, word)) return direction;
  }
  return QuizDirection.deEn;
}

/// Whether [word] can be asked in [direction] (`quiz-engine.md`: articles
/// needs an article, forms a parsable `forms` cell).
bool applies(QuizDirection direction, QuizWord word) => switch (direction) {
  QuizDirection.deEn || QuizDirection.enDe || QuizDirection.listening => true,
  QuizDirection.mixed => true,
  QuizDirection.deBn => (word.bangla ?? '').trim().isNotEmpty,
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
  final right = value(answer).trim().toLowerCase();
  final seen = <String>{right};
  final candidates = <QuizWord>[];
  for (final word in pool) {
    final shown = value(word).trim().toLowerCase();
    if (word.uid == answer.uid || shown.isEmpty || !seen.add(shown)) continue;
    if (_synonyms(answer, word)) continue;
    candidates.add(word);
  }
  // Seeded, then stably sorted by closeness: the order among equally close
  // words is the seed's, so the same quiz gets the same tiles.
  candidates.shuffle(random);
  int closeness(QuizWord word) =>
      (word.pos == answer.pos ? 0 : 2) + (word.step == answer.step ? 0 : 1);
  final ranked = <(int, int, QuizWord)>[
    for (final (i, word) in candidates.indexed) (closeness(word), i, word),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return <String>[for (final (_, _, word) in ranked.take(count)) value(word)];
}

/// Whether [a] and [b] would both be right: a meaning they share, or one
/// named in the other's synonyms cell.
bool _synonyms(QuizWord a, QuizWord b) {
  Set<String> meanings(QuizWord w) => <String>{
    for (final m in splitMeanings(w.english))
      m.toLowerCase().replaceFirst(RegExp(r'^to\s+'), ''),
  };
  if (meanings(a).intersection(meanings(b)).isNotEmpty) return true;
  if ((a.bangla ?? '').trim().isNotEmpty &&
      a.bangla!.trim() == b.bangla?.trim()) {
    return true;
  }
  bool names(QuizWord w, QuizWord other) =>
      _hasWords(w.synonyms ?? '', other.german);
  return names(a, b) || names(b, a);
}

/// Whether [phrase]'s words appear in [text] as whole words, in order: "an"
/// is not named by "das Anliegen".
bool _hasWords(String text, String phrase) {
  List<String> words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}-]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
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
