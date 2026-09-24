import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

part 'exam_repository.g.dart';

/// One question of a mock exam, as the generator hands it over.
///
/// Every field but the answer is known before the learner sees the paper,
/// which is what lets the whole set be pre-inserted (FR-L12-01).
@immutable
class ExamQuestion {
  const ExamQuestion({
    required this.ord,
    required this.section,
    required this.prompt,
    this.itemRef,
    this.optionsJson,
    this.expected,
  });

  final int ord;
  final String section;
  final String prompt;

  /// The item's ref (`exam-generator.md`): a word's uid, `<topic uid>#<n>`,
  /// or `writing:` / `speaking:` and a category id. What never repeats across
  /// a step's mocks, and what a result screen links back from.
  final String? itemRef;

  /// Multiple-choice options. Null for a typed question.
  final String? optionsJson;

  /// Null for Writing and Speaking, which are graded by rubric.
  final String? expected;

  /// [item] as row [ord] of its paper (`exam-generator.md`).
  static ExamQuestion of(int ord, ExamItem item) {
    final row = item.encode();
    return ExamQuestion(
      ord: ord,
      section: row.section,
      prompt: row.prompt,
      itemRef: row.ref,
      optionsJson: row.options,
      expected: row.expected,
    );
  }
}

/// One question of a quiz.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.ord,
    required this.wordUid,
    required this.prompt,
    required this.expected,
  });

  final int ord;
  final String wordUid;
  final String prompt;
  final String expected;
}

/// The verdicts `answer_check` produces, matching the CHECK on `quiz_answers`.
enum Verdict {
  correct,
  almost,
  wrongArticle,
  wrong;

  static Verdict? parse(String? value) => switch (value) {
    'correct' => Verdict.correct,
    'almost' => Verdict.almost,
    'wrongArticle' => Verdict.wrongArticle,
    'wrong' => Verdict.wrong,
    _ => null,
  };

  String get wire => name;
}

/// What an exam attempt ended up being worth.
/// A finished quiz as L2's last quiz card shows it. A record rather than
/// drift's row, so a provider can return it.
typedef LastQuiz = ({
  int score,
  int outOf,
  int length,
  String direction,
  String finishedAt,
});

@immutable
class ExamScore {
  const ExamScore({
    required this.scorePoints,
    required this.maxPoints,
    required this.passed,
  });

  final double scorePoints;
  final double maxPoints;
  final bool passed;
}

/// One seed's line in the exam hub.
@immutable
class SeedSummary {
  const SeedSummary({
    required this.seed,
    required this.attempts,
    required this.finished,
    required this.bestPercent,
    required this.everPassed,
  });

  final int seed;

  /// Every attempt that is no longer running, abandoned ones included:
  /// FR-L12-04 shows one as an attempt without a score, and BR-EXAM-02's
  /// *Try another mock* must not offer a seed the learner walked out of as
  /// though it had never been sat.
  final int attempts;

  /// How many of those were graded. [bestPercent] and [everPassed] come from
  /// these only (FR-L10-02), so `finished == 0` is the card that reads
  /// "1 attempt · no score".
  final int finished;

  final double bestPercent;
  final bool everPassed;
}

/// Mock exams and quizzes, written per question.
///
/// The shape follows FR-L12-01: an attempt is created with every answer row
/// already there, and answering updates a row in place. A crash then loses at
/// most the answer being typed, and resuming is a query rather than a replay.
///
/// The clock lives with the caller, not here. The exam screen already runs a
/// ticker for the countdown, and a repository that owned a second clock would
/// have two that could disagree — so [recordTime] takes elapsed seconds and
/// adds them.
@DriftAccessor(include: <String>{'../db/exam_queries.drift'})
class ExamRepository extends DatabaseAccessor<AppDatabase>
    with _$ExamRepositoryMixin {
  ExamRepository(super.db);

  /// Creates the attempt and every answer row, together.
  ///
  /// One transaction: an attempt whose questions did not land would resume to
  /// a blank paper, and the learner would have no way to get their time back.
  Future<int> begin({
    required String sublevelCode,
    required int seed,
    required String startedAt,
    required List<ExamQuestion> questions,
  }) => db.transaction(() async {
    // A crash mid-exam, or a double-tap on *Begin exam*, leaves an attempt
    // nothing ever finishes or abandons. It would sit `in_progress` for good
    // and be counted twice by the hub, so starting this seed again closes it
    // out — which is what FR-L12-04 calls an unfinished attempt anyway.
    await (update(db.examAttempts)..where(
          (t) =>
              t.sublevelCode.equals(sublevelCode) &
              t.seed.equals(seed) &
              t.status.equals('in_progress'),
        ))
        .write(const ExamAttemptsCompanion(status: Value('abandoned')));

    final id = await into(db.examAttempts).insert(
      ExamAttemptsCompanion.insert(
        sublevelCode: sublevelCode,
        seed: seed,
        startedAt: startedAt,
      ),
    );

    await batch((batch) {
      batch.insertAll(db.examAnswers, <ExamAnswersCompanion>[
        for (final question in questions)
          ExamAnswersCompanion.insert(
            attemptId: id,
            ord: question.ord,
            section: question.section,
            prompt: question.prompt,
            itemRef: Value(question.itemRef),
            optionsJson: Value(question.optionsJson),
            expected: Value(question.expected),
          ),
      ]);
    });

    return id;
  });

  /// What [step]'s three mocks are drawn from (#83): its words but the
  /// suspended ones, with their examples and categories, its grammar topics,
  /// and the connectors the writing check counts.
  Future<ExamPool> pool(String step) async {
    final examples = <String, List<({String german, String english})>>{};
    for (final row in await examExamples(step).get()) {
      (examples[row.uid] ??= <({String german, String english})>[]).add((
        german: row.german,
        english: row.english ?? '',
      ));
    }
    return ExamPool(
      step: step,
      level: step.split('.').first,
      words: <ExamWord>[
        for (final row in await examWords(step).get())
          ExamWord(
            word: QuizWord(
              uid: row.uid,
              german: row.german,
              english: row.english,
              step: step,
              article: row.article,
              pos: row.pos,
              bangla: row.bangla,
              forms: row.forms,
              synonyms: row.synonyms,
            ),
            category: row.categoryId,
            examples: examples[row.uid] ?? const [],
          ),
      ],
      topics: <GrammarSource>[
        for (final topic in await examTopics(step).get())
          GrammarSource(
            uid: topic.uid,
            topic: topic.topic,
            rule: topic.rule ?? '',
            exampleDe: topic.exampleDe ?? '',
            exampleEn: topic.exampleEn ?? '',
            watchOut: topic.watchOut ?? '',
            tags: topic.tags.split(','),
            levelCode: topic.levelCode,
          ),
      ],
      categories: <int, String>{
        for (final row in await examCategories(step).get()) row.id: row.name,
      },
      connectors: <String>[
        for (final row in await examConnectors(step).get()) row,
      ],
    );
  }

  /// The refs of every paper sat for [step], by seed: `buildExam`'s `sat`,
  /// so a new mock shares nothing with one already stored (BR-EXAM-02).
  Future<Map<int, Set<String>>> satRefs(String step) async {
    final refs = <int, Set<String>>{};
    for (final row in await examSatRefs(step).get()) {
      (refs[row.seed] ??= <String>{}).add(row.ref!);
    }
    return refs;
  }

  /// The paper [seed] of [step] was sat with, to sit again: a retake is the
  /// same mock, whatever has changed in the course since. Null before the
  /// seed has been sat.
  Future<List<ExamQuestion>?> storedPaper(String step, int seed) async {
    final attempt = await latestAttempt(step, seed).getSingleOrNull();
    if (attempt == null) return null;
    return <ExamQuestion>[
      for (final row in await answersFor(attempt.id).get())
        ExamQuestion(
          ord: row.ord,
          section: row.section,
          prompt: row.prompt,
          itemRef: row.itemRef,
          optionsJson: row.optionsJson,
          expected: row.expected,
        ),
    ];
  }

  /// Writes one answer in place. Called as the learner moves on, not on submit.
  ///
  /// [points] and [selfRubricJson] are absent rather than null when not given,
  /// so grading can write the points without clearing a rubric the learner
  /// already ticked.
  Future<void> answer({
    required int attemptId,
    required int ord,
    required String? given,
    double? points,
    String? selfRubricJson,
  }) =>
      (update(
        db.examAnswers,
      )..where((t) => t.attemptId.equals(attemptId) & t.ord.equals(ord))).write(
        ExamAnswersCompanion(
          given: Value(given),
          points: points == null ? const Value.absent() : Value(points),
          selfRubricJson: selfRubricJson == null
              ? const Value.absent()
              : Value(selfRubricJson),
        ),
      );

  Future<void> flag({
    required int attemptId,
    required int ord,
    required bool flagged,
  }) =>
      (update(db.examAnswers)
            ..where((t) => t.attemptId.equals(attemptId) & t.ord.equals(ord)))
          .write(ExamAnswersCompanion(flagged: Value(flagged ? 1 : 0)));

  /// Whether that attempt is in the table at all.
  ///
  /// The router's guard reads this: FR-L12-01 resumes an exam from its id
  /// alone, so a deep link or a restored process carries nothing else — and
  /// an id for an attempt that was never created, or that a data reset wiped,
  /// would open a runner with no questions in it.
  Future<bool> exists(int attemptId) async {
    final row = await (select(
      db.examAttempts,
    )..where((t) => t.id.equals(attemptId))).getSingleOrNull();
    return row != null;
  }

  /// The attempt to offer *Continue* on, or null. Today's *Resume* card.
  Future<ExamAttempt?> resumable(String sublevelCode) =>
      inProgressExam(sublevelCode).getSingleOrNull();

  /// The same, per seed, for the hub's three cards (FR-L10-02): a seed with an
  /// entry shows *Resume* instead of *Start*.
  Stream<Map<int, ExamAttempt>> watchResumable(String sublevelCode) =>
      inProgressBySeed(sublevelCode).watch().map(
        // At most one row per seed: `begin` abandons the one it replaces.
        (rows) => <int, ExamAttempt>{for (final row in rows) row.seed: row},
      );

  /// The question to put the learner back on, or null when the paper is full.
  ///
  /// Read from the answers rather than from a stored cursor: the answers are
  /// the record, and a cursor could disagree with them. A question answered
  /// and then cleared counts as unanswered again, which is what clearing it
  /// means.
  Future<int?> nextQuestion(int attemptId) =>
      firstUnanswered(attemptId).getSingle();

  Stream<List<ExamAnswer>> watchAnswers(int attemptId) =>
      answersFor(attemptId).watch();

  /// Adds elapsed seconds. `duration_sec` counts only while the timer runs.
  ///
  /// One statement rather than read-then-write: a tick landing while the
  /// submit is grading would otherwise read the old total and lose the other.
  Future<void> recordTime({
    required int attemptId,
    int running = 0,
    int paused = 0,
  }) async {
    if (running == 0 && paused == 0) return;
    await db.customStatement(
      'UPDATE exam_attempts SET duration_sec = duration_sec + ?, '
      'paused_sec = paused_sec + ? WHERE id = ?',
      <Object?>[running, paused, attemptId],
    );
    // A raw statement, so drift has to be told which streams to re-emit.
    db.markTablesUpdated(<TableInfo<Table, Object?>>{db.examAttempts});
  }

  Future<void> finish({
    required int attemptId,
    required String finishedAt,
    required ExamScore score,
  }) => (update(db.examAttempts)..where((t) => t.id.equals(attemptId))).write(
    ExamAttemptsCompanion(
      finishedAt: Value(finishedAt),
      scorePoints: Value(score.scorePoints),
      maxPoints: Value(score.maxPoints),
      passed: Value(score.passed ? 1 : 0),
      status: const Value('finished'),
    ),
  );

  /// Grades [attemptId] as its answers stand (#84): each row's points, and
  /// the attempt's score, out of the paper's points, passed at
  /// [passPercent] (`exam_pass_percent`, BR-EXAM-04). With [finishedAt] it
  /// is the submit that finishes the attempt; without, L13's re-grade after
  /// a rubric tick (FR-L13-03). One transaction: a score never disagrees
  /// with the rows it adds up.
  Future<ExamScore> grade(
    int attemptId, {
    required int passPercent,
    String? finishedAt,
  }) => db.transaction(() async {
    final rows = await answersFor(attemptId).get();
    final paper = scorePaper(<({ExamItem item, String? given, String? rubric})>[
      for (final row in rows)
        (
          item: ExamItem.decode((
            section: row.section,
            ref: row.itemRef,
            prompt: row.prompt,
            options: row.optionsJson,
            expected: row.expected,
          )),
          given: row.given,
          rubric: row.selfRubricJson,
        ),
    ], passPercent: passPercent);
    for (final (i, row) in rows.indexed) {
      await (update(db.examAnswers)..where(
            (t) => t.attemptId.equals(attemptId) & t.ord.equals(row.ord),
          ))
          .write(ExamAnswersCompanion(points: Value(paper.points[i])));
    }
    final score = ExamScore(
      scorePoints: paper.total,
      maxPoints: paper.max,
      passed: paper.passed,
    );
    await (update(db.examAttempts)..where((t) => t.id.equals(attemptId))).write(
      ExamAttemptsCompanion(
        scorePoints: Value(score.scorePoints),
        maxPoints: Value(score.maxPoints),
        passed: Value(score.passed ? 1 : 0),
        finishedAt: finishedAt == null
            ? const Value.absent()
            : Value(finishedAt),
        status: finishedAt == null
            ? const Value.absent()
            : const Value('finished'),
      ),
    );
    return score;
  });

  /// Leaving an exam. FR-L12-04: the answers stay, so the result screen can
  /// still show what was done.
  Future<void> abandon(int attemptId) =>
      (update(db.examAttempts)..where((t) => t.id.equals(attemptId))).write(
        const ExamAttemptsCompanion(status: Value('abandoned')),
      );

  /// One line per seed that has been sat, for the exam hub.
  Stream<List<SeedSummary>> watchSeeds(String sublevelCode) =>
      examSeedSummary(sublevelCode).watch().map(
        (rows) => <SeedSummary>[
          for (final row in rows)
            SeedSummary(
              seed: row.seed,
              attempts: row.attempts,
              finished: row.finished ?? 0,
              bestPercent: row.bestPercent ?? 0,
              everPassed: row.everPassed == 1,
            ),
        ],
      );

  /// Whether the step counts as passed. A query, not a flag: a flag would have
  /// to be kept in step with attempts a data reset can delete.
  Stream<bool> watchStepPassed(String sublevelCode) =>
      stepPassed(sublevelCode).watchSingle();

  // --- Quizzes --------------------------------------------------------------

  Future<int> beginQuiz({
    required String startedAt,
    required String direction,
    required String source,
    required int seed,
    required List<QuizQuestion> questions,
    String? sourceRef,
  }) => db.transaction(() async {
    final id = await into(db.quizAttempts).insert(
      QuizAttemptsCompanion.insert(
        startedAt: startedAt,
        direction: direction,
        source: source,
        sourceRef: Value(sourceRef),
        seed: seed,
        length: questions.length,
      ),
    );

    await batch((batch) {
      batch.insertAll(db.quizAnswers, <QuizAnswersCompanion>[
        for (final question in questions)
          QuizAnswersCompanion.insert(
            attemptId: id,
            ord: question.ord,
            wordUid: question.wordUid,
            prompt: question.prompt,
            expected: question.expected,
          ),
      ]);
    });

    return id;
  });

  /// Records one quiz answer.
  ///
  /// [reAsked] is BR-QUIZ-01's second pass: a wrong item comes back at the end,
  /// and the flag is what keeps the result screen from counting it twice.
  Future<void> answerQuiz({
    required int attemptId,
    required int ord,
    required String given,
    required Verdict verdict,
    required double points,
    bool reAsked = false,
  }) =>
      (update(
        db.quizAnswers,
      )..where((t) => t.attemptId.equals(attemptId) & t.ord.equals(ord))).write(
        QuizAnswersCompanion(
          given: Value(given),
          verdict: Value(verdict.wire),
          points: Value(points),
          reAsked: Value(reAsked ? 1 : 0),
        ),
      );

  Future<void> finishQuiz({
    required int attemptId,
    required String finishedAt,
    required double scorePoints,
    required double maxPoints,
  }) => (update(db.quizAttempts)..where((t) => t.id.equals(attemptId))).write(
    QuizAttemptsCompanion(
      finishedAt: Value(finishedAt),
      scorePoints: Value(scorePoints),
      maxPoints: Value(maxPoints),
    ),
  );

  Stream<List<QuizAnswer>> watchQuizAnswers(int attemptId) =>
      quizAnswersFor(attemptId).watch();

  /// The uids *Retry mistakes* builds a new quiz from.
  Future<List<String>> mistakeUids(int attemptId) async {
    final rows = await quizMistakes(attemptId).get();
    return <String>[for (final row in rows) row.wordUid];
  }

  Stream<List<QuizAttempt>> watchRecentQuizzes({int limit = 10}) =>
      recentQuizzes(limit).watch();

  /// L2's "Last quiz · 16 / 20 · Standard · DE → EN · Sun 20 Sep": the
  /// step's latest finished quiz, or null before the first.
  Stream<LastQuiz?> watchLastStepQuiz(String code) =>
      lastStepQuiz(code).watch().map(
        (rows) => rows.isEmpty
            ? null
            : (
                score: rows.single.scorePoints.round(),
                outOf: rows.single.maxPoints.round(),
                length: rows.single.length,
                direction: rows.single.direction,
                finishedAt: rows.single.finishedAt!,
              ),
      );
}
