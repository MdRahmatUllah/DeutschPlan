import 'dart:math';

import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// `quiz_builder.dart` — #81, `docs/03-domain/quiz-engine.md`.
void main() {
  const today = '2026-09-21';

  QuizWord noun(
    String uid,
    String german,
    String english, {
    String article = 'die',
    String step = 'A1.1',
    String? forms,
    String? bangla = 'বাংলা',
    double stability = 5,
    String? lastReview = '2026-09-10',
    String? synonyms,
  }) => QuizWord(
    uid: uid,
    german: german,
    english: english,
    step: step,
    article: article,
    pos: 'noun',
    bangla: bangla == 'বাংলা' ? '$bangla $uid' : bangla,
    forms: forms,
    stability: stability,
    lastReview: lastReview,
    synonyms: synonyms,
  );

  QuizWord verb(
    String uid,
    String german,
    String english, {
    String? forms,
    String step = 'A1.1',
  }) => QuizWord(
    uid: uid,
    german: german,
    english: english,
    step: step,
    pos: 'verb',
    bangla: 'বাংলা $uid',
    forms: forms,
    stability: 5,
    lastReview: '2026-09-10',
  );

  Future<Quiz> build(
    List<QuizWord> learned, {
    QuizDirection direction = QuizDirection.deEn,
    int length = 10,
    int seed = 7,
    List<QuizWord>? pool,
  }) => QuizBuilder(_Store(learned, pool ?? learned)).build(
    direction: direction,
    source: QuizSource.stepLearned,
    sourceRef: 'A1.1',
    length: length,
    seed: seed,
    today: today,
  );

  final twelve = <QuizWord>[
    for (var i = 0; i < 12; i++)
      noun('n$i', 'Wort$i', 'word $i', forms: 'Wörter$i'),
  ];

  group('directions', () {
    test(
      'DE → EN asks the headword and expects the meaning, with four tiles',
      () async {
        final quiz = await build(twelve, length: 1);
        final item = quiz.items.single;
        final word = twelve.firstWhere((w) => w.uid == item.wordUid);
        expect(item.direction, QuizDirection.deEn);
        expect(item.prompt, 'die ${word.german}');
        expect(item.expected, word.english);
        expect(item.options, hasLength(4));
        expect(item.options, contains(word.english));
        expect(item.ord, 1);
      },
    );

    test('DE → বাংলা expects the Bangla, and skips words without it', () async {
      final words = <QuizWord>[
        ...twelve.take(3),
        noun('x', 'Ohne', 'without', bangla: null),
      ];
      final quiz = await build(words, direction: QuizDirection.deBn);
      expect(quiz.items.map((i) => i.wordUid), isNot(contains('x')));
      final item = quiz.items.first;
      expect(
        item.expected,
        words.firstWhere((w) => w.uid == item.wordUid).bangla,
      );
    });

    test(
      'EN → DE asks the meaning and expects the headword with its article',
      () async {
        final item = (await build(
          twelve,
          direction: QuizDirection.enDe,
          length: 1,
        )).items.single;
        final word = twelve.firstWhere((w) => w.uid == item.wordUid);
        expect(
          (item.prompt, item.expected),
          (word.english, 'die ${word.german}'),
        );
        expect(item.options, contains('die ${word.german}'));
      },
    );

    test(
      'articles needs an article: the noun without it, der/die/das expected',
      () async {
        final words = <QuizWord>[
          noun('a', 'Tür', 'door'),
          verb('v', 'gehen', 'to go'),
        ];
        final quiz = await build(words, direction: QuizDirection.articles);
        expect(
          quiz.items.map((i) => (i.wordUid, i.prompt, i.expected)),
          <(String, String, String)>[('a', 'Tür', 'die')],
        );
        expect(
          quiz.items.single.options,
          isEmpty,
          reason: 'three fixed buttons, not tiles',
        );
      },
    );

    test('listening plays the headword and expects it typed', () async {
      final item = (await build(
        twelve,
        direction: QuizDirection.listening,
        length: 1,
      )).items.single;
      expect(item.prompt, item.expected);
      expect(item.expected, startsWith('die Wort'));
    });

    test(
      'forms needs a parsable forms cell and names the form it asks for',
      () async {
        final words = <QuizWord>[
          noun('h', 'Haus', 'house', article: 'das', forms: 'Häuser'),
          verb('g', 'gehen', 'to go', forms: 'geht · ist gegangen'),
          verb(
            'e',
            'erklären',
            'to explain',
            forms: 'erklärt · erläutert · legt dar',
          ),
          noun('none', 'Luft', 'air'),
        ];
        final quiz = await build(words, direction: QuizDirection.forms);
        expect(quiz.items.map((i) => i.wordUid).toSet(), <String>{'h', 'g'});
        for (final item in quiz.items) {
          final pairs = parseForms(
            words.firstWhere((w) => w.uid == item.wordUid),
          );
          expect(pairs, contains((item.form, item.expected)));
          expect(
            item.prompt,
            words.firstWhere((w) => w.uid == item.wordUid).german,
          );
        }
      },
    );

    test(
      'mixed rotates DE → EN, DE → বাংলা, EN → DE, articles, listening, forms, '
      'skipping those that do not apply',
      () async {
        final words = <QuizWord>[
          for (var i = 0; i < 6; i++)
            noun('n$i', 'Wort$i', 'word $i', forms: 'Wörter$i'),
        ];
        final quiz = await build(words, direction: QuizDirection.mixed);
        expect(quiz.items.map((i) => i.direction), rotation);
        final plainVerb = verb('v', 'gehen', 'to go');
        // No article, no forms: item 3 (articles) falls through to listening.
        expect(mixedDirection(3, plainVerb), QuizDirection.listening);
        expect(
          mixedDirection(5, plainVerb),
          QuizDirection.deEn,
          reason: 'forms wraps to the start',
        );
      },
    );
  });

  group('BR-QUIZ-01 selection', () {
    test('the length, or fewer when fewer words qualify', () async {
      expect((await build(twelve, length: 10)).items, hasLength(10));
      expect(
        (await build(twelve.take(4).toList(), length: 10)).items,
        hasLength(4),
      );
      expect((await build(const <QuizWord>[])).items, isEmpty);
    });

    test('a word is asked once', () async {
      final uids = (await build(
        twelve,
        length: 10,
      )).items.map((i) => i.wordUid);
      expect(uids.toSet(), hasLength(10));
    });

    test(
      'the same seed builds the same quiz; another seed another order',
      () async {
        final a = await build(twelve, seed: 1);
        final b = await build(twelve, seed: 1);
        final c = await build(twelve, seed: 2);
        String key(Quiz q) =>
            q.items.map((i) => '${i.wordUid}:${i.options.join('|')}').join(',');
        expect(key(a), key(b));
        expect(key(a), isNot(key(c)));
      },
    );

    test(
      'prefers the lowest retrievability: only the weakest 2× length are drawn',
      () {
        final fsrs = Fsrs();
        final words = <QuizWord>[
          for (var i = 0; i < 40; i++)
            // Stability rises with i: word 0 is the most likely forgotten.
            noun(
              'n$i',
              'Wort$i',
              'word $i',
              stability: 1.0 + i,
              lastReview: '2026-09-01',
            ),
        ];
        for (var seed = 0; seed < 20; seed++) {
          final picked = pickWords(
            words,
            length: 10,
            today: today,
            fsrs: fsrs,
            random: Random(seed),
          );
          expect(picked, hasLength(10));
          for (final word in picked) {
            expect(
              int.parse(word.uid.substring(1)),
              lessThan(20),
              reason: 'seed $seed picked ${word.uid}',
            );
          }
        }
      },
    );

    test('a word never reviewed counts as the weakest', () {
      final words = <QuizWord>[
        noun(
          'strong',
          'Stark',
          'strong',
          stability: 100,
          lastReview: '2026-09-20',
        ),
        noun('never', 'Nie', 'never', lastReview: null),
      ];
      final picked = pickWords(
        words,
        length: 1,
        today: today,
        fsrs: Fsrs(),
        random: Random(1),
      );
      // The window is 2 words, so either may be drawn; the ranking puts the
      // unreviewed one first.
      expect(picked, hasLength(1));
      final ranked = pickWords(
        words,
        length: 2,
        today: today,
        fsrs: Fsrs(),
        random: Random(1),
      );
      expect(ranked.map((w) => w.uid).toSet(), <String>{'strong', 'never'});
    });
  });

  group('distractors', () {
    String english(QuizWord w) => w.english;

    test('three, the same part of speech and step first', () {
      final answer = noun('a', 'Tür', 'door');
      final pool = <QuizWord>[
        answer,
        verb('v1', 'gehen', 'to go'),
        noun('far', 'Berg', 'mountain', step: 'B1.1'),
        noun('n1', 'Tisch', 'table'),
        noun('n2', 'Stuhl', 'chair'),
        noun('n3', 'Fenster', 'window'),
      ];
      final wrong = distractors(answer, pool, english, Random(3));
      expect(wrong.toSet(), <String>{'table', 'chair', 'window'});
    });

    test(
      'the step outranks the seed: same-step nouns beat other-step nouns',
      () {
        final answer = noun('a', 'Tür', 'door');
        final pool = <QuizWord>[
          answer,
          for (var i = 0; i < 5; i++)
            noun('far$i', 'Berg$i', 'mountain $i', step: 'B1.1'),
          noun('n1', 'Tisch', 'table'),
          noun('n2', 'Stuhl', 'chair'),
          noun('n3', 'Fenster', 'window'),
        ];
        for (var seed = 0; seed < 20; seed++) {
          expect(
            distractors(answer, pool, english, Random(seed)).toSet(),
            <String>{'table', 'chair', 'window'},
            reason: 'seed $seed',
          );
        }
      },
    );

    test('fall back to other steps, then other parts of speech', () {
      final answer = noun('a', 'Tür', 'door');
      final pool = <QuizWord>[
        answer,
        verb('v1', 'gehen', 'to go'),
        noun('far', 'Berg', 'mountain', step: 'B1.1'),
        noun('n1', 'Tisch', 'table'),
      ];
      final wrong = distractors(answer, pool, english, Random(3));
      expect(wrong, <String>['table', 'mountain', 'to go']);
    });

    test(
      'never a synonym: no shared meaning, no word the synonyms cell names',
      () {
        final answer = noun(
          'a',
          'Absicht',
          'intention / purpose',
          synonyms: 'das Vorhaben, der Plan; mit Absicht',
        );
        final pool = <QuizWord>[
          answer,
          noun('s1', 'Zweck', 'purpose'),
          noun('s2', 'Vorhaben', 'project', article: 'das'),
          noun('s3', 'Plan', 'plan', article: 'der'),
          noun('ok1', 'Tisch', 'table'),
          noun('ok2', 'Stuhl', 'chair'),
          noun('ok3', 'Fenster', 'window'),
          // "an" is inside "Anliegen", but it is not a word the cell names.
          noun('ok4', 'an', 'at', article: 'der'),
        ];
        final wrong = distractors(answer, pool, english, Random(5), count: 10);
        expect(wrong.toSet(), <String>{'table', 'chair', 'window', 'at'});
      },
    );

    test('never the answer twice, nor two tiles alike', () {
      final answer = noun('a', 'Tür', 'door');
      final pool = <QuizWord>[
        answer,
        noun('dup', 'Pforte', 'door'),
        noun('n1', 'Tisch', 'table'),
        noun('n2', 'Tafel', 'table'),
        noun('n3', 'Stuhl', 'chair'),
      ];
      final wrong = distractors(answer, pool, english, Random(1));
      expect(wrong, isNot(contains('door')));
      expect(wrong.toSet(), hasLength(wrong.length));
      expect(wrong.toSet(), <String>{'table', 'chair'});
    });

    test(
      'the quiz draws them from the step\'s whole pool, not only learned words',
      () async {
        final learned = <QuizWord>[noun('a', 'Tür', 'door')];
        final pool = <QuizWord>[
          ...learned,
          noun('p1', 'Tisch', 'table'),
          noun('p2', 'Stuhl', 'chair'),
          noun('p3', 'Fenster', 'window'),
        ];
        final item = (await build(learned, pool: pool)).items.single;
        expect(item.options.toSet(), <String>{
          'door',
          'table',
          'chair',
          'window',
        });
      },
    );
  });

  group('forms', () {
    test('a noun: its plural, spelled out or as an ending', () {
      expect(
        parseForms(noun('h', 'Haus', 'house', forms: 'Häuser')),
        <(FormLabel, String)>[(FormLabel.plural, 'Häuser')],
      );
      expect(
        parseForms(noun('f', 'Frau', 'woman', forms: '-en')),
        <(FormLabel, String)>[(FormLabel.plural, 'Frauen')],
      );
    });

    test('a verb or phrase: 3rd person and Perfekt', () {
      expect(
        parseForms(
          verb(
            'g',
            'aufstehen',
            'to get up',
            forms: 'steht auf · ist aufgestanden',
          ),
        ),
        <(FormLabel, String)>[
          (FormLabel.thirdPerson, 'steht auf'),
          (FormLabel.perfekt, 'ist aufgestanden'),
        ],
      );
    });

    test('an adjective or adverb: comparative and superlative', () {
      const gut = QuizWord(
        uid: 'g',
        german: 'gut',
        english: 'good',
        step: 'A1.1',
        pos: 'adj',
        forms: 'besser · am besten',
      );
      expect(parseForms(gut), <(FormLabel, String)>[
        (FormLabel.comparative, 'besser'),
        (FormLabel.superlative, 'am besten'),
      ]);
    });

    test('a synonym set or an empty cell is not asked', () {
      expect(
        parseForms(
          verb(
            'e',
            'erklären',
            'to explain',
            forms: 'erklärt · erläutert · legt dar',
          ),
        ),
        isEmpty,
      );
      expect(parseForms(verb('x', 'gehen', 'to go')), isEmpty);
      expect(parseForms(verb('y', 'gehen', 'to go', forms: '  ')), isEmpty);
    });

    test('every forms cell in the real content.db parses, but for the four synonym sets', () {
      final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
      addTearDown(db.close);
      final rows = db.select(
        "SELECT uid, german, article, pos, english, forms, sublevel_code FROM words "
        "WHERE forms IS NOT NULL AND trim(forms) != ''",
      );
      final unparsed = <String>[
        for (final row in rows)
          if (parseForms(
            QuizWord(
              uid: row['uid'] as String,
              german: row['german'] as String,
              article: row['article'] as String?,
              pos: row['pos'] as String?,
              english: row['english'] as String,
              forms: row['forms'] as String?,
              step: row['sublevel_code'] as String,
            ),
          ).isEmpty)
            '${row['german']}: ${row['forms']}',
      ];
      expect(rows.length, greaterThan(3000));
      expect(unparsed, hasLength(4), reason: unparsed.join('\n'));
      expect(
        unparsed.every((u) => u.split('·').length == 3),
        isTrue,
        reason: unparsed.join('\n'),
      );
    });
  });

  test('the wire names round-trip', () {
    for (final d in QuizDirection.values) {
      expect(QuizDirection.parse(d.name), d);
    }
    for (final s in QuizSource.values) {
      expect(QuizSource.parse(s.name), s);
    }
    expect(() => QuizDirection.parse('sideways'), throwsArgumentError);
  });
}

class _Store implements QuizStore {
  _Store(this._learned, this._pool);

  final List<QuizWord> _learned;
  final List<QuizWord> _pool;

  @override
  Future<List<QuizWord>> learned(QuizSource source, {String? ref}) async =>
      _learned;

  @override
  Future<List<QuizWord>> stepWords(String step) async =>
      _pool.where((w) => w.step == step).toList();
}
