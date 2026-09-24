@TestOn('vm')
library;

import 'dart:convert';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

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

  test('each row gets its points, and the attempt its score', () async {
    final id = await sit();
    await answer(id, 1, 'das');
    await answer(id, 2, 'das');
    await answer(id, 3, 'der');
    // 4 left empty.
    await answer(id, 6, null, rubric: <bool>[true, true, false, false]);

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
    final watching = exams.watchStepPassed('A1.1').listen(passed.add);
    addTearDown(watching.cancel);

    final id = await sit();
    for (var ord = 1; ord <= 4; ord++) {
      await answer(id, ord, 'das');
    }
    await answer(id, 6, null, rubric: <bool>[true, true, true, true]);
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
    await answer(id, 6, null, rubric: <bool>[true, true, true, true]);

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

      expect(regraded.scorePoints, 2);
      final row = await attempt(id);
      expect(row.scorePoints, 2);
      expect(row.finishedAt, '2026-09-21T08:30:00Z');
    },
  );

  test('graded but not submitted stays in progress', () async {
    final id = await sit();
    await exams.grade(id, passPercent: 60);

    expect((await attempt(id)).status, 'in_progress');
  });
}
