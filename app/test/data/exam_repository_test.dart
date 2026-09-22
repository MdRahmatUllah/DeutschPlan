@TestOn('vm')
library;

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

/// `ExamRepository`. No content is read here — an exam is built from content
/// by the generator and handed over already formed, so these tests are about
/// what survives a crash, a pause and a second attempt.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ExamRepository exams;

  setUp(() {
    // `AppDatabase.memory()` rather than a bare connection: it runs
    // `configureConnection`, and without `PRAGMA foreign_keys = ON` the
    // cascade from `exam_attempts` to `exam_answers` is decoration.
    db = AppDatabase.memory();
    exams = ExamRepository(db);
  });

  tearDown(() => db.close());

  List<ExamQuestion> paper({int count = 3}) => <ExamQuestion>[
    for (var ord = 1; ord <= count; ord++)
      ExamQuestion(
        ord: ord,
        section: ord == count ? 'writing' : 'vocabulary',
        prompt: 'Question $ord',
        itemRef: 'uid-$ord',
        expected: ord == count ? null : 'answer $ord',
      ),
  ];

  Future<int> begin({
    String code = 'A1.1',
    int seed = 1,
    int count = 3,
    String startedAt = '2026-03-04T09:00:00Z',
  }) => exams.begin(
    sublevelCode: code,
    seed: seed,
    startedAt: startedAt,
    questions: paper(count: count),
  );

  group('beginning an exam', () {
    test('pre-inserts every question', () async {
      final id = await begin();
      final answers = await exams.watchAnswers(id).first;

      expect(answers, hasLength(3));
      expect(answers.map((a) => a.ord), <int>[1, 2, 3]);
      expect(answers.first.prompt, 'Question 1');
      expect(answers.first.expected, 'answer 1');
      expect(answers.every((a) => a.given == null), isTrue);
    });

    test('a writing question carries no expected answer', () async {
      final id = await begin();
      final answers = await exams.watchAnswers(id).first;
      expect(answers.last.section, 'writing');
      expect(answers.last.expected, isNull);
    });

    test('nothing lands when the questions do not', () async {
      // The attempt and its paper are one thing. An attempt with no questions
      // would resume to a blank exam and the learner could not get the time
      // back. Two questions share an ord, so the second insert violates the
      // primary key.
      await expectLater(
        exams.begin(
          sublevelCode: 'A1.1',
          seed: 1,
          startedAt: '2026-03-04T09:00:00Z',
          questions: const <ExamQuestion>[
            ExamQuestion(ord: 1, section: 'vocabulary', prompt: 'a'),
            ExamQuestion(ord: 1, section: 'vocabulary', prompt: 'b'),
          ],
        ),
        throwsA(isA<Exception>()),
      );

      expect(await db.select(db.examAttempts).get(), isEmpty);
    });

    test('the seed is checked by the database', () async {
      // BR-EXAM-02: three mocks per step, so seed 4 is a bug, not a feature.
      await expectLater(begin(seed: 4), throwsA(isA<Exception>()));
    });
  });

  group('answering', () {
    test('updates the row in place', () async {
      final id = await begin();
      await exams.answer(attemptId: id, ord: 2, given: 'das Haus');

      final answers = await exams.watchAnswers(id).first;
      expect(answers, hasLength(3), reason: 'answering inserted a row');
      expect(answers[1].given, 'das Haus');
    });

    test('grading does not clear a rubric the learner ticked', () async {
      final id = await begin();
      await exams.answer(
        attemptId: id,
        ord: 3,
        given: 'Mein Tag …',
        selfRubricJson: '{"structure":1}',
      );
      await exams.answer(attemptId: id, ord: 3, given: 'Mein Tag …', points: 2);

      final answers = await exams.watchAnswers(id).first;
      expect(answers.last.selfRubricJson, '{"structure":1}');
      expect(answers.last.points, 2);
    });

    test('flagging is separate from answering', () async {
      final id = await begin();
      await exams.answer(attemptId: id, ord: 1, given: 'das Haus');
      await exams.flag(attemptId: id, ord: 1, flagged: true);

      final answers = await exams.watchAnswers(id).first;
      expect(answers.first.flagged, 1);
      expect(answers.first.given, 'das Haus');
    });
  });

  group('resuming', () {
    test('finds the attempt that was left running', () async {
      final id = await begin();
      final found = await exams.resumable('A1.1');
      expect(found!.id, id);
    });

    test('a finished attempt is not offered', () async {
      final id = await begin();
      await exams.finish(
        attemptId: id,
        finishedAt: '2026-03-04T10:00:00Z',
        score: const ExamScore(scorePoints: 30, maxPoints: 48, passed: true),
      );
      expect(await exams.resumable('A1.1'), isNull);
    });

    test('an abandoned attempt is not offered but keeps its answers', () async {
      // FR-L12-04: leaving an exam keeps what was done, so the result screen
      // can still show it.
      final id = await begin();
      await exams.answer(attemptId: id, ord: 1, given: 'das Haus');
      await exams.abandon(id);

      expect(await exams.resumable('A1.1'), isNull);
      final answers = await exams.watchAnswers(id).first;
      expect(answers.first.given, 'das Haus');
    });

    test('another step is another exam', () async {
      await begin();
      expect(await exams.resumable('A1.2'), isNull);
    });

    test('the first unanswered question is where it picks up', () async {
      final id = await begin();
      expect(await exams.nextQuestion(id), 1);

      await exams.answer(attemptId: id, ord: 1, given: 'das Haus');
      expect(await exams.nextQuestion(id), 2);
    });

    test('a gap is found before a later answer', () async {
      // The learner skipped 2 and answered 3. Resume puts them on 2, not 4.
      final id = await begin();
      await exams.answer(attemptId: id, ord: 1, given: 'a');
      await exams.answer(attemptId: id, ord: 3, given: 'c');
      expect(await exams.nextQuestion(id), 2);
    });

    test('a cleared answer counts as unanswered again', () async {
      final id = await begin();
      await exams.answer(attemptId: id, ord: 1, given: 'a');
      await exams.answer(attemptId: id, ord: 1, given: null);
      expect(await exams.nextQuestion(id), 1);
    });

    test('a full paper has no next question', () async {
      final id = await begin();
      for (var ord = 1; ord <= 3; ord++) {
        await exams.answer(attemptId: id, ord: ord, given: 'x');
      }
      expect(await exams.nextQuestion(id), isNull);
    });
  });

  group('the timer', () {
    Future<ExamAttempt> attempt(int id) =>
        (db.select(db.examAttempts)..where((t) => t.id.equals(id))).getSingle();

    test('accumulates running and paused time separately', () async {
      final id = await begin();
      await exams.recordTime(attemptId: id, running: 120);
      await exams.recordTime(attemptId: id, paused: 45);
      await exams.recordTime(attemptId: id, running: 300);

      final row = await attempt(id);
      expect(row.durationSec, 420);
      expect(row.pausedSec, 45);
    });

    test('a pause does not count towards the duration', () async {
      final id = await begin();
      await exams.recordTime(attemptId: id, paused: 600);
      expect((await attempt(id)).durationSec, 0);
    });

    test('one call can record both sides of a pause', () async {
      final id = await begin();
      await exams.recordTime(attemptId: id, running: 60, paused: 10);

      final row = await attempt(id);
      expect(row.durationSec, 60);
      expect(row.pausedSec, 10);
    });

    test('a zero tick is not a write', () async {
      final id = await begin();
      await exams.recordTime(attemptId: id);
      final row = await attempt(id);
      expect(row.durationSec, 0);
      expect(row.pausedSec, 0);
    });

    test('a tick reaches an open stream', () async {
      // A raw statement, so drift only re-emits if it is told to.
      final id = await begin();
      final seen = <int>[];
      final subscription =
          (db.select(db.examAttempts)..where((t) => t.id.equals(id)))
              .watchSingle()
              .listen((row) => seen.add(row.durationSec));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await exams.recordTime(attemptId: id, running: 30);
      await pumpEventQueue();

      expect(seen.last, 30);
    });
  });

  group('the exam hub', () {
    Future<void> sat({
      required int seed,
      required double points,
      required bool passed,
      String code = 'A1.1',
    }) async {
      final id = await begin(code: code, seed: seed);
      await exams.finish(
        attemptId: id,
        finishedAt: '2026-03-04T10:00:00Z',
        score: ExamScore(scorePoints: points, maxPoints: 48, passed: passed),
      );
    }

    test('shows the best score and the attempt count per seed', () async {
      await sat(seed: 1, points: 24, passed: false);
      await sat(seed: 1, points: 36, passed: true);
      await sat(seed: 2, points: 12, passed: false);

      final seeds = await exams.watchSeeds('A1.1').first;
      expect(seeds.map((s) => s.seed), <int>[1, 2]);
      expect(seeds.first.attempts, 2);
      expect(seeds.first.bestPercent, closeTo(75, 0.01));
      expect(seeds.first.everPassed, isTrue);
      expect(seeds.last.attempts, 1);
      expect(seeds.last.everPassed, isFalse);
    });

    test('an unfinished attempt is not a score', () async {
      await begin();
      expect(await exams.watchSeeds('A1.1').first, isEmpty);
    });

    test('an abandoned attempt is not a score either', () async {
      final id = await begin();
      await exams.abandon(id);
      expect(await exams.watchSeeds('A1.1').first, isEmpty);
    });

    test('another step has its own seeds', () async {
      await sat(seed: 1, points: 36, passed: true);
      expect(await exams.watchSeeds('A1.2').first, isEmpty);
    });

    test('the step is passed once any seed has been', () async {
      expect(await exams.watchStepPassed('A1.1').first, isFalse);

      await sat(seed: 1, points: 12, passed: false);
      expect(await exams.watchStepPassed('A1.1').first, isFalse);

      await sat(seed: 3, points: 36, passed: true);
      expect(await exams.watchStepPassed('A1.1').first, isTrue);
    });

    test('a pass on one step does not pass another', () async {
      await sat(seed: 1, points: 36, passed: true);
      expect(await exams.watchStepPassed('A1.2').first, isFalse);
    });

    test('the hub re-emits when an attempt finishes', () async {
      final seen = <int>[];
      final subscription = exams
          .watchSeeds('A1.1')
          .listen((seeds) => seen.add(seeds.length));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(seen.last, 0);

      await sat(seed: 1, points: 36, passed: true);
      await pumpEventQueue();

      expect(seen.last, 1);
    });
  });

  group('quizzes', () {
    Future<int> quiz({int count = 3}) => exams.beginQuiz(
      startedAt: '2026-03-04T09:00:00Z',
      direction: 'deEn',
      source: 'stepLearned',
      sourceRef: 'A1.1',
      seed: 7,
      questions: <QuizQuestion>[
        for (var ord = 1; ord <= count; ord++)
          QuizQuestion(
            ord: ord,
            wordUid: 'uid-$ord',
            prompt: 'Wort $ord',
            expected: 'word $ord',
          ),
      ],
    );

    test('are pre-inserted the same way', () async {
      final id = await quiz();
      final answers = await exams.watchQuizAnswers(id).first;
      expect(answers, hasLength(3));
      expect(answers.every((a) => a.verdict == null), isTrue);
    });

    test('the length is the number of questions, not a claim', () async {
      final id = await quiz(count: 5);
      final attempt = await (db.select(
        db.quizAttempts,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(attempt.length, 5);
    });

    test('an answer records the verdict and the points', () async {
      final id = await quiz();
      await exams.answerQuiz(
        attemptId: id,
        ord: 1,
        given: 'hous',
        verdict: Verdict.almost,
        points: 0.5,
      );

      final answers = await exams.watchQuizAnswers(id).first;
      expect(answers.first.verdict, 'almost');
      expect(answers.first.points, 0.5);
      expect(answers.first.reAsked, 0);
    });

    test('the mistakes are what BR-QUIZ-01 re-asks', () async {
      final id = await quiz();
      await exams.answerQuiz(
        attemptId: id,
        ord: 1,
        given: 'house',
        verdict: Verdict.correct,
        points: 1,
      );
      await exams.answerQuiz(
        attemptId: id,
        ord: 2,
        given: 'der Tür',
        verdict: Verdict.wrongArticle,
        points: 0.5,
      );
      await exams.answerQuiz(
        attemptId: id,
        ord: 3,
        given: '',
        verdict: Verdict.wrong,
        points: 0,
      );

      expect(await exams.mistakeUids(id), <String>['uid-2', 'uid-3']);
    });

    test('an unanswered question is not a mistake', () async {
      final id = await quiz();
      expect(await exams.mistakeUids(id), isEmpty);
    });

    test('a re-asked answer is marked as one', () async {
      final id = await quiz();
      await exams.answerQuiz(
        attemptId: id,
        ord: 2,
        given: 'die Tür',
        verdict: Verdict.correct,
        points: 1,
        reAsked: true,
      );

      final answers = await exams.watchQuizAnswers(id).first;
      expect(answers[1].reAsked, 1);
    });

    test('only finished quizzes show in the history, newest first', () async {
      final first = await quiz();
      final second = await quiz();

      await exams.finishQuiz(
        attemptId: first,
        finishedAt: '2026-03-04T09:10:00Z',
        scorePoints: 8,
        maxPoints: 10,
      );

      expect(await exams.watchRecentQuizzes().first, hasLength(1));

      await exams.finishQuiz(
        attemptId: second,
        finishedAt: '2026-03-05T09:10:00Z',
        scorePoints: 10,
        maxPoints: 10,
      );

      final history = await exams.watchRecentQuizzes().first;
      expect(history.map((row) => row.id), <int>[second, first]);
    });

    test('a verdict the database does not know is refused', () async {
      // The CHECK and the enum have to agree, or a typo would sit in the
      // table until something tried to read it back.
      final id = await quiz();
      await expectLater(
        db.customStatement(
          'UPDATE quiz_answers SET verdict = ? WHERE attempt_id = ? AND ord = 1',
          <Object?>['nearly', id],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('every enum value is one the database accepts', () async {
      final id = await quiz();
      for (final verdict in Verdict.values) {
        await exams.answerQuiz(
          attemptId: id,
          ord: 1,
          given: 'x',
          verdict: verdict,
          points: 0,
        );
        expect(Verdict.parse(verdict.wire), verdict);
      }
    });
  });

  test('deleting an attempt takes its answers with it', () async {
    // ON DELETE CASCADE, which only bites with foreign keys on — the export
    // and the data reset both delete attempts.
    final id = await begin();
    await (db.delete(db.examAttempts)..where((t) => t.id.equals(id))).go();
    expect(await exams.watchAnswers(id).first, isEmpty);
  });
}
