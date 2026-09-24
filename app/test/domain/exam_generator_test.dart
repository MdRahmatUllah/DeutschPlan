import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two letters for word [i]: the cloze rules read letters, not digits.
String tag(int i) => String.fromCharCodes(<int>[97 + i ~/ 26, 97 + i % 26]);

bool noun(int i, bool nouns) => nouns || i % 3 == 0;

/// Word [i] of [count]'s category: half the step in 0, a quarter in 1, the
/// rest spread over 2–6 — so the biggest is plain.
int category(int i, int count) => i < count ~/ 2
    ? 0
    : i < count * 3 ~/ 4
    ? 1
    : 2 + i % 5;

/// The sentence a grammar item is about, however it asks it.
String sentence(GrammarItem item) => switch (item) {
  GapFill(:final before, :final answer, :final after) ||
  PickTheForm(
    :final before,
    :final answer,
    :final after,
  ) => '$before$answer$after',
  SpotTheError(:final tokens, :final wrong, :final correction) => <String>[
    for (final (i, token) in tokens.indexed) i == wrong ? correction : token,
  ].join(' '),
  OrderTheSentence(:final answer) => answer.join(' '),
  RuleRecall(:final question) => question,
};

/// What never repeats for [ref]: a grammar item's topic.
String key(String ref) => ref.split('#').first;

/// `exam_generator.dart` — #83.
void main() {
  /// A step of [count] words: every third a der/die/das noun with a plural
  /// (all of them with [nouns]), the rest verbs with forms; every other with
  /// an example that says it (all of them with [nouns]), categories as
  /// [category] spreads them, Bangla on all but every fifth; and [topics]
  /// grammar topics, each with its own example.
  ExamPool pool({
    int count = 200,
    int topics = 12,
    String step = 'A2.1',
    bool nouns = false,
  }) => ExamPool(
    step: step,
    level: step.split('.').first,
    words: <ExamWord>[
      for (var i = 0; i < count; i++)
        ExamWord(
          word: QuizWord(
            uid: 'w$i',
            german: noun(i, nouns) ? 'Haus${tag(i)}' : 'sag${tag(i)}en',
            english: 'meaning $i',
            step: step,
            article: noun(i, nouns) ? const ['der', 'die', 'das'][i % 3] : null,
            pos: noun(i, nouns) ? 'noun' : 'verb',
            bangla: i % 5 == 0 ? null : 'অর্থ $i',
            forms: noun(i, nouns)
                ? '-er'
                : 'sag${tag(i)}t · hat gesag${tag(i)}t',
          ),
          category: category(i, count),
          examples: i.isEven || nouns
              ? <({String german, String english})>[
                  (
                    german: noun(i, nouns)
                        ? 'Das Haus${tag(i)} ist groß.'
                        : 'Wir sag${tag(i)}en heute.',
                    english: 'Example $i.',
                  ),
                ]
              : const <({String german, String english})>[],
        ),
    ],
    topics: <GrammarSource>[
      for (var t = 0; t < topics; t++)
        GrammarSource(
          uid: 'g$t',
          topic: 'Topic $t',
          rule: 'Rule $t: the verb comes second in a main clause.',
          exampleDe:
              'Wir besuchen heute das Dorf${tag(t)}. '
              'Morgen fahren wir nach Stadt${tag(t)}.',
          exampleEn:
              'Today we visit the village ${tag(t)}. '
              'Tomorrow we go to town ${tag(t)}.',
          watchOut: '—',
          tags: const <String>['gap-fill', 'pick-the-form', 'word-order'],
          levelCode: step.split('.').first,
        ),
    ],
    categories: <int, String>{for (var c = 0; c < 7; c++) c: 'Kategorie $c'},
    connectors: const <String>['und', 'aber', 'weil'],
  );

  Map<ExamSection, int> counts(Exam exam) => <ExamSection, int>{
    for (final section in ExamSection.values)
      section: exam.items.where((i) => i.section == section).length,
  };

  group('BR-EXAM-03 sections and counts', () {
    test('nine sections, in paper order, 42 items worth 48 points', () {
      final exam = buildExam(pool(), seed: 1);

      expect(counts(exam), <ExamSection, int>{
        ExamSection.vocabulary: 10,
        ExamSection.reverse: 8,
        ExamSection.articles: 6,
        ExamSection.wordForms: 4,
        ExamSection.gapFill: 6,
        ExamSection.grammar: 4,
        ExamSection.listening: 2,
        ExamSection.writing: 1,
        ExamSection.speaking: 1,
      });
      final order = exam.items.map((i) => i.section.index).toList();
      expect(order, List<int>.of(order)..sort());
      expect(exam.maxPoints, 48);
    });

    test('FR-L10-04 without listening its points go to Vocabulary and '
        'Reverse', () {
      final exam = buildExam(pool(), seed: 2, listening: false);

      expect(counts(exam)[ExamSection.listening], 0);
      expect(counts(exam)[ExamSection.vocabulary], 11);
      expect(counts(exam)[ExamSection.reverse], 9);
      expect(exam.items, hasLength(42));
      expect(exam.maxPoints, 48);
    });

    test('a seed outside 1–3 is refused', () {
      expect(() => buildExam(pool(), seed: 0), throwsRangeError);
      expect(() => buildExam(pool(), seed: 4), throwsRangeError);
    });
  });

  group('BR-EXAM-02 seeds', () {
    List<ExamRow> rows(Exam exam) => <ExamRow>[
      for (final item in exam.items) item.encode(),
    ];

    test('the same pool and seed give the same paper', () {
      expect(
        rows(buildExam(pool(), seed: 2)),
        rows(buildExam(pool(), seed: 2)),
      );
    });

    test('another step draws other words: the step seeds the paper', () {
      // The words alone: grammar items are seeded by their topic and step
      // anyway, and would differ even if the paper's seed did not.
      List<String> words(Exam exam) => <String>[
        for (final item in exam.items)
          if (item is WordQuestion) item.ref,
      ];

      expect(
        words(buildExam(pool(), seed: 1)),
        isNot(words(buildExam(pool(step: 'A2.2'), seed: 1))),
      );
    });

    test('the three mocks never share an item', () {
      final papers = <Exam>[
        for (var seed = 1; seed <= 3; seed++) buildExam(pool(), seed: seed),
      ];
      final refs = <String>[
        for (final paper in papers) ...paper.items.map((i) => i.ref),
      ];

      expect(refs.toSet(), hasLength(refs.length));
      expect(papers.every((paper) => !paper.reused), isTrue);
    });

    test('a word is asked once in a paper, whatever the section', () {
      final exam = buildExam(pool(), seed: 3);
      final words = <String>[
        for (final item in exam.items)
          if (item is WordQuestion || item is GapQuestion) item.ref,
      ];

      expect(words.toSet(), hasLength(words.length));
    });

    test('too small a step reuses, never within a paper, and says so', () {
      final small = pool(count: 60, topics: 4);
      final papers = <Exam>[
        for (var seed = 1; seed <= 3; seed++) buildExam(small, seed: seed),
      ];
      for (final paper in papers) {
        final refs = paper.items.map((i) => i.ref).toList();
        expect(refs.toSet(), hasLength(refs.length), reason: '${paper.seed}');
        expect(paper.items, hasLength(42), reason: '${paper.seed}');
      }
      expect(papers.any((paper) => paper.reused), isTrue);
    });

    test('what is reused is what was drawn longest ago', () {
      // 40 nouns, each with forms and an example. Forms take 12 and gap
      // fill 18, so Articles finds 10 fresh: paper 1 takes 6 and paper 2
      // takes 4, then reuses the two drawn first — paper 1's first forms.
      final small = pool(count: 40, topics: 2, nouns: true);
      Set<String> refs(Exam exam, ExamSection section) => <String>{
        for (final item in exam.items)
          if (item.section == section) item.ref,
      };
      final one = buildExam(small, seed: 1);
      final two = buildExam(small, seed: 2);
      final three = buildExam(small, seed: 3);

      // What the others drew before Articles: their forms and gap fills.
      final before = <String>{
        for (final paper in <Exam>[one, three])
          for (final section in <ExamSection>[
            ExamSection.wordForms,
            ExamSection.gapFill,
          ])
            ...refs(paper, section),
      };
      final reused = refs(two, ExamSection.articles).intersection(before);
      expect(reused, hasLength(2));
      expect(refs(one, ExamSection.wordForms).containsAll(reused), isTrue);
      expect(two.reused, isTrue);
    });

    test('no grammar sentence is asked in two papers', () {
      final sentences = <String>[
        for (var seed = 1; seed <= 3; seed++)
          for (final item in buildExam(pool(), seed: seed).items)
            if (item is GrammarQuestion) sentence(item.item),
      ];

      expect(sentences, hasLength(12));
      expect(sentences.toSet(), hasLength(12));
    });

    test('ten topics for twelve slots: the last paper reuses the two drawn '
        'longest ago, and says so', () {
      final few = pool(topics: 10);
      final papers = <Exam>[
        for (var seed = 1; seed <= 3; seed++) buildExam(few, seed: seed),
      ];
      Set<String> topics(Exam exam) => <String>{
        for (final item in exam.items)
          if (item is GrammarQuestion) key(item.ref),
      };

      expect(papers.map((p) => p.reused), <bool>[false, false, true]);
      final shared = topics(papers[2])
          .intersection(topics(papers[0]).union(topics(papers[1])));
      expect(shared, hasLength(2));
      expect(topics(papers[0]).containsAll(shared), isTrue);
    });

    test('a paper built after the pool changed shares nothing with a stored '
        'one', () {
      final first = buildExam(pool(), seed: 1);
      final stored = <String>{for (final item in first.items) item.ref};
      // A word the first paper never asked is suspended in between.
      final full = pool();
      final unasked = full.words.firstWhere(
        (w) => !stored.contains(w.word.uid),
      );
      final changed = ExamPool(
        step: full.step,
        level: full.level,
        words: <ExamWord>[
          for (final w in full.words)
            if (w != unasked) w,
        ],
        topics: full.topics,
        categories: full.categories,
        connectors: full.connectors,
      );

      final second = buildExam(
        changed,
        seed: 2,
        sat: <int, Set<String>>{1: stored},
      );

      expect(second.items, hasLength(42));
      expect(
        second.items
            .map((i) => key(i.ref))
            .toSet()
            .intersection(stored.map(key).toSet()),
        isEmpty,
      );
    });

    test(
      'stored seeds are not drawn again, and the last paper still fills',
      () {
        final refs = <int, Set<String>>{
          for (var seed = 1; seed <= 2; seed++)
            seed: <String>{
              for (final item in buildExam(pool(), seed: seed).items) item.ref,
            },
        };

        final third = buildExam(pool(), seed: 3, sat: refs);

        expect(third.items, hasLength(42));
        expect(third.reused, isFalse);
        expect(
          third.items.map((i) => key(i.ref)).toSet().intersection(<String>{
            for (final ref in refs.values.expand((r) => r)) key(ref),
          }),
          isEmpty,
        );
      },
    );

    test('grammar items come from four topics when there are four', () {
      for (final step in <String>['A2.1', 'A2.2', 'B1.1']) {
        for (var seed = 1; seed <= 3; seed++) {
          final exam = buildExam(pool(step: step), seed: seed);
          final topics = <String>{
            for (final item in exam.items)
              if (item is GrammarQuestion) item.ref.split('#').first,
          };

          expect(topics, hasLength(4), reason: '$step $seed');
        }
      }
    });
  });

  group('BR-EXAM-03 what each section asks', () {
    final exam = buildExam(pool(), seed: 1);
    List<T> of<T extends ExamItem>(ExamSection section) =>
        exam.items.where((i) => i.section == section).cast<T>().toList();

    test('Vocabulary: the headword, its meaning expected', () {
      for (final item in of<WordQuestion>(ExamSection.vocabulary)) {
        final i = int.parse(item.ref.substring(1));
        expect(item.expected, 'meaning $i');
        expect(item.prompt, contains(tag(i)));
      }
    });

    test('in Bangla, the Bangla meaning where there is one', () {
      final bangla = buildExam(pool(), seed: 1, bangla: true);
      for (final item in bangla.items.whereType<WordQuestion>()) {
        final i = int.parse(item.ref.substring(1));
        final meaning = i % 5 == 0 ? 'meaning $i' : 'অর্থ $i';
        if (item.section == ExamSection.vocabulary) {
          expect(item.expected, meaning);
        }
        if (item.section == ExamSection.reverse) expect(item.prompt, meaning);
      }
    });

    test('Reverse: the meaning, the headword with its article expected', () {
      for (final item in of<WordQuestion>(ExamSection.reverse)) {
        final i = int.parse(item.ref.substring(1));
        expect(item.prompt, 'meaning $i');
        expect(item.expected, contains(tag(i)));
        if (i % 3 == 0) expect(item.expected.split(' '), hasLength(2));
      }
    });

    test('Articles: nouns only, three buttons', () {
      for (final item in of<WordQuestion>(ExamSection.articles)) {
        expect(<String>['der', 'die', 'das'], contains(item.expected));
        expect(item.options, <String>['der', 'die', 'das']);
        expect(item.prompt, 'Haus${tag(int.parse(item.ref.substring(1)))}');
      }
    });

    test('Word forms: a labelled form from the forms cell', () {
      for (final item in of<WordQuestion>(ExamSection.wordForms)) {
        expect(item.form, isNotNull);
        final i = int.parse(item.ref.substring(1));
        expect(switch (item.form!) {
          FormLabel.plural => 'Haus${tag(i)}er',
          FormLabel.thirdPerson => 'sag${tag(i)}t',
          _ => 'hat gesag${tag(i)}t',
        }, item.expected);
      }
    });

    test('Gap fill: an example with the word blanked', () {
      final gaps = of<GapQuestion>(ExamSection.gapFill);
      expect(gaps, hasLength(6));
      for (final gap in gaps) {
        final i = int.parse(gap.ref.substring(1));
        expect(i.isEven, isTrue, reason: 'only words with an example');
        expect(
          '${gap.before}${gap.answer}${gap.after}',
          anyOf('Das Haus${tag(i)} ist groß.', 'Wir sag${tag(i)}en heute.'),
        );
        expect(gap.translation, 'Example $i.');
      }
    });

    test('Gap fill expects the form the sentence uses', () {
      const rechnung = ExamWord(
        word: QuizWord(
          uid: 'r',
          german: 'Rechnung',
          english: 'bill',
          step: 'A2.1',
          pos: 'noun',
        ),
        examples: <({String german, String english})>[
          (german: 'Zwei Rechnungen liegen hier.', english: 'Two bills.'),
        ],
      );
      final exam = buildExam(
        const ExamPool(
          step: 'A2.1',
          level: 'A2',
          words: <ExamWord>[rechnung],
          topics: <GrammarSource>[],
        ),
        seed: 1,
      );
      final gap = exam.items.whereType<GapQuestion>().single;

      expect(gap.answer, 'Rechnungen');
      expect(gap.before, 'Zwei ');
      expect(gap.after, ' liegen hier.');
    });

    test('Listening: the headword, typed back', () {
      for (final item in of<WordQuestion>(ExamSection.listening)) {
        expect(item.expected, item.prompt);
      }
    });

    test('Writing: ten single-word targets from a category, the level\'s '
        'minimum, the connectors', () {
      final task = of<WritingTask>(ExamSection.writing).single;
      final id = int.parse(task.ref.split(':').last);

      expect(task.category, 'Kategorie $id');
      expect(task.targets, hasLength(10));
      expect(task.targets.toSet(), hasLength(10));
      expect(task.targets.any((t) => t.contains(' ')), isFalse);
      expect(task.minWords, 60);
      expect(task.connectors, <String>['und', 'aber', 'weil']);
      expect(task.expected, isNull);
    });

    test('the biggest categories go to papers 1, 2 and 3', () {
      expect(
        <String?>[
          for (var seed = 1; seed <= 3; seed++)
            buildExam(
              pool(),
              seed: seed,
            ).items.whereType<WritingTask>().single.category,
        ],
        <String>['Kategorie 0', 'Kategorie 1', 'Kategorie 2'],
      );
    });

    test('Speaking is about another category than the paper\'s writing', () {
      for (var seed = 1; seed <= 3; seed++) {
        final exam = buildExam(pool(), seed: seed);
        expect(
          exam.items.whereType<SpeakingTask>().single.category,
          isNot(exam.items.whereType<WritingTask>().single.category),
        );
      }
    });

    test('no target is a word the paper asks', () {
      final german = <String, String>{
        for (final w in pool().words) w.word.uid: w.word.german,
      };
      for (var seed = 1; seed <= 3; seed++) {
        final exam = buildExam(pool(), seed: seed);
        final asked = <String>{
          for (final item in exam.items) ?german[item.ref],
        };
        expect(
          exam.items
              .whereType<WritingTask>()
              .single
              .targets
              .toSet()
              .intersection(asked),
          isEmpty,
        );
      }
    });

    test('Speaking: a category, and the level\'s length', () {
      final task = of<SpeakingTask>(ExamSection.speaking).single;
      expect(task.seconds, 60);
      expect(task.category, startsWith('Kategorie'));
    });
  });

  test('FR-L12W-02 and FR-L12S-02 per level', () {
    expect(
      <int>[
        for (final l in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
          writingMinWords(l),
      ],
      <int>[30, 60, 100, 150, 200, 250],
    );
    expect(
      <int>[
        for (final l in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
          speakingSeconds(l),
      ],
      <int>[60, 60, 90, 90, 120, 120],
    );
  });

  group('FR-L12-01 a paper survives being stored', () {
    test('every item decodes to what was encoded', () {
      for (var seed = 1; seed <= 3; seed++) {
        for (final item in buildExam(pool(), seed: seed).items) {
          final row = item.encode();
          expect(ExamItem.decode(row).encode(), row, reason: row.prompt);
          expect(ExamItem.decode(row).runtimeType, item.runtimeType);
        }
      }
    });

    test('every kind of grammar item round-trips', () {
      final items = <GrammarItem>[
        const GapFill(
          before: 'Ich ',
          after: ' heute.',
          answer: 'gehe',
          translation: 'I go.',
        ),
        const PickTheForm(
          before: 'Ich ',
          after: '.',
          options: <String>['gehe', 'geht', 'gehen'],
          answer: 'gehe',
        ),
        const SpotTheError(
          tokens: <String>['Ich', 'geht', 'heute.'],
          wrong: 1,
          correction: 'gehe',
        ),
        const OrderTheSentence(
          chips: <String>['heute', 'Ich', 'gehe'],
          answer: <String>['Ich', 'gehe', 'heute'],
        ),
        const RuleRecall(
          question: 'Which rule?',
          options: <String>['a', 'b', 'c', 'd'],
          answer: 2,
        ),
      ];
      final expected = <String>['gehe', 'gehe', '1', 'Ich gehe heute', '2'];
      for (final (i, item) in items.indexed) {
        final question = GrammarQuestion('g#$i', item);
        final row = question.encode();
        expect(row.expected, expected[i]);
        expect(ExamItem.decode(row).encode(), row);
      }
      expect(GrammarQuestion('g#1', items[1]).options, <String>[
        'gehe',
        'geht',
        'gehen',
      ]);
      expect(GrammarQuestion('g#4', items[4]).options, <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(GrammarQuestion('g#0', items[0]).options, isNull);
    });
  });
}
