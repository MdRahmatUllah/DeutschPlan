import 'dart:convert';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show ReviewSource;
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart';

/// One item of a finished paper, as L13 shows it.
typedef ExamResultRow = ({
  int ord,
  ExamItem item,
  String? given,
  double points,

  /// A task's rubric ticks (FR-L12S-03); empty for a question.
  List<bool> rubric,
});

/// L13's data: the attempt as graded, its rows, the step's previous finished
/// attempt with its number, and the pass mark.
typedef ExamResult = ({
  ExamAttempt attempt,
  List<ExamResultRow> rows,
  ({ExamAttempt attempt, int number})? previous,
  int passPercent,
});

/// L13's data (`exam-results.md`, #135): the result, the rubric a learner
/// ticks here and the re-grade it causes (FR-L13-03), and the missed words
/// into revision (FR-L13-02). The screen talks to this and nothing else, so
/// a test or a golden can hand it a result without a database.
class ExamResultService {
  ExamResultService(this._exams, this._settings, this._rating, this._words);

  final ExamRepository _exams;
  final SettingsRepository _settings;
  final RatingService _rating;
  final WordRepository _words;

  Future<ExamResult?> result(int attemptId) async {
    final attempt = await _exams.attempt(attemptId);
    if (attempt == null) return null;
    final rows = <ExamResultRow>[
      for (final row in await _exams.answers(attemptId))
        (
          ord: row.ord,
          item: ExamItem.decode((
            section: row.section,
            ref: row.itemRef,
            prompt: row.prompt,
            options: row.optionsJson,
            expected: row.expected,
          )),
          given: row.given,
          points: row.points,
          rubric: rubricTicks(row.selfRubricJson),
        ),
    ];
    final finished = await _exams.finishedAttempts(attempt.sublevelCode).get();
    final at = finished.indexWhere((a) => a.id == attemptId);
    return (
      attempt: attempt,
      rows: rows,
      previous: at > 0 ? (attempt: finished[at - 1], number: at) : null,
      passPercent: _settings.read(SettingKeys.examPassPercent),
    );
  }

  /// FR-L13-03: a task's ticks, then the paper graded again as it stands.
  /// The finish time stays the submit's.
  Future<void> rubric(int attemptId, int ord, List<bool> ticks) async {
    await _exams.rubric(
      attemptId: attemptId,
      ord: ord,
      json: jsonEncode(ticks),
    );
    await _exams.grade(
      attemptId,
      passPercent: _settings.read(SettingKeys.examPassPercent),
    );
  }

  /// FR-L13-02: every missed word rated Again (source `exam`), then due
  /// tomorrow. The exam itself rated nothing (BR-EXAM-05).
  Future<void> addToRevision(
    List<String> uids, {
    required PlanDate today,
  }) async {
    for (final uid in uids) {
      await _rating.rate(uid, Rating.again, source: ReviewSource.exam);
    }
    await _words.dueOn(uids, addDays(today, 1));
  }
}

/// The words [rows] missed: a word item (every section but Grammar, Writing
/// and Speaking) that scored less than its point, once each.
List<String> missedWords(List<ExamResultRow> rows) => <String>{
  for (final row in rows)
    if ((row.item is WordQuestion || row.item is GapQuestion) &&
        row.points < row.item.section.points)
      row.item.ref,
}.toList();
