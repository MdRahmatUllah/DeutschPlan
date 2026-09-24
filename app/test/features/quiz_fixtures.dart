import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/quiz_run_service.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/plan_engine.dart' show PlanDate;
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The QuizRunner artboard's run: Standard · DE → EN over A2.1, twenty
/// items. The seventh asks "rental contract, lease" for der Mietvertrag.
Quiz artboardQuiz() => Quiz(
  direction: QuizDirection.deEn,
  source: QuizSource.stepLearned,
  sourceRef: 'A2.1',
  seed: 7,
  items: <QuizItem>[
    for (var ord = 1; ord <= 20; ord++)
      ord == 7
          ? const QuizItem(
              ord: 7,
              wordUid: 'w7',
              direction: QuizDirection.enDe,
              prompt: 'rental contract, lease',
              expected: 'der Mietvertrag',
              hint: 'ভাড়ার চুক্তি',
            )
          : QuizItem(
              ord: ord,
              wordUid: 'w$ord',
              direction: QuizDirection.deEn,
              prompt: 'das Wort$ord',
              expected: 'word $ord',
            ),
  ],
);

/// L8 without a database: [quiz], and a record of what the runner did.
class StubQuizRun implements QuizRunService {
  StubQuizRun({Quiz? quiz, this.error}) : quiz = quiz ?? artboardQuiz();

  final Quiz quiz;

  /// Thrown by [start] while set.
  Object? error;

  /// Each start's direction, source, ref, length and seed.
  final List<(QuizDirection, QuizSource, String?, int, int)> started =
      <(QuizDirection, QuizSource, String?, int, int)>[];

  /// Each answer's ord, what was given and its verdict.
  final List<(int, String, Verdict)> answers = <(int, String, Verdict)>[];

  /// The finish's points; null until then.
  double? finished;

  @override
  Future<QuizRun> start({
    required QuizDirection direction,
    required QuizSource source,
    required int length,
    required int seed,
    required PlanDate today,
    String? sourceRef,
  }) async {
    started.add((direction, source, sourceRef, length, seed));
    if (error case final error?) throw error;
    return QuizRun(quiz: quiz, attemptId: quiz.items.isEmpty ? null : 1);
  }

  @override
  Future<void> answer(
    QuizRun run,
    QuizItem item, {
    required String given,
    required Verdict verdict,
  }) async => answers.add((item.ord, given, verdict));

  @override
  Future<void> finish(QuizRun run, {required double points}) async =>
      finished = points;
}

List<Override> quizStub([StubQuizRun? run]) => <Override>[
  quizRunServiceProvider.overrideWithValue(run ?? StubQuizRun()),
];
