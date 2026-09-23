import 'dart:math';

/// S3 · the placement check, as pure Dart. `docs/04-screens/placement.md`.
///
/// FR-S3-01: start at A1.1; two right in a row move up a step, two wrong in
/// a row move down; 20 items at most; stop after 8 if the step has held for
/// the last 3. FR-S3-02: items drawn with a fixed seed per session, and the
/// wrong options share the right one's part of speech. FR-S3-03 is the
/// caller's to keep — nothing here can write anything.

/// A word a placement item can be made from.
class PlacementWord {
  const PlacementWord({
    required this.uid,
    required this.german,
    required this.english,
    required this.pos,
    this.article,
    this.examples = const <String>[],
  });

  final String uid;
  final String? article;
  final String german;
  final String english;

  /// `words.pos`, as the pipeline writes it — `noun`, `verb`, `adj`…
  final String pos;

  /// German example sentences, for a gap item.
  final List<String> examples;
}

/// The three kinds `placement.md` names.
enum PlacementKind { meaning, article, gap }

class PlacementItem {
  const PlacementItem({
    required this.step,
    required this.kind,
    required this.word,
    required this.options,
    required this.answer,
    this.sentence,
  });

  /// The step it was drawn from, which is the step being tested.
  final String step;
  final PlacementKind kind;
  final PlacementWord word;

  /// Four for a meaning or a gap, three for an article.
  final List<String> options;

  /// The index into [options] that is right.
  final int answer;

  /// A gap item's sentence, with the word replaced by `___`.
  final String? sentence;

  /// "A1", from "A1.1" — what the level tag and the breakdown group by.
  String get level => step.split('.').first;
}

/// One area of the result: "A1 words 9 / 10", "Articles 5 / 5".
typedef PlacementArea = ({String area, int correct, int total});

class PlacementResult {
  const PlacementResult({
    required this.step,
    required this.correct,
    required this.answered,
    required this.areas,
  });

  /// The step to suggest: where the walk ended.
  final String step;
  final int correct;
  final int answered;

  /// Word items grouped by level in course order, then articles.
  final List<PlacementArea> areas;
}

class PlacementSession {
  PlacementSession({required List<String> steps, required this.seed})
    : assert(steps.isNotEmpty, 'a check needs somewhere to start'),
      _steps = List<String>.unmodifiable(steps),
      _random = Random(seed);

  /// FR-S3-01's limits.
  static const int maxItems = 20;
  static const int earliestStop = 8;
  static const int stableFor = 3;
  static const int toMove = 2;

  /// The label `areas` uses for article items — the caller names it.
  static const String articles = 'articles';

  /// BR-COURSE-01's twelve steps, in course order.
  final List<String> _steps;

  /// FR-S3-02: the same seed draws the same items in the same order.
  final int seed;
  final Random _random;

  int _index = 0;
  int _rightInARow = 0;
  int _wrongInARow = 0;
  final List<(PlacementItem, bool)> _answered = <(PlacementItem, bool)>[];
  final Set<String> _used = <String>{};

  /// The step the next item comes from. Starts at A1.1 — the first step.
  String get step => _steps[_index];

  int get answered => _answered.length;

  /// FR-S3-01's stop: 20 items, or 8 with the step unmoved for the last 3.
  bool get finished {
    if (_answered.length >= maxItems) return true;
    if (_answered.length < earliestStop) return false;
    final last = _answered.sublist(_answered.length - stableFor);
    return last.every((entry) => entry.$1.step == step);
  }

  /// The next item, from [pool] — the words of [step]. Null when the pool
  /// cannot make one: fewer than four words, or all of them used.
  PlacementItem? next(List<PlacementWord> pool) {
    // Words spelt alike but for case — ihr and Ihr, sie and Sie, morgen and
    // Morgen. Shown alone at the top of a meaning item, "Ihr" is also "ihr",
    // and a learner who answers "you all" is not wrong. They are asked with a
    // sentence round them, or as their article, or not at all.
    final spellings = <String, int>{};
    for (final w in pool) {
      spellings.update(w.german.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }
    bool ambiguous(PlacementWord w) => spellings[w.german.toLowerCase()]! > 1;

    final fresh = pool.where((w) => !_used.contains(w.uid)).toList();
    if (fresh.isEmpty) return null;

    // Kinds in turn, so a check is not twenty meaning questions — falling
    // back to meaning when the word cannot be the other kind.
    final wanted = PlacementKind.values[_answered.length % 3];
    final candidates = fresh
        .where((w) => _canBe(w, wanted, ambiguous: ambiguous(w)))
        .toList();
    final meanings = fresh.where((w) => !ambiguous(w)).toList();
    final kind = candidates.isEmpty ? PlacementKind.meaning : wanted;
    final from = candidates.isEmpty ? meanings : candidates;
    if (from.isEmpty) return null;

    final word = from[_random.nextInt(from.length)];
    final item = _build(word, kind, pool);
    if (item == null) return null;
    _used.add(word.uid);
    return item;
  }

  /// FR-S3-01's walk.
  void answer(PlacementItem item, {required bool correct}) {
    _answered.add((item, correct));
    if (correct) {
      _wrongInARow = 0;
      if (++_rightInARow == toMove) {
        _rightInARow = 0;
        if (_index < _steps.length - 1) _index++;
      }
    } else {
      _rightInARow = 0;
      if (++_wrongInARow == toMove) {
        _wrongInARow = 0;
        if (_index > 0) _index--;
      }
    }
  }

  PlacementResult result() {
    final byArea = <String, (int, int)>{};
    for (final (item, correct) in _answered) {
      final area = item.kind == PlacementKind.article ? articles : item.level;
      final (right, total) = byArea[area] ?? (0, 0);
      byArea[area] = (right + (correct ? 1 : 0), total + 1);
    }

    // Levels in course order, articles last — the order the artboard reads.
    final levels = <String>{for (final code in _steps) code.split('.').first}
        .toList();
    final order = <String>[...levels, articles];

    return PlacementResult(
      step: step,
      correct: _answered.where((entry) => entry.$2).length,
      answered: _answered.length,
      areas: <PlacementArea>[
        for (final area in order)
          if (byArea[area] case (final right, final total))
            (area: area, correct: right, total: total),
      ],
    );
  }

  static bool _canBe(
    PlacementWord word,
    PlacementKind kind, {
    required bool ambiguous,
  }) => switch (kind) {
    PlacementKind.meaning => !ambiguous,
    PlacementKind.article => _genders.contains(word.article),
    PlacementKind.gap => _gapIn(word) != null,
  };

  PlacementItem? _build(
    PlacementWord word,
    PlacementKind kind,
    List<PlacementWord> pool,
  ) {
    if (kind == PlacementKind.article) {
      final options = List<String>.of(_genders);
      return PlacementItem(
        step: step,
        kind: kind,
        word: word,
        options: options,
        answer: options.indexOf(word.article!),
      );
    }

    // FR-S3-02: the wrong options share the right one's part of speech, so
    // a noun is never told apart from three verbs by its shape alone. Other
    // parts of speech only when the step has too few of this one.
    String shown(PlacementWord w) =>
        kind == PlacementKind.gap ? w.german : w.english;
    final target = shown(word);
    // Not the answer again under another uid, and — in a gap — not the
    // answer spelt with another case, which would look the same on screen.
    bool distinct(String text) => text.toLowerCase() != target.toLowerCase();
    final same = pool
        .where((w) => w.uid != word.uid && w.pos == word.pos)
        .map(shown)
        .where(distinct)
        .toSet()
        .toList();
    final other = pool
        .where((w) => w.uid != word.uid && w.pos != word.pos)
        .map(shown)
        .where((text) => distinct(text) && !same.contains(text))
        .toSet()
        .toList();
    same.shuffle(_random);
    other.shuffle(_random);
    final distractors = <String>[...same, ...other].take(3).toList();
    if (distractors.length < 3) return null;

    final options = <String>[...distractors, target]..shuffle(_random);
    return PlacementItem(
      step: step,
      kind: kind,
      word: word,
      options: options,
      answer: options.indexOf(target),
      sentence: kind == PlacementKind.gap ? _gapIn(word) : null,
    );
  }

  /// The first example that holds the headword as it is written — a verb
  /// conjugated in the sentence cannot be blanked without giving it away.
  static String? _gapIn(PlacementWord word) {
    final pattern = RegExp(
      r'(?<![\p{L}])' + RegExp.escape(word.german) + r'(?![\p{L}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final sentence in word.examples) {
      if (pattern.hasMatch(sentence)) {
        return sentence.replaceFirst(pattern, '___');
      }
    }
    return null;
  }

  static const List<String> _genders = <String>['der', 'die', 'das'];
}
