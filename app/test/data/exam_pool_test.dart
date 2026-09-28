@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/domain/exam_grading.dart' show sameTargetFamily;
import 'package:sogda/domain/grammar_item_generator.dart';

import '../db/content_fixture.dart';

/// `ExamRepository.pool` and the generator over it — #83.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ExamRepository exams;

  Future<void> open(File content) async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    exams = ExamRepository(db);
  }

  group('BR-EXAM-02 the pool, over the fixture', () {
    late Directory directory;

    setUp(() async {
      directory = tempDir('sogda_exam');
      await open(ContentFixture.write('${directory.path}/content.db').file);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'the step\'s words with their examples and category, the level',
      () async {
        final pool = await exams.pool('A1.1');

        expect(pool.level, 'A1');
        expect(pool.words.map((w) => w.word.uid), <String>[
          ContentFixture.haus,
          ContentFixture.tuer,
        ]);
        final haus = pool.words.first;
        expect(haus.word.headword, 'das Haus');
        expect(haus.word.bangla, 'বাড়ি');
        expect(haus.category, 1);
        expect(haus.examples, <({String german, String english})>[
          (german: 'Das Haus ist groß.', english: 'The house is big.'),
          // No translation in the course: an empty one, not a crash.
          (german: 'Ich sehe das Haus.', english: ''),
        ]);
        expect(pool.categories, <int, String>{1: 'Wohnen'});
      },
    );

    test('a suspended word is left out, any other status kept', () async {
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: ContentFixture.tuer,
              status: const Value('suspended'),
            ),
          );
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: ContentFixture.haus,
              status: const Value('done'),
            ),
          );

      final pool = await exams.pool('A1.1');
      expect(pool.words.map((w) => w.word.uid), <String>[ContentFixture.haus]);
    });

    test(
      '#832 and the course words that share a meaning, for Reverse',
      () async {
        await db.customStatement('''
INSERT INTO c.words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
  article, german, pos, english, bangla, search_key, search_key_alt, kind)
VALUES ('uid-heim', 'A1.2', 'A1', 9, 9, 'das', 'Heim', 'noun', 'house',
  'ঘর', 'heim', 'heim', 'vocab')
''');
        final pool = await exams.pool('A1.1');
        expect(pool.sharedMeanings['house']!.map((w) => w.uid), <String>[
          ContentFixture.haus,
          'uid-heim',
        ]);
      },
    );

    test('the step\'s grammar topics, with their tags', () async {
      final pool = await exams.pool('A1.1');

      expect(pool.topics.single.uid, 'g1');
      expect(pool.topics.single.rule, 'The verb is second.');
      expect(pool.topics.single.tags, contains('word-order'));
      expect((await exams.pool('A1.2')).topics, isEmpty);
    });

    test('a paper is stored and read back whole', () async {
      final exam = buildExam(await exams.pool('A1.1'), seed: 1);
      final id = await exams.begin(
        sublevelCode: 'A1.1',
        seed: 1,
        startedAt: '2026-09-21T08:00:00Z',
        questions: <ExamQuestion>[
          for (final (i, item) in exam.items.indexed)
            ExamQuestion.of(i + 1, item),
        ],
      );

      final rows = await exams.answersFor(id).get();
      expect(rows, hasLength(exam.items.length));
      for (final (i, row) in rows.indexed) {
        final item = ExamItem.decode((
          section: row.section,
          ref: row.itemRef,
          prompt: row.prompt,
          options: row.optionsJson,
          expected: row.expected,
        ));
        expect(item.encode(), exam.items[i].encode());
        expect(row.ord, i + 1);
      }
    });

    test('what was sat, by seed, and the paper a retake sits again', () async {
      expect(await exams.satRefs('A1.1'), isEmpty);
      expect(await exams.storedPaper('A1.1', 1), isNull);

      final exam = buildExam(await exams.pool('A1.1'), seed: 1);
      final questions = <ExamQuestion>[
        for (final (i, item) in exam.items.indexed)
          ExamQuestion.of(i + 1, item),
      ];
      final first = await exams.begin(
        sublevelCode: 'A1.1',
        seed: 1,
        startedAt: '2026-09-21T08:00:00Z',
        questions: questions,
      );
      await exams.abandon(first);

      expect(await exams.satRefs('A1.1'), <int, Set<String>>{
        1: <String>{for (final item in exam.items) item.ref},
      });
      final again = await exams.storedPaper('A1.1', 1);
      expect(
        <String>[for (final q in again!) '${q.ord} ${q.section} ${q.prompt}'],
        <String>[
          for (final q in questions) '${q.ord} ${q.section} ${q.prompt}',
        ],
      );
      expect(again.map((q) => q.itemRef), questions.map((q) => q.itemRef));
      expect(again.map((q) => q.expected), questions.map((q) => q.expected));
      expect(await exams.storedPaper('A1.1', 2), isNull);
      expect(await exams.satRefs('A1.2'), isEmpty);
    });
  });

  group('every step of the real course', () {
    setUpAll(() async => open(realContent()));
    tearDownAll(() => db.close());

    const steps = <String>[
      'A1.1', 'A1.2', 'A2.1', 'A2.2', 'B1.1', 'B1.2', //
      'B2.1', 'B2.2', 'C1.1', 'C1.2', 'C2.1', 'C2.2',
    ];

    String key(String ref) => ref.split('#').first;

    test('#752 FR-L15-01 no Pick the form borrows a sentence from a later '
        'step than its topic', () async {
      // The earliest step each example sentence is a word's example in.
      final firstStep = <String, int>{};
      for (final row
          in await db
              .customSelect(
                'SELECT e.german AS german, s.ord AS step FROM word_examples e '
                'JOIN words w ON w.uid = e.word_uid '
                'JOIN sublevels s ON s.code = w.sublevel_code',
              )
              .get()) {
        // Compared without spaces: an item's parts leave out the blank's.
        final german = row.read<String>('german').replaceAll(RegExp(r'\s'), '');
        final step = row.read<int>('step');
        final known = firstStep[german];
        if (known == null || step < known) firstStep[german] = step;
      }
      final order = <String, int>{
        for (final row
            in await db.customSelect('SELECT code, ord FROM sublevels').get())
          row.read<String>('code'): row.read<int>('ord'),
      };

      final later = <String>[];
      for (final step in steps) {
        final pool = await exams.pool(step);
        for (final topic in pool.topics) {
          for (var seed = 1; seed <= 20; seed++) {
            for (final item in generateItems(
              topic,
              seed: seed,
              course: pool.course,
            ).whereType<PickTheForm>()) {
              final sentence = '${item.before}${item.answer}${item.after}'
                  .replaceAll(RegExp(r'\s'), '');
              final from = firstStep[sentence];
              if (from != null && from > order[step]!) {
                later.add('[$step] ${topic.topic}: $sentence');
              }
            }
          }
        }
      }
      expect(later.toSet(), isEmpty);
    });

    test('#753 every Writing and Speaking task is about a theme, never a word '
        'class or a language feature', () async {
      // What SQA and #908's review saw drawn, held apart from `notThemes` so
      // a name dropped from the list is caught too: the word classes, B2.1's
      // level label and C1.1's register.
      const reported = <String>{
        'Core verbs',
        'Core adjectives & adverbs',
        'Numbers, time & dates',
        'Question words & pronouns',
        'Connectors & function words',
        'Everyday life at B2',
        'Advanced verbs',
        'Verbs with prepositions',
        'Advanced adjectives & adverbs',
        'Idioms & sayings',
        'Professional & leadership language',
      };
      for (final step in steps) {
        final pool = await exams.pool(step);
        final themes = pool.categories.values.where(
          (name) => !notThemes.contains(name),
        );
        expect(
          themes.length,
          greaterThanOrEqualTo(themesPerStep),
          reason: '$step has too few themes for three papers',
        );
        for (var seed = 1; seed <= 3; seed++) {
          final paper = buildExam(pool, seed: seed);
          for (final category in <String?>[
            paper.items.whereType<WritingTask>().single.category,
            paper.items.whereType<SpeakingTask>().single.category,
          ]) {
            expect(category, isNotNull, reason: '$step $seed');
            expect(notThemes, isNot(contains(category)), reason: '$step $seed');
            expect(reported, isNot(contains(category)), reason: '$step $seed');
          }
        }
      }
    });

    test('#753 every name the generator leaves out is a category of the '
        'course', () async {
      final names = <String>{
        for (final row
            in await db.customSelect('SELECT name FROM c.categories').get())
          row.read<String>('name'),
      };
      expect(notThemes.difference(names), isEmpty);
    });

    for (final listening in <bool>[true, false]) {
      test('BR-EXAM-02/03 three full papers that never share an item'
          '${listening ? '' : ', listening off'}', () async {
        for (final step in steps) {
          final pool = await exams.pool(step);
          final papers = <Exam>[
            for (var seed = 1; seed <= 3; seed++)
              buildExam(pool, seed: seed, listening: listening),
          ];
          final german = <String, String>{
            for (final w in pool.words) w.word.uid: w.word.german,
          };
          final grammar = <String>[];
          final rest = <String>[];
          for (final paper in papers) {
            final why = '$step ${paper.seed}';
            expect(paper.items, hasLength(42), reason: why);
            expect(paper.maxPoints, 48, reason: why);
            for (final item in paper.items) {
              (item is GrammarQuestion ? grammar : rest).add(key(item.ref));
            }
            // FR-L12W-01 matches tokens: a phrase could never be found; and
            // no target is an answer the learner could go back and copy.
            final task = paper.items.whereType<WritingTask>().single;
            expect(task.targets.toSet(), hasLength(10), reason: why);
            expect(task.targets.where((t) => t.contains(' ')), isEmpty);
            // #388: one of a word family, so one word never reads as two.
            for (final (i, a) in task.targets.indexed) {
              for (final b in task.targets.skip(i + 1)) {
                expect(sameTargetFamily(a, b), isFalse, reason: '$why $a $b');
              }
            }
            expect(
              task.targets.toSet().intersection(<String>{
                for (final item in paper.items) ?german[item.ref],
              }),
              isEmpty,
              reason: why,
            );
          }
          // Words and tasks never repeat. Grammar needs twelve topics for
          // that; with fewer, the last paper reuses and says so.
          expect(rest.toSet(), hasLength(rest.length), reason: step);
          final enough = pool.topics.length >= 12;
          expect(grammar.toSet().length, enough ? 12 : pool.topics.length);
          expect(papers.map((p) => p.reused), <bool>[
            false,
            false,
            !enough,
          ], reason: step);
        }
      });
    }

    test('the writing task: ten targets, and the course\'s connectors so '
        'far', () async {
      final first = buildExam(await exams.pool('A1.1'), seed: 1);
      final last = buildExam(await exams.pool('C2.2'), seed: 1);
      final a1 = first.items.whereType<WritingTask>().single;
      final c2 = last.items.whereType<WritingTask>().single;

      expect(a1.targets, hasLength(10));
      expect(a1.minWords, 30);
      expect(c2.minWords, 250);
      expect(c2.connectors.length, greaterThan(a1.connectors.length));
      expect(c2.connectors, containsAll(a1.connectors));
    });

    test(
      'the connectors are the course\'s so far, each once, as typed',
      () async {
        // `weil` is A2.1's: A1.2 has only A1.1's three.
        expect((await exams.pool('A1.2')).connectors, <String>[
          'aber',
          'oder',
          'und',
        ]);
        final all = (await exams.pool('C2.2')).connectors;
        expect(all.toSet(), hasLength(all.length));
        expect(all, containsAll(<String>['weil', 'falls', 'sintemal']));
        expect(all.where((c) => c.contains(RegExp(r'[↔/(]'))), isEmpty);
      },
    );
  });
}
