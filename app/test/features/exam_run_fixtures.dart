import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart' show ExamAttempt;
import 'package:deutschplan/data/repositories/exam_repository.dart'
    show ExamScore;
import 'package:deutschplan/data/repositories/exam_run_service.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart' show FormLabel;
import 'package:flutter_riverpod/misc.dart' show Override;

/// The ExamRunner artboard's attempt: A1.2 · Mock 2, 14:32 left.
ExamAttempt artboardAttempt({
  int durationSec = 20 * 60 - (14 * 60 + 32),
  String status = 'in_progress',
}) => ExamAttempt(
  id: 7,
  sublevelCode: 'A1.2',
  seed: 2,
  startedAt: '2026-09-21T19:00:00.000Z',
  pausedSec: 0,
  durationSec: durationSec,
  scorePoints: 0,
  maxPoints: 0,
  passed: 0,
  status: status,
);

/// A full paper in BR-EXAM-03's order: 10 · 8 · 6 · 4 · 6 · 4 · 2, then
/// Writing and Speaking. The artboard's question 21, the third of the six
/// Articles, is "Wohnung".
List<ExamItem> artboardPaper() => <ExamItem>[
  for (var i = 1; i <= 10; i++)
    WordQuestion(
      ExamSection.vocabulary,
      'v$i',
      prompt: 'das Wort$i',
      expected: 'word $i',
    ),
  for (var i = 1; i <= 8; i++)
    WordQuestion(
      ExamSection.reverse,
      'r$i',
      prompt: 'word $i',
      expected: 'das Wort$i',
    ),
  for (var i = 1; i <= 6; i++)
    i == 3
        ? const WordQuestion(
            ExamSection.articles,
            'wohnung',
            prompt: 'Wohnung',
            expected: 'die',
          )
        : WordQuestion(
            ExamSection.articles,
            'a$i',
            prompt: 'Wort$i',
            expected: 'das',
          ),
  for (var i = 1; i <= 4; i++)
    const WordQuestion(
      ExamSection.wordForms,
      'gehen',
      prompt: 'gehen',
      expected: 'ist gegangen',
      form: FormLabel.perfekt,
    ),
  for (var i = 1; i <= 6; i++)
    GapQuestion(
      'g$i',
      before: 'Ich',
      after: 'gern.',
      answer: 'lese',
      translation: 'I like reading.',
    ),
  const GrammarQuestion(
    't1#0',
    GapFill(
      before: 'Ich',
      after: 'gern einen Kaffee.',
      answer: 'hätte',
      translation: "I'd like a coffee.",
    ),
  ),
  const GrammarQuestion(
    't2#1',
    PickTheForm(
      before: '',
      after: 'Sie mir helfen?',
      options: <String>['Könnten', 'Können', 'Konnten'],
      answer: 'Könnten',
      translation: 'Could you help me?',
    ),
  ),
  const GrammarQuestion(
    't3#2',
    SpotTheError(
      tokens: <String>['Können', 'Sie', 'mir', 'helfen?'],
      wrong: 0,
      correction: 'Könnten',
    ),
  ),
  const GrammarQuestion(
    't4#4',
    RuleRecall(
      question: 'Konjunktiv II – Höflichkeit',
      options: <String>[
        'könnte for polite requests',
        'verb last',
        'dative',
        'v2',
      ],
      answer: 0,
    ),
  ),
  for (var i = 1; i <= 2; i++)
    WordQuestion(
      ExamSection.listening,
      'l$i',
      prompt: 'das Haus',
      expected: 'das Haus',
    ),
  const WritingTask(
    'writing:1',
    level: 'A1',
    category: 'Wohnen',
    targets: <String>['Wohnung', 'Miete'],
    minWords: 30,
    connectors: <String>['und', 'aber'],
  ),
  const SpeakingTask(
    'speaking:1',
    level: 'A1',
    category: 'Wohnen',
    seconds: 60,
  ),
];

/// L12 without a database: a paper, and a record of what the runner did.
class StubExamRun implements ExamRunService {
  StubExamRun({
    List<ExamItem>? items,
    Map<int, String>? given,
    this.attempt,
    this.timed = true,
    this.missing = false,
    this.flagged = const <int>{},
  }) : items = items ?? artboardPaper(),
       given = given ?? {for (var ord = 1; ord <= 20; ord++) ord: 'x'};

  final List<ExamItem> items;

  /// The answers already stored, by ord; the first missing is where it
  /// resumes.
  final Map<int, String> given;
  final ExamAttempt? attempt;
  final bool missing;

  /// The ords already flagged.
  final Set<int> flagged;

  @override
  final bool timed;

  /// Each answer written: its ord and value.
  final List<(int, String?)> answers = <(int, String?)>[];

  /// Each flag written.
  final List<(int, bool)> flags = <(int, bool)>[];

  /// Each time written: seconds running and paused.
  final List<(int, int)> times = <(int, int)>[];

  int submitted = 0;

  /// Makes the next submits throw, as a failed write would.
  bool failSubmit = false;

  /// How often *Leave* abandoned the attempt.
  int abandoned = 0;

  @override
  Future<ExamPaperRun?> load(int attemptId) async {
    if (missing) return null;
    final questions = <ExamRunQuestion>[
      for (final (i, item) in items.indexed)
        (
          ord: i + 1,
          item: item,
          given: given[i + 1],
          flagged: flagged.contains(i + 1),
        ),
    ];
    final at = questions.indexWhere((q) => q.given == null);
    return (
      attempt: attempt ?? artboardAttempt(),
      questions: questions,
      resumeAt: at < 0 ? 0 : at,
    );
  }

  @override
  Future<void> answer(int attemptId, int ord, String? given) async =>
      answers.add((ord, given));

  @override
  Future<void> flag(int attemptId, int ord, {required bool flagged}) async =>
      flags.add((ord, flagged));

  @override
  Future<void> recordTime(
    int attemptId, {
    int running = 0,
    int paused = 0,
  }) async => times.add((running, paused));

  @override
  Future<void> abandon(int attemptId) async => abandoned++;

  @override
  Future<ExamScore> submit(int attemptId) async {
    submitted++;
    if (failSubmit) throw StateError('disk full');
    return const ExamScore(scorePoints: 30, maxPoints: 48, passed: true);
  }
}

List<Override> examRunStub([StubExamRun? run]) => <Override>[
  examRunServiceProvider.overrideWithValue(run ?? StubExamRun()),
];
