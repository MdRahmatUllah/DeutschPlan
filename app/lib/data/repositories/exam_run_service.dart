import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart' show ExamAttempt;
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart' show rubricTicks;

/// One question of a paper, as the runner holds it.
typedef ExamRunQuestion = ({
  int ord,
  ExamItem item,
  String? given,
  bool flagged,

  /// A task's rubric ticks so far (FR-L12S-03); empty for a question.
  List<bool> rubric,
});

/// L12's paper: the attempt, its questions in order, and where to resume.
typedef ExamPaperRun = ({
  ExamAttempt attempt,
  List<ExamRunQuestion> questions,

  /// The index of the first unanswered question (FR-L12-01); 0 when every
  /// one has an answer.
  int resumeAt,
});

/// L12's data (`exam-runner.md`, #130): reads the paper L11 stored, writes
/// each answer and flag as it is given, the time as it runs, and grades the
/// submit. The runner talks to this and nothing else, so a test or a golden
/// can hand it a paper without a database.
class ExamRunService {
  ExamRunService(this._exams, this._settings, this._now, this._models);

  final ExamRepository _exams;
  final ModelRepository _models;
  final SettingsRepository _settings;
  final DateTime Function() _now;

  /// Whether L11's *Timer on* is on: read when the runner opens, fresh or
  /// resumed, so a restored exam keeps it (exam-runner.md).
  bool get timed => _settings.read(SettingKeys.examTimer);

  /// The paper, or null for an attempt that isn't there.
  Future<ExamPaperRun?> load(int attemptId) async {
    final attempt = await _exams.attempt(attemptId);
    if (attempt == null) return null;
    final rows = await _exams.answers(attemptId);
    final questions = <ExamRunQuestion>[
      for (final row in rows)
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
          flagged: row.flagged != 0,
          rubric: rubricTicks(row.selfRubricJson),
        ),
    ];
    final next = await _exams.nextQuestion(attemptId);
    final at = questions.indexWhere((q) => q.ord == next);
    return (attempt: attempt, questions: questions, resumeAt: at < 0 ? 0 : at);
  }

  /// FR-L12-01: written as it is given, so a restart loses at most the
  /// answer being typed.
  Future<void> answer(int attemptId, int ord, String? given) =>
      _exams.answer(attemptId: attemptId, ord: ord, given: given);

  /// FR-L12S-03: the ticks, written as they are ticked.
  Future<void> rubric(int attemptId, int ord, List<bool> ticks) =>
      _exams.rubric(attemptId: attemptId, ord: ord, json: jsonEncode(ticks));

  /// FR-L12S-02: where this attempt's Speaking is recorded.
  Future<String> recordingPath(int attemptId) async {
    final file = await _models.recordingFor(attemptId);
    await file.parent.create(recursive: true);
    return file.path;
  }

  /// FR-L12S-04: the recording gone from the phone. The row's `given` is
  /// cleared by the runner, which is what zeros the section (#84).
  Future<void> discard(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  Future<void> flag(int attemptId, int ord, {required bool flagged}) =>
      _exams.flag(attemptId: attemptId, ord: ord, flagged: flagged);

  /// FR-L12-03: seconds run and seconds paused, added to the attempt.
  Future<void> recordTime(int attemptId, {int running = 0, int paused = 0}) =>
      _exams.recordTime(attemptId: attemptId, running: running, paused: paused);

  /// FR-L12-04: left. The answers stay, as an attempt without a score.
  Future<void> abandon(int attemptId) => _exams.abandon(attemptId);

  /// The submit: graded as the answers stand, and finished.
  Future<ExamScore> submit(int attemptId) => _exams.grade(
    attemptId,
    passPercent: _settings.read(SettingKeys.examPassPercent),
    finishedAt: _now().toUtc().toIso8601String(),
  );
}
