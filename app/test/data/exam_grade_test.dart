@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/domain/exam_generator.dart';

/// `ExamRepository.grade` — #84.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ExamRepository exams;

  setUp(() {
    db = AppDatabase.memory();
    exams = ExamRepository(db);
  });

  tearDown(() => db.close());

  /// Four Articles questions, then Writing and Speaking: 12 points.
  Future<int> sit({int seed = 1}) => exams.begin(
    sublevelCode: 'A1.1',
    seed: seed,
    startedAt: '2026-09-21T08:00:00Z',
    questions: <ExamQuestion>[
      for (var i = 0; i < 4; i++)
        ExamQuestion.of(
          i + 1,
          WordQuestion(
            ExamSection.articles,
            'w$i',
            prompt: 'Haus',
            expected: 'das',
          ),
        ),
      ExamQuestion.of(
        5,
        const WritingTask(
          'writing:1',
          level: 'A1',
          category: 'Wohnen',
          targets: <String>['a', 'b', 'c', 'd', 'e', 'f'],
          minWords: 30,
          connectors: <String>[],
        ),
      ),
      ExamQuestion.of(
        6,
        const SpeakingTask(
          'speaking:1',
          level: 'A1',
          category: 'Wohnen',
          seconds: 60,
        ),
      ),
    ],
  );

  Future<void> answer(int id, int ord, String? given, {List<bool>? rubric}) =>
      exams.answer(
        attemptId: id,
        ord: ord,
        given: given,
        selfRubricJson: rubric == null ? null : jsonEncode(rubric),
      );

  Future<ExamAttempt> attempt(int id) =>
      (db.select(db.examAttempts)..where((t) => t.id.equals(id))).getSingle();

  test("#775 a paper in Russian is graded in Russian: a comma is the "
      "language's own", () async {
    Future<double> graded(String? lang) async {
      final id = await exams.begin(
        sublevelCode: 'A1.1',
        seed: lang == null ? 2 : 3,
        startedAt: '2026-09-21T08:00:00Z',
        meaningLang: lang,
        questions: <ExamQuestion>[
          ExamQuestion.of(
            1,
            const WordQuestion(
              ExamSection.vocabulary,
              'indem',
              prompt: 'indem',
              expected: 'тем, что / благодаря тому, что',
            ),
          ),
        ],
      );
      await answer(id, 1, 'что');
      return (await exams.grade(id, passPercent: 60)).scorePoints;
    }

    expect(await graded('ru'), 0);
    expect(await graded(null), 1, reason: 'before v5: English or Bangla');
  });

  test('each row gets its points, and the attempt its score', () async {
    final id = await sit();
    await answer(id, 1, 'das');
    await answer(id, 2, 'das');
    await answer(id, 3, 'der');
    // 4 left empty.
    await answer(
      id,
      6,
      'recordings/1.m4a',
      rubric: <bool>[true, true, false, false],
    );

    final score = await exams.grade(
      id,
      passPercent: 60,
      finishedAt: '2026-09-21T08:30:00Z',
    );

    final rows = await exams.answersFor(id).get();
    expect(rows.map((r) => r.points), <double>[1, 1, 0, 0, 0, 2]);
    expect(score.scorePoints, 4);
    expect(score.maxPoints, 12);
    expect(score.passed, isFalse);
    final row = await attempt(id);
    expect(row.scorePoints, 4);
    expect(row.maxPoints, 12);
    expect(row.passed, 0);
    expect(row.status, 'finished');
    expect(row.finishedAt, '2026-09-21T08:30:00Z');
  });

  test('BR-EXAM-04 a pass marks the step, by query', () async {
    final passed = <bool>[];
    // The hub's seeds, where a pass shows (the step's *Passed* chip reads
    // the same attempts).
    final watching = exams
        .watchSeeds('A1.1')
        .listen((seeds) => passed.add(seeds.any((s) => s.everPassed)));
    addTearDown(watching.cancel);

    final id = await sit();
    for (var ord = 1; ord <= 4; ord++) {
      await answer(id, ord, 'das');
    }
    await answer(
      id,
      6,
      'recordings/1.m4a',
      rubric: <bool>[true, true, true, true],
    );
    final score = await exams.grade(
      id,
      passPercent: 60,
      finishedAt: '2026-09-21T08:30:00Z',
    );
    await pumpEventQueue();

    // 8 of 12 is 67 %.
    expect(score.passed, isTrue);
    expect(passed.last, isTrue);
  });

  test('the pass mark is the setting\'s', () async {
    final id = await sit();
    for (var ord = 1; ord <= 4; ord++) {
      await answer(id, ord, 'das');
    }
    await answer(
      id,
      6,
      'recordings/1.m4a',
      rubric: <bool>[true, true, true, true],
    );

    expect((await exams.grade(id, passPercent: 60)).passed, isTrue);
    expect((await exams.grade(id, passPercent: 70)).passed, isFalse);
  });

  test(
    'FR-L13-03 a rubric ticked later re-grades, and does not finish',
    () async {
      final id = await sit();
      await answer(id, 1, 'das');
      await exams.grade(
        id,
        passPercent: 60,
        finishedAt: '2026-09-21T08:30:00Z',
      );

      await answer(id, 5, 'kurz', rubric: <bool>[true, true]);
      final regraded = await exams.grade(id, passPercent: 60);

      expect(regraded.scorePoints, 3);
      final row = await attempt(id);
      expect(row.scorePoints, 3);
      expect(row.finishedAt, '2026-09-21T08:30:00Z');
    },
  );

  test('graded but not submitted stays in progress', () async {
    final id = await sit();
    await exams.grade(id, passPercent: 60);

    expect((await attempt(id)).status, 'in_progress');
  });

  test('#911 FR-L12-04 a submit that lost the race to Leave finishes '
      'nothing: the attempt stays abandoned and unscored', () async {
    final id = await sit();
    await answer(id, 1, 'das');
    expect(await exams.abandon(id), isTrue);

    await expectLater(
      exams.grade(id, passPercent: 60, finishedAt: '2026-09-21T08:30:00Z'),
      throwsStateError,
    );

    final row = await attempt(id);
    expect(row.status, 'abandoned');
    expect(row.finishedAt, isNull);
    expect(row.scorePoints, 0);
    // The rows' points roll back with it.
    expect((await exams.answersFor(id).get()).first.points, 0);
  });
}
