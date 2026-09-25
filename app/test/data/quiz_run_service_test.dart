@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart'
    show ExamRepository, QuizQuestion;
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/quiz_run_service.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/quiz_store.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// L8's data over a real database (#123): the attempt, each answer as it is
/// given, and the finish.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late ExamRepository exams;
  late QuizRunService service;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_quiz_run');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    exams = ExamRepository(db);
    DateTime now() => DateTime.utc(2026, 9, 21, 19);
    final words = WordRepository(db, settings);
    service = QuizRunService(
      QuizBuilder(DriftQuizStore(words, settings, ContentDao(db))),
      exams,
      RatingService(db, settings, PlanRepository(db), words, now),
      words,
      now,
    );
    for (final uid in <String>[ContentFixture.haus, ContentFixture.strasse]) {
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: uid,
              status: const Value('learning'),
              stability: const Value(3),
              reps: const Value(2),
              lastReview: const Value('2026-09-10T21:30:00Z'),
            ),
          );
    }
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  Future<QuizRun> start({int seed = 42}) => service.start(
    direction: QuizDirection.enDe,
    source: QuizSource.allLearned,
    length: 10,
    seed: seed,
    today: '2026-09-21',
  );

  test('FR-L8-01 the attempt stores its seed and every question', () async {
    final run = await start();
    final attempt = await (db.select(
      db.quizAttempts,
    )..where((a) => a.id.equals(run.attemptId!))).getSingle();
    expect(
      (attempt.seed, attempt.direction, attempt.source, attempt.length),
      (42, 'enDe', 'allLearned', 2),
    );
    final answers = await exams.watchQuizAnswers(run.attemptId!).first;
    expect(
      [for (final a in answers) (a.ord, a.wordUid, a.expected)],
      [for (final i in run.quiz.items) (i.ord, i.wordUid, i.expected)],
    );
  });

  test('FR-L8-01 the stored seed rebuilds the same quiz', () async {
    final run = await start(seed: 9);
    final again = await start(seed: 9);
    expect(
      [for (final i in again.quiz.items) (i.wordUid, i.prompt)],
      [for (final i in run.quiz.items) (i.wordUid, i.prompt)],
    );
  });

  test('answers are persisted per item, as they are given', () async {
    final run = await start();
    final first = run.quiz.items.first;
    await service.answer(run, first, given: 'x', verdict: Verdict.wrong);
    await service.answer(
      run,
      run.quiz.items[1],
      given: 'die Straße',
      verdict: Verdict.almost,
    );
    final answers = await exams.watchQuizAnswers(run.attemptId!).first;
    expect(
      [for (final a in answers) (a.ord, a.given, a.verdict, a.points)],
      [(1, 'x', 'wrong', 0.0), (2, 'die Straße', 'almost', 0.5)],
    );
  });

  test('FR-L8-02 BR-FSRS-03 each answer is rated, source quiz', () async {
    final run = await start();
    final (first, second) = (run.quiz.items[0], run.quiz.items[1]);
    await service.answer(run, first, given: 'x', verdict: Verdict.wrong);
    await service.answer(run, second, given: 'y', verdict: Verdict.almost);
    final log = await (db.select(
      db.reviewLog,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    expect(
      [for (final r in log) (r.wordUid, r.rating, r.source)],
      [
        (first.wordUid, Rating.again.value, 'quiz'),
        (second.wordUid, Rating.hard.value, 'quiz'),
      ],
    );
  });

  test('BR-FSRS-03 the rating for each verdict', () {
    expect(ratingFor(Verdict.correct), Rating.good);
    expect(ratingFor(Verdict.almost), Rating.hard);
    expect(ratingFor(Verdict.wrongArticle), Rating.again);
    expect(ratingFor(Verdict.wrong), Rating.again);
  });

  test('FR-L8-03 a re-ask is marked, and the first answer stands', () async {
    final run = await start();
    final first = run.quiz.items.first;
    await service.answer(run, first, given: 'x', verdict: Verdict.wrong);
    await service.reasked(run, first);
    final row = (await exams.watchQuizAnswers(run.attemptId!).first).first;
    expect(
      (row.given, row.verdict, row.points, row.reAsked),
      ('x', 'wrong', 0.0, 1),
    );
    final ratings = await db.select(db.reviewLog).get();
    expect(ratings, hasLength(1), reason: 'the re-ask is not rated again');
  });

  test('BR-ANS-04 the finish scores out of one point an item', () async {
    final run = await start();
    await service.finish(run, points: 1.5);
    final attempt = await (db.select(
      db.quizAttempts,
    )..where((a) => a.id.equals(run.attemptId!))).getSingle();
    expect(
      (attempt.finishedAt, attempt.scorePoints, attempt.maxPoints),
      ('2026-09-21T19:00:00.000Z', 1.5, 2.0),
    );
  });

  test('FR-L9-01 the result: the attempt and its mistakes, as the course '
      'writes them', () async {
    final run = await start();
    final (first, second) = (run.quiz.items[0], run.quiz.items[1]);
    await service.answer(run, first, given: 'x', verdict: Verdict.almost);
    await service.answer(
      run,
      second,
      given: second.expected,
      verdict: Verdict.correct,
    );
    await service.finish(run, points: 1.5);

    final result = (await service.result(run.attemptId!))!;
    expect((result.attempt.scorePoints, result.attempt.maxPoints), (1.5, 2.0));
    final words = <String, (String, String)>{
      ContentFixture.haus: ('Haus', 'das'),
      ContentFixture.strasse: ('Straße', 'die'),
    };
    expect(
      [
        for (final m in result.mistakes)
          (m.uid, m.given, m.verdict, (m.german!, m.article!)),
      ],
      [(first.wordUid, 'x', 'almost', words[first.wordUid])],
      reason: 'only what was not right',
    );
  });

  test('an unknown attempt has no result', () async {
    expect(await service.result(99), isNull);
  });

  test('FR-L9-01 BR-FSRS-03 Add mistakes to revision: an almost rated '
      'Again, a wrong not twice, both due tomorrow, those only', () async {
    Future<String?> due(String uid) async => (await (db.select(
      db.wordState,
    )..where((s) => s.wordUid.equals(uid))).getSingle()).due;
    final before = await due(ContentFixture.strasse);

    await service.addToRevision(<({String uid, String? verdict})>[
      (uid: ContentFixture.haus, verdict: 'almost'),
      (uid: 'uid-not-learned', verdict: 'wrong'),
    ], today: '2026-09-21');

    expect(await due(ContentFixture.haus), '2026-09-22');
    expect(await due(ContentFixture.strasse), before, reason: 'not a mistake');
    final log = await db.select(db.reviewLog).get();
    expect(
      [for (final r in log) (r.wordUid, r.rating, r.source)],
      [(ContentFixture.haus, Rating.again.value, 'quiz')],
      reason: 'the almost is rated Again; the wrong already was',
    );
  });

  test('a source with nothing learned records nothing', () async {
    final run = await service.start(
      direction: QuizDirection.deEn,
      source: QuizSource.stepLearned,
      sourceRef: 'B2.2',
      length: 10,
      seed: 1,
      today: '2026-09-21',
    );
    expect(run.quiz.items, isEmpty);
    expect(run.attemptId, isNull);
    expect(await db.select(db.quizAttempts).get(), isEmpty);
  });

  test('FR-W2-03 BR-QUIZ-01 a compare answer rates only a word being '
      'learned; every answer is recorded', () async {
    // Straße is suspended; Tür was never started; Haus is learning.
    await (db.update(db.wordState)
          ..where((s) => s.wordUid.equals(ContentFixture.strasse)))
        .write(const WordStateCompanion(status: Value('suspended')));
    final uids = <String>[
      ContentFixture.tuer,
      ContentFixture.strasse,
      ContentFixture.haus,
    ];
    QuizItem item(int ord) => QuizItem(
      ord: ord,
      wordUid: uids[ord - 1],
      direction: QuizDirection.compare,
      prompt: 'Das ___ ist hier.',
      expected: 'x',
      options: const <String>['x', 'y'],
    );
    final id = await exams.beginQuiz(
      startedAt: '2026-09-21T19:00:00Z',
      direction: 'compare',
      source: 'compareSet',
      sourceRef: 'set',
      seed: 1,
      questions: <QuizQuestion>[
        for (var ord = 1; ord <= 3; ord++)
          QuizQuestion(
            ord: ord,
            wordUid: uids[ord - 1],
            prompt: 'Das ___ ist hier.',
            expected: 'x',
          ),
      ],
    );
    final run = QuizRun(
      quiz: Quiz(
        direction: QuizDirection.compare,
        source: QuizSource.compareSet,
        seed: 1,
        items: <QuizItem>[item(1), item(2), item(3)],
      ),
      attemptId: id,
    );
    final before = await (db.select(
      db.wordState,
    )..where((s) => s.wordUid.equals(ContentFixture.strasse))).getSingle();

    for (final ord in <int>[1, 2, 3]) {
      await service.answer(
        run,
        item(ord),
        given: 'x',
        verdict: Verdict.correct,
      );
    }

    final log = await db.select(db.reviewLog).get();
    expect([for (final r in log) r.wordUid], [ContentFixture.haus]);
    expect(
      await (db.select(
        db.wordState,
      )..where((s) => s.wordUid.equals(ContentFixture.tuer))).getSingleOrNull(),
      isNull,
      reason: 'a To-do word is not started by a quiz',
    );
    final after = await (db.select(
      db.wordState,
    )..where((s) => s.wordUid.equals(ContentFixture.strasse))).getSingle();
    expect((after.due, after.reps), (before.due, before.reps));
    final answers = await exams.watchQuizAnswers(id).first;
    expect([for (final a in answers) a.verdict], everyElement('correct'));
  });
}
