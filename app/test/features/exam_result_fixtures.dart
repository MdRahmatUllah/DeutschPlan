import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/plan_engine.dart' show PlanDate;
import 'package:flutter_riverpod/misc.dart' show Override;

import 'exam_run_fixtures.dart';

/// Points per section as the ExamResults artboard adds up: 37 of 48, with
/// nine words missed (the word sections' misses).
const Map<ExamSection, double> artboardSectionPoints = <ExamSection, double>{
  ExamSection.vocabulary: 8,
  ExamSection.reverse: 6,
  ExamSection.articles: 5,
  ExamSection.wordForms: 3,
  ExamSection.gapFill: 4,
  ExamSection.grammar: 4,
  ExamSection.listening: 1,
  ExamSection.writing: 3,
  ExamSection.speaking: 3,
};

/// The artboard's attempt: A1.2, Mock 2, 18:41, 37 of 48, passed.
ExamAttempt resultAttempt({
  int id = 7,
  double score = 37,
  bool passed = true,
  String finishedAt = '2026-09-21T19:19:00.000Z',
}) => ExamAttempt(
  id: id,
  sublevelCode: 'A1.2',
  seed: 2,
  startedAt: '2026-09-21T19:00:00.000Z',
  finishedAt: finishedAt,
  pausedSec: 0,
  durationSec: 18 * 60 + 41,
  scorePoints: score,
  maxPoints: 48,
  passed: passed ? 1 : 0,
  status: 'finished',
);

/// The artboard's paper, graded: each section's first items right until its
/// points are spent; the tasks at their points, Speaking with three ticks.
List<ExamResultRow> artboardRows() {
  final left = Map<ExamSection, double>.of(artboardSectionPoints);
  return <ExamResultRow>[
    for (final (i, item) in artboardPaper().indexed)
      () {
        final section = item.section;
        final points = item is WritingTask || item is SpeakingTask
            ? left[section]!
            : (left[section]! >= 1 ? 1.0 : 0.0);
        left[section] = left[section]! - points;
        return (
          ord: i + 1,
          item: item,
          given: 'x',
          points: points,
          rubric: item is SpeakingTask
              ? const <bool>[true, true, true, false]
              : item is WritingTask
              ? const <bool>[false, false]
              : const <bool>[],
          // The artboard's three flags: Q3, Q12 and Q21.
          flagged: i == 2 || i == 11 || i == 20,
        );
      }(),
  ];
}

/// L13 without a database: [result] as given, and what the screen asked.
class StubExamResult implements ExamResultService {
  StubExamResult({ExamResult? result, this.missing = false})
    : result0 =
          result ??
          (
            attempt: resultAttempt(),
            rows: artboardRows(),
            previous: (
              attempt: resultAttempt(
                id: 3,
                score: 30,
                finishedAt: '2026-09-14T19:00:00Z',
              ),
              number: 1,
            ),
            passPercent: 60,
            missed: missedWords(artboardRows()),
          );

  ExamResult result0;
  final bool missing;

  /// Each rubric written: its ord and ticks.
  final List<(int, List<bool>)> rubrics = <(int, List<bool>)>[];

  /// The uids *Add missed words to revision* sent, and for which day.
  final List<(List<String>, PlanDate)> added = <(List<String>, PlanDate)>[];

  /// Each recording deleted: its ord.
  final List<int> deleted = <int>[];

  /// Makes *Add missed words to revision* throw.
  bool failAdd = false;

  @override
  Future<ExamResult?> result(int attemptId) async => missing ? null : result0;

  @override
  Future<void> rubric(int attemptId, int ord, List<bool> ticks) async {
    rubrics.add((ord, ticks));
    // Graded again as the repository would: half a point a Writing tick.
    final rows = <ExamResultRow>[
      for (final row in result0.rows)
        row.ord == ord
            ? (
                ord: row.ord,
                item: row.item,
                given: row.given,
                points:
                    row.points +
                    0.5 *
                        (ticks.where((t) => t).length -
                            row.rubric.where((t) => t).length),
                rubric: ticks,
                flagged: row.flagged,
              )
            : row,
    ];
    final score = rows.fold(0.0, (sum, r) => sum + r.points);
    result0 = (
      attempt: resultAttempt(score: score, passed: score / 48 >= 0.6),
      rows: rows,
      previous: result0.previous,
      passPercent: result0.passPercent,
      missed: result0.missed,
    );
  }

  @override
  Future<void> deleteRecording(int attemptId, int ord, String path) async {
    deleted.add(ord);
    final rows = <ExamResultRow>[
      for (final row in result0.rows)
        row.ord == ord
            ? (
                ord: row.ord,
                item: row.item,
                given: null,
                points: 0.0,
                rubric: row.rubric,
                flagged: row.flagged,
              )
            : row,
    ];
    result0 = (
      attempt: result0.attempt,
      rows: rows,
      previous: result0.previous,
      passPercent: result0.passPercent,
      missed: result0.missed,
    );
  }

  @override
  Future<void> addToRevision(
    List<String> uids, {
    required PlanDate today,
  }) async {
    if (failAdd) throw StateError('disk full');
    added.add((uids, today));
  }
}

List<Override> examResultStub([StubExamResult? stub]) => <Override>[
  examResultServiceProvider.overrideWithValue(stub ?? StubExamResult()),
];

/// A paper that does not pass: the artboard's, with six Vocabulary and all
/// of Reverse missed — 25 of 48.
ExamResult failedResult() {
  var vocabulary = 6;
  final rows = <ExamResultRow>[
    for (final row in artboardRows())
      if ((row.item.section == ExamSection.vocabulary &&
              row.points == 1 &&
              vocabulary-- > 0) ||
          row.item.section == ExamSection.reverse)
        (
          ord: row.ord,
          item: row.item,
          given: row.given,
          points: 0.0,
          rubric: row.rubric,
          flagged: row.flagged,
        )
      else
        row,
  ];
  return (
    attempt: resultAttempt(score: 25, passed: false),
    rows: rows,
    previous: null,
    passPercent: 60,
    missed: missedWords(rows),
  );
}
