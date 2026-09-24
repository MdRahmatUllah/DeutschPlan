/// `docs/03-domain/exam-generator.md`: a step's three mock exams, from one
/// seeded algorithm (BR-EXAM-02), in BR-EXAM-03's nine sections.
///
/// Plain Dart: no Flutter, no drift. The data layer hands it an [ExamPool];
/// L11 (#129) builds the paper and pre-inserts it, and the runner (#130)
/// reads each row back with [ExamItem.decode].
library;

import 'dart:convert';
import 'dart:math';

import 'package:deutschplan/domain/cloze.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart';

/// BR-EXAM-03's sections, in paper order, with their items and the points
/// each is worth. The wire name is `exam_answers.section`.
enum ExamSection {
  vocabulary(10),
  reverse(8),
  articles(6),
  wordForms(4),
  gapFill(6),
  grammar(4),
  listening(2),
  writing(1, points: 4),
  speaking(1, points: 4);

  const ExamSection(this.count, {this.points = 1});

  /// Items in a paper with listening on.
  final int count;
  final int points;

  static ExamSection parse(String wire) => values.firstWhere(
    (section) => section.name == wire,
    orElse: () => throw ArgumentError.value(wire, 'section'),
  );
}

/// How many items of [section] a paper has. FR-L10-04: with listening off
/// its two points go to Vocabulary and Reverse, one each, so a paper is
/// still 40 questions and 48 points.
int sectionCount(ExamSection section, {required bool listening}) {
  if (listening) return section.count;
  return switch (section) {
    ExamSection.listening => 0,
    ExamSection.vocabulary || ExamSection.reverse => section.count + 1,
    _ => section.count,
  };
}

/// FR-L12W-02: the fewest words a text must have at [level].
int writingMinWords(String level) => switch (level) {
  'A1' => 30,
  'A2' => 60,
  'B1' => 100,
  'B2' => 150,
  'C1' => 200,
  _ => 250,
};

/// FR-L12S-02: the longest a recording may run at [level], in seconds.
int speakingSeconds(String level) => switch (level) {
  'A1' || 'A2' => 60,
  'B1' || 'B2' => 90,
  _ => 120,
};

/// A word as the exam sees it: the quiz builder's word, its category and
/// its example sentences.
class ExamWord {
  const ExamWord({
    required this.word,
    this.category,
    this.examples = const <({String german, String english})>[],
  });

  final QuizWord word;
  final int? category;
  final List<({String german, String english})> examples;
}

/// Everything a step's mocks are built from (`exam-generator.md`, step 1).
class ExamPool {
  const ExamPool({
    required this.step,
    required this.level,
    required this.words,
    required this.topics,
    this.categories = const <int, String>{},
    this.connectors = const <String>[],
  });

  /// `A1.1`, and its level `A1`.
  final String step;
  final String level;

  /// The step's words, any status but suspended, in course order.
  final List<ExamWord> words;

  /// The step's grammar topics, in course order.
  final List<GrammarSource> topics;

  /// Category names by id.
  final Map<int, String> categories;

  /// The course's conjunctions up to this step: what the writing check
  /// counts as connectors.
  final List<String> connectors;
}

/// One mock: its items in paper order (`exam_answers.ord` is the position
/// plus one).
class Exam {
  const Exam({
    required this.step,
    required this.seed,
    required this.items,
    required this.reused,
  });

  final String step;
  final int seed;
  final List<ExamItem> items;

  /// The step had too few items for three papers without repeats, so this
  /// one reuses the least recently used of another's — the hub says so.
  final bool reused;

  /// 48 for a full paper, listening or not (FR-L10-04). A step too small to
  /// fill every section gives fewer.
  int get maxPoints => items.fold(0, (sum, item) => sum + item.section.points);
}

/// One exam row as `exam_answers` stores it.
typedef ExamRow = ({
  String section,
  String? ref,
  String prompt,
  String? options,
  String? expected,
});

/// One item of a paper.
///
/// [ref] is what never repeats across a step's three mocks: a word's uid in
/// every word section, `<topic uid>#<n>` for a grammar item, and
/// `writing:<category id>` / `speaking:<category id>` for the two tasks.
sealed class ExamItem {
  const ExamItem(this.section, this.ref);

  final ExamSection section;
  final String ref;

  /// What `answer_check` compares against; null for Writing and Speaking,
  /// which are graded by their checks and rubric.
  String? get expected;

  /// The choices, for a question answered by tapping one.
  List<String>? get options => null;

  Map<String, Object?> get _prompt;

  /// The row L11 pre-inserts. The prompt is JSON, so every kind of item
  /// comes back whole after a restart (FR-L12-01).
  ExamRow encode() => (
    section: section.name,
    ref: ref,
    prompt: jsonEncode(_prompt),
    options: options == null ? null : jsonEncode(options),
    expected: expected,
  );

  /// The item a row holds, as [encode] wrote it.
  static ExamItem decode(ExamRow row) {
    final section = ExamSection.parse(row.section);
    final ref = row.ref ?? '';
    final json = jsonDecode(row.prompt) as Map<String, Object?>;
    return switch (section) {
      ExamSection.gapFill => GapQuestion(
        ref,
        before: json['before']! as String,
        after: json['after']! as String,
        answer: row.expected!,
        translation: json['translation']! as String,
      ),
      ExamSection.grammar => GrammarQuestion(ref, _grammarItem(json)),
      ExamSection.writing => WritingTask(
        ref,
        level: json['level']! as String,
        category: json['category'] as String?,
        targets: (json['targets']! as List<Object?>).cast<String>(),
        minWords: json['minWords']! as int,
        connectors: (json['connectors']! as List<Object?>).cast<String>(),
      ),
      ExamSection.speaking => SpeakingTask(
        ref,
        level: json['level']! as String,
        category: json['category'] as String?,
        seconds: json['seconds']! as int,
      ),
      _ => WordQuestion(
        section,
        ref,
        prompt: json['prompt']! as String,
        expected: row.expected!,
        form: switch (json['form']) {
          final String form => FormLabel.values.byName(form),
          _ => null,
        },
      ),
    };
  }
}

/// Vocabulary (the headword; its meaning typed), Reverse (the meaning; the
/// headword typed, article optional), Articles (the noun; der/die/das
/// tapped), Word forms (the word and [form]; the form typed) and Listening
/// (the headword played; typed).
final class WordQuestion extends ExamItem {
  const WordQuestion(
    super.section,
    super.ref, {
    required this.prompt,
    required this.expected,
    this.form,
  });

  final String prompt;
  @override
  final String expected;
  final FormLabel? form;

  @override
  List<String>? get options => section == ExamSection.articles
      ? const <String>['der', 'die', 'das']
      : null;

  @override
  Map<String, Object?> get _prompt => <String, Object?>{
    'prompt': prompt,
    if (form != null) 'form': form!.name,
  };
}

/// Gap fill: one of the word's example sentences with the word blanked, as
/// the cloze card blanks it — [answer] is the form the sentence uses.
final class GapQuestion extends ExamItem {
  const GapQuestion(
    String ref, {
    required this.before,
    required this.after,
    required this.answer,
    required this.translation,
  }) : super(ExamSection.gapFill, ref);

  final String before;
  final String after;
  final String answer;
  final String translation;

  @override
  String get expected => answer;

  @override
  Map<String, Object?> get _prompt => <String, Object?>{
    'before': before,
    'after': after,
    'translation': translation,
  };
}

/// A grammar item, from the generator L15 practises with.
///
/// [expected] is what the learner produces: the missing word (gap fill), the
/// right form (pick the form), the index of the wrong token (spot the
/// error), the words in order joined by a space, or the index of the right
/// rule (rule recall).
final class GrammarQuestion extends ExamItem {
  const GrammarQuestion(String ref, this.item)
    : super(ExamSection.grammar, ref);

  final GrammarItem item;

  @override
  String get expected => switch (item) {
    GapFill(:final answer) || PickTheForm(:final answer) => answer,
    SpotTheError(:final wrong) => '$wrong',
    OrderTheSentence(:final answer) => answer.join(' '),
    RuleRecall(:final answer) => '$answer',
  };

  @override
  List<String>? get options => switch (item) {
    PickTheForm(:final options) || RuleRecall(:final options) => options,
    _ => null,
  };

  @override
  Map<String, Object?> get _prompt => switch (item) {
    GapFill(:final before, :final after, :final answer, :final translation) =>
      <String, Object?>{
        'kind': 'gapFill',
        'before': before,
        'after': after,
        'answer': answer,
        'translation': translation,
      },
    PickTheForm(
      :final before,
      :final after,
      :final options,
      :final answer,
      :final translation,
    ) =>
      <String, Object?>{
        'kind': 'pickTheForm',
        'before': before,
        'after': after,
        'options': options,
        'answer': answer,
        'translation': translation,
      },
    SpotTheError(:final tokens, :final wrong, :final correction) =>
      <String, Object?>{
        'kind': 'spotTheError',
        'tokens': tokens,
        'wrong': wrong,
        'correction': correction,
      },
    OrderTheSentence(:final chips, :final answer) => <String, Object?>{
      'kind': 'orderTheSentence',
      'chips': chips,
      'answer': answer,
    },
    RuleRecall(:final question, :final options, :final answer) =>
      <String, Object?>{
        'kind': 'ruleRecall',
        'question': question,
        'options': options,
        'answer': answer,
      },
  };
}

GrammarItem _grammarItem(Map<String, Object?> json) {
  List<String> strings(String key) => (json[key]! as List<Object?>).cast();
  String text(String key) => json[key]! as String;
  return switch (json['kind']) {
    'gapFill' => GapFill(
      before: text('before'),
      after: text('after'),
      answer: text('answer'),
      translation: text('translation'),
    ),
    'pickTheForm' => PickTheForm(
      before: text('before'),
      after: text('after'),
      options: strings('options'),
      answer: text('answer'),
      translation: text('translation'),
    ),
    'spotTheError' => SpotTheError(
      tokens: strings('tokens'),
      wrong: json['wrong']! as int,
      correction: text('correction'),
    ),
    'orderTheSentence' => OrderTheSentence(
      chips: strings('chips'),
      answer: strings('answer'),
    ),
    'ruleRecall' => RuleRecall(
      question: text('question'),
      options: strings('options'),
      answer: json['answer']! as int,
    ),
    final kind => throw ArgumentError.value(kind, 'kind'),
  };
}

/// Writing: a text about [category] at [level], using at least 6 of the 10
/// [targets] and at least [minWords] words (FR-L12W-01…03). The screen words
/// the task from ARB per level; this is what it fills in.
final class WritingTask extends ExamItem {
  const WritingTask(
    String ref, {
    required this.level,
    required this.category,
    required this.targets,
    required this.minWords,
    required this.connectors,
  }) : super(ExamSection.writing, ref);

  final String level;

  /// The category's German name; null when the step has none.
  final String? category;
  final List<String> targets;
  final int minWords;
  final List<String> connectors;

  @override
  String? get expected => null;

  @override
  Map<String, Object?> get _prompt => <String, Object?>{
    'level': level,
    'category': category,
    'targets': targets,
    'minWords': minWords,
    'connectors': connectors,
  };
}

/// Speaking: talk about [category] for up to [seconds] (FR-L12S-02).
final class SpeakingTask extends ExamItem {
  const SpeakingTask(
    String ref, {
    required this.level,
    required this.category,
    required this.seconds,
  }) : super(ExamSection.speaking, ref);

  final String level;
  final String? category;
  final int seconds;

  @override
  String? get expected => null;

  @override
  Map<String, Object?> get _prompt => <String, Object?>{
    'level': level,
    'category': category,
    'seconds': seconds,
  };
}

/// The order the sections draw from the pool: the scarcest first, so a
/// small step spends its few nouns and forms where only they will do; and
/// Writing and Speaking last, so the targets can leave out every word the
/// paper asks.
const List<ExamSection> _drawOrder = <ExamSection>[
  ExamSection.wordForms,
  ExamSection.gapFill,
  ExamSection.articles,
  ExamSection.grammar,
  ExamSection.listening,
  ExamSection.reverse,
  ExamSection.vocabulary,
  ExamSection.writing,
  ExamSection.speaking,
];

/// What never repeats for [ref]: a grammar item's topic (a topic's items
/// share their sentence), anything else itself.
String _key(String ref) => ref.split('#').first;

/// Mock [seed] (1–3) of [pool]'s step.
///
/// The three papers are drawn together, section by section, each from its
/// own `Random(hash(step, seed))`: an item one paper takes is out of the
/// others' pools, so the mocks never share one (BR-EXAM-02). Only when a
/// section runs out does a paper reuse an item, the one another paper took
/// longest ago, and [Exam.reused] says so. The same pool always gives the
/// same papers.
///
/// [sat] holds the refs of the papers already stored, by seed. Those seeds
/// are not drawn again: their refs count as drawn before anything else, so
/// a paper built after the pool has changed — a word suspended, a setting
/// moved, a content update — still shares nothing with them. A retake is
/// the stored paper, not a new one.
///
/// [bangla] asks Vocabulary for the Bangla meaning and words Reverse's
/// prompt in Bangla, where the course has one — the learner's meaning
/// language. [listening] false is FR-L10-04.
Exam buildExam(
  ExamPool pool, {
  required int seed,
  bool listening = true,
  bool bangla = false,
  Map<int, Set<String>> sat = const <int, Set<String>>{},
}) {
  if (seed < 1 || seed > 3) throw RangeError.range(seed, 1, 3, 'seed');
  final seeds = <int>[
    for (var s = 1; s <= 3; s++)
      if (s == seed || !sat.containsKey(s)) s,
  ];
  final randoms = <int, Random>{
    for (final s in seeds) s: Random(practiceSeed(pool.step, 'mock $s')),
  };
  final papers = <int, Map<ExamSection, List<ExamItem>>>{
    for (final s in seeds) s: <ExamSection, List<ExamItem>>{},
  };
  final taken = <int, Set<String>>{for (final s in seeds) s: <String>{}};
  // When each key was last drawn, for the least-recently-used reuse; the
  // stored papers' first.
  final drawn = <String, int>{};
  var clock = 0;
  for (final MapEntry(key: s, value: refs) in sat.entries) {
    if (s == seed) continue;
    for (final ref in refs) {
      drawn[_key(ref)] = clock++;
    }
  }
  final reused = <int>{};

  /// [n] of [candidates] for paper [s]: fresh ones first, in the paper's
  /// seeded order ([ordered]: as given); then another paper's, the longest
  /// ago first. Never one the paper already has.
  List<T> draw<T>(
    int s,
    List<T> candidates,
    int n,
    String Function(T) key, {
    bool ordered = false,
  }) {
    final fresh = <T>[
      for (final c in candidates)
        if (!drawn.containsKey(key(c))) c,
    ];
    if (!ordered) fresh.shuffle(randoms[s]);
    final old = <T>[
      for (final c in candidates)
        if (drawn.containsKey(key(c)) && !taken[s]!.contains(key(c))) c,
    ]..sort((a, b) => drawn[key(a)]!.compareTo(drawn[key(b)]!));
    final picked = <T>[...fresh, ...old].take(n).toList();
    for (final c in picked) {
      if (drawn.containsKey(key(c))) reused.add(s);
      drawn[key(c)] = clock++;
      taken[s]!.add(key(c));
    }
    return picked;
  }

  final words = pool.words;
  final byCategory = <int, List<ExamWord>>{};
  for (final w in words) {
    if (w.category != null) (byCategory[w.category!] ??= <ExamWord>[]).add(w);
  }
  // The categories a task can be about, the biggest first: a big one gives
  // the learner the most to write about, so papers 1–3 take the first three.
  final categories = <int?>[
    ...byCategory.keys.toList()..sort((a, b) {
      final bySize = byCategory[b]!.length.compareTo(byCategory[a]!.length);
      return bySize != 0 ? bySize : a.compareTo(b);
    }),
  ];
  if (categories.isEmpty) categories.add(null);
  final writingAbout = <int, int?>{};
  // Each topic's items; a paper that draws a topic asks one of them.
  final topics = <(String, List<GrammarItem>)>[
    for (final topic in pool.topics)
      if (generateItems(
            topic,
            seed: practiceSeed(topic.uid, pool.step),
            siblings: <String>[
              for (final other in pool.topics)
                if (other.uid != topic.uid) other.rule,
            ],
          )
          case final items when items.isNotEmpty)
        (topic.uid, items),
  ];

  for (final section in _drawOrder) {
    for (final s in seeds) {
      final n = sectionCount(section, listening: listening);
      if (n == 0) continue;
      papers[s]![section] = switch (section) {
        ExamSection.grammar => <ExamItem>[
          for (final (uid, items) in draw(s, topics, n, (t) => t.$1))
            if (randoms[s]!.nextInt(items.length) case final i)
              GrammarQuestion('$uid#$i', items[i]),
        ],
        ExamSection.writing => <ExamItem>[
          for (final id in draw(
            s,
            categories,
            n,
            (id) => 'writing:${id ?? '-'}',
            ordered: true,
          ))
            _writing(
              pool,
              writingAbout[s] = id,
              byCategory[id] ?? words,
              taken[s]!,
              randoms[s]!,
            ),
        ],
        // About something other than the paper's writing, where there is.
        ExamSection.speaking => <ExamItem>[
          for (final id in draw(
            s,
            switch (<int?>[
              for (final c in categories)
                if (c != writingAbout[s]) c,
            ]) {
              final others when others.isNotEmpty => others,
              _ => categories,
            },
            n,
            (id) => 'speaking:${id ?? '-'}',
            ordered: true,
          ))
            SpeakingTask(
              'speaking:${id ?? '-'}',
              level: pool.level,
              category: id == null ? null : pool.categories[id],
              seconds: speakingSeconds(pool.level),
            ),
        ],
        ExamSection.gapFill => <ExamItem>[
          for (final (_, gap) in draw(
            s,
            <(ExamWord, GapQuestion)>[
              for (final w in words)
                if (_gap(w, randoms[s]!) case final gap?) (w, gap),
            ],
            n,
            (c) => c.$1.word.uid,
          ))
            gap,
        ],
        _ => <ExamItem>[
          for (final w in draw(
            s,
            <ExamWord>[
              for (final w in words)
                if (_fits(section, w.word)) w,
            ],
            n,
            (w) => w.word.uid,
          ))
            _wordQuestion(section, w.word, bangla, randoms[s]!),
        ],
      };
    }
  }

  final items = <ExamItem>[
    for (final section in ExamSection.values) ...?papers[seed]![section],
  ];
  return Exam(
    step: pool.step,
    seed: seed,
    items: items,
    reused: reused.contains(seed),
  );
}

/// Whether [word] can be asked in a word [section].
bool _fits(ExamSection section, QuizWord word) => switch (section) {
  ExamSection.articles => applies(QuizDirection.articles, word),
  ExamSection.wordForms => applies(QuizDirection.forms, word),
  _ => true,
};

WordQuestion _wordQuestion(
  ExamSection section,
  QuizWord word,
  bool bangla,
  Random random,
) {
  final meaning = bangla && (word.bangla ?? '').trim().isNotEmpty
      ? word.bangla!
      : word.english;
  switch (section) {
    case ExamSection.vocabulary:
      return WordQuestion(
        section,
        word.uid,
        prompt: word.headword,
        expected: meaning,
      );
    case ExamSection.reverse:
      return WordQuestion(
        section,
        word.uid,
        prompt: meaning,
        expected: word.headword,
      );
    case ExamSection.articles:
      return WordQuestion(
        section,
        word.uid,
        prompt: word.german,
        expected: word.article!,
      );
    case ExamSection.wordForms:
      final forms = parseForms(word);
      final (label, form) = forms[random.nextInt(forms.length)];
      return WordQuestion(
        section,
        word.uid,
        prompt: word.german,
        expected: form,
        form: label,
      );
    default:
      return WordQuestion(
        section,
        word.uid,
        prompt: word.headword,
        expected: word.headword,
      );
  }
}

/// A gap fill from one of [word]'s examples, the seed's pick among those
/// the cloze rules can blank; null when none can be.
GapQuestion? _gap(ExamWord word, Random random) {
  final gaps = <GapQuestion>[
    for (final example in word.examples)
      if (clozeGap(example.german, word.word.german, pos: word.word.pos)
          case final gap?)
        GapQuestion(
          word.word.uid,
          before: example.german.substring(0, gap.start),
          after: example.german.substring(gap.end),
          answer: example.german.substring(gap.start, gap.end),
          translation: example.english,
        ),
  ];
  return gaps.isEmpty ? null : gaps[random.nextInt(gaps.length)];
}

/// The Writing task about category [id]: ten targets from [words], single
/// words so FR-L12W-01's token match can find them, and none the paper
/// already [asked] (by uid) — the runner goes back and forth, and a target
/// must not be an answer to copy. Nor its spelling under another uid: the
/// course has homographs.
WritingTask _writing(
  ExamPool pool,
  int? id,
  List<ExamWord> words,
  Set<String> asked,
  Random random,
) {
  final spelled = <String>{
    for (final w in pool.words)
      if (asked.contains(w.word.uid)) w.word.german,
  };
  bool fits(ExamWord w) =>
      !w.word.german.trim().contains(' ') && !spelled.contains(w.word.german);
  final own = <String>[
    for (final w in words)
      if (fits(w)) w.word.german,
  ]..shuffle(random);
  // Topped up from the rest of the step when the category is small.
  final rest = <String>[
    for (final w in pool.words)
      if (fits(w) && !own.contains(w.word.german)) w.word.german,
  ]..shuffle(random);
  return WritingTask(
    'writing:${id ?? '-'}',
    level: pool.level,
    category: id == null ? null : pool.categories[id],
    targets: <String>{...own, ...rest}.take(10).toList(),
    minWords: writingMinWords(pool.level),
    connectors: pool.connectors,
  );
}
