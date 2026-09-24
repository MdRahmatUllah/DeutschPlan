import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart' show QuizAttempt;
import 'package:deutschplan/data/repositories/exam_repository.dart'
    show QuizMistakeRowsResult, QuizResult;
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

/// The QuizResult artboard: 16 / 20 in 4 min 12 s, Standard · DE → EN, and
/// its four mistakes — three typos and a wrong article.
QuizResult artboardResult({int id = 1}) => (
  attempt: QuizAttempt(
    id: id,
    startedAt: '2026-09-21T19:00:00.000Z',
    finishedAt: '2026-09-21T19:04:12.000Z',
    direction: 'deEn',
    source: 'stepLearned',
    sourceRef: 'A2.1',
    seed: 7,
    length: 20,
    scorePoints: 16,
    maxPoints: 20,
  ),
  mistakes: <QuizMistakeRowsResult>[
    for (final (ord, uid, given, verdict, german, article)
        in <(int, String, String, String, String, String?)>[
          (3, 'kaution', 'die Kausion', 'almost', 'Kaution', 'die'),
          (8, 'umziehen', 'umzihen', 'almost', 'umziehen', null),
          (
            11,
            'vermieter',
            'die Vermieter',
            'wrongArticle',
            'Vermieter',
            'der',
          ),
          (17, 'nebenkosten', 'die Nebenkoste', 'almost', 'Nebenkosten', 'die'),
        ])
      QuizMistakeRowsResult(
        ord: ord,
        uid: uid,
        given: given,
        verdict: verdict,
        expected: article == null ? german : '$article $german',
        german: german,
        article: article,
      ),
  ],
);

/// L8 without a database: [quiz], and a record of what the runner did.
class StubQuizRun implements QuizRunService {
  StubQuizRun({Quiz? quiz, this.error, QuizResult? outcome})
    : quiz = quiz ?? artboardQuiz(),
      outcome = outcome ?? artboardResult();

  final Quiz quiz;

  /// Thrown by [start] while set.
  Object? error;

  /// Each start's direction, source, ref, length and seed.
  final List<(QuizDirection, QuizSource, String?, int, int)> started =
      <(QuizDirection, QuizSource, String?, int, int)>[];

  /// Each answer's ord, what was given and its verdict.
  final List<(int, String, Verdict)> answers = <(int, String, Verdict)>[];

  /// The ords asked again at the end (FR-L8-03).
  final List<int> again = <int>[];

  /// The finish's points; null until then.
  double? finished;

  /// What L9 reads back (#126).
  final QuizResult? outcome;

  /// Each *Add mistakes to revision*: its uids and the day it was asked.
  final List<(List<String>, String)> added = <(List<String>, String)>[];

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
  Future<void> reasked(QuizRun run, QuizItem item) async => again.add(item.ord);

  @override
  Future<void> finish(QuizRun run, {required double points}) async =>
      finished = points;

  @override
  Future<QuizResult?> result(int attemptId) async => outcome;

  @override
  Future<void> addToRevision(
    List<String> uids, {
    required PlanDate today,
  }) async => added.add((uids, today));
}

List<Override> quizStub([StubQuizRun? run]) => <Override>[
  quizRunServiceProvider.overrideWithValue(run ?? StubQuizRun()),
];
