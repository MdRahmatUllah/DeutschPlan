import 'package:deutschplan/data/repositories/exam_repository.dart' as exam;
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show ReviewSource;
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart' show PlanDate, addDays;
import 'package:deutschplan/domain/quiz_builder.dart';

/// A started quiz: its items and the `quiz_attempts` row recording them —
/// null for a quiz with nothing in it, which records nothing.
class QuizRun {
  const QuizRun({required this.quiz, required this.attemptId});

  final Quiz quiz;
  final int? attemptId;
}

/// L8's data (`quiz.md`, #123): builds the quiz, records it and each answer
/// as it is given, and finishes it. The runner talks to this and nothing
/// else, so a test or a golden can hand it a quiz without a database.
class QuizRunService {
  QuizRunService(
    this._builder,
    this._exams,
    this._rating,
    this._words,
    this._now,
  );

  final QuizBuilder _builder;
  final exam.ExamRepository _exams;
  final RatingService _rating;
  final WordRepository _words;
  final DateTime Function() _now;

  /// FR-L8-01: built by `QuizBuilder`, the seed stored in `quiz_attempts`,
  /// so the attempt can be rebuilt.
  Future<QuizRun> start({
    required QuizDirection direction,
    required QuizSource source,
    required int length,
    required int seed,
    required PlanDate today,
    String? sourceRef,
  }) async {
    final quiz = await _builder.build(
      direction: direction,
      source: source,
      sourceRef: sourceRef,
      length: length,
      seed: seed,
      today: today,
    );
    if (quiz.items.isEmpty) return QuizRun(quiz: quiz, attemptId: null);
    final id = await _exams.beginQuiz(
      startedAt: _now().toUtc().toIso8601String(),
      direction: direction.name,
      source: source.name,
      sourceRef: sourceRef,
      seed: seed,
      questions: <exam.QuizQuestion>[
        for (final item in quiz.items)
          exam.QuizQuestion(
            ord: item.ord,
            wordUid: item.wordUid,
            prompt: item.prompt,
            expected: item.expected,
          ),
      ],
    );
    return QuizRun(quiz: quiz, attemptId: id);
  }

  /// One answer, persisted as it is given — a quiz left half way keeps what
  /// was answered (FR-L8-04) — and rated into FSRS (FR-L8-02).
  Future<void> answer(
    QuizRun run,
    QuizItem item, {
    required String given,
    required Verdict verdict,
  }) async {
    await _exams.answerQuiz(
      attemptId: run.attemptId!,
      ord: item.ord,
      given: given,
      verdict: exam.Verdict.parse(verdict.name)!,
      points: verdict.score,
    );
    await _rating.rate(
      item.wordUid,
      ratingFor(verdict),
      source: ReviewSource.quiz,
    );
  }

  /// FR-L8-03: [item] was asked again at the end. Its first answer stands:
  /// a re-ask changes neither the score nor FSRS, which the first answer
  /// already rated.
  Future<void> reasked(QuizRun run, QuizItem item) =>
      _exams.markQuizReAsked(attemptId: run.attemptId!, ord: item.ord);

  /// L9 (#126): the finished run and its mistakes.
  Future<exam.QuizResult?> result(int attemptId) =>
      _exams.quizResult(attemptId);

  /// FR-L9-01 *Add mistakes to revision*: every mistake rated Again
  /// (BR-FSRS-03), then due tomorrow, explicitly. A wrong answer was rated
  /// Again as it was given; an almost was rated Hard, so it is rated Again
  /// now, and FSRS, `review_log` and its status agree.
  Future<void> addToRevision(
    List<({String uid, String? verdict})> mistakes, {
    required PlanDate today,
  }) async {
    for (final m in mistakes) {
      if (m.verdict == Verdict.almost.name) {
        await _rating.rate(m.uid, Rating.again, source: ReviewSource.quiz);
      }
    }
    await _words.dueOn(<String>[
      for (final m in mistakes) m.uid,
    ], addDays(today, 1));
  }

  /// The run is over: its score out of one point an item (BR-ANS-04).
  Future<void> finish(QuizRun run, {required double points}) =>
      _exams.finishQuiz(
        attemptId: run.attemptId!,
        finishedAt: _now().toUtc().toIso8601String(),
        scorePoints: points,
        maxPoints: run.quiz.items.length.toDouble(),
      );
}

/// BR-FSRS-03: correct → Good, almost → Hard, anything else → Again.
Rating ratingFor(Verdict verdict) => switch (verdict) {
  Verdict.correct => Rating.good,
  Verdict.almost => Rating.hard,
  Verdict.wrongArticle || Verdict.wrong => Rating.again,
};
