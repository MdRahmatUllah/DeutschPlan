import 'dart:async';

import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/features/learn/exam_intro_screen.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The ExamHub artboard: Mock 1 passed at 78 % in two attempts, Mock 2 at
/// 62 % in one, Mock 3 not sat.
ExamHub artboardExamHub({
  List<SeedSummary>? seeds,
  Map<int, int> resume = const <int, int>{},
  Set<int> reused = const <int>{},
}) => (
  seeds:
      seeds ??
      const <SeedSummary>[
        SeedSummary(
          seed: 1,
          attempts: 2,
          finished: 2,
          bestPercent: 78.2,
          everPassed: true,
        ),
        SeedSummary(
          seed: 2,
          attempts: 1,
          finished: 1,
          bestPercent: 62,
          everPassed: false,
        ),
      ],
  resume: resume,
  reused: reused,
);

/// The ExamHub artboards' settings: pass mark 60 %, unlocked at 90 %,
/// listening on.
ExamRules artboardExamRules({
  int passPercent = 60,
  int unlockPercent = 90,
  bool listening = true,
}) => (
  passPercent: passPercent,
  unlockPercent: unlockPercent,
  listening: listening,
);

/// The ExamIntro artboard: Mock 2 of A1.2, 62 % in one attempt, pass mark
/// 60 %, listening and the timer on.
ExamIntro artboardExamIntro({
  SeedSummary? best = const SeedSummary(
    seed: 2,
    attempts: 1,
    finished: 1,
    bestPercent: 62,
    everPassed: false,
  ),
  int passPercent = 60,
  bool listening = true,
  bool timer = true,
}) =>
    (best: best, passPercent: passPercent, listening: listening, timer: timer);

/// L10 and L11 without a database: the ExamHub and ExamIntro artboards,
/// and a *Begin exam* that begins attempt 42 and records what it was
/// asked.
///
/// [hubPending]: the papers never done, what a locked tab must not wait on.
List<Override> examStub({
  ExamHub? hub,
  ExamRules? rules,
  ExamIntro? intro,
  bool hubPending = false,
}) => <Override>[
  examHubProvider.overrideWith(
    (ref, code) => hubPending
        ? Completer<ExamHub>().future
        : Future<ExamHub>.value(hub ?? artboardExamHub()),
  ),
  examRulesProvider.overrideWithValue(rules ?? artboardExamRules()),
  examIntroProvider.overrideWith(
    (ref, mock) async => intro ?? artboardExamIntro(),
  ),
  examStartProvider.overrideWith(StubExamStart.new),
];

/// *Begin exam* without a database.
class StubExamStart extends ExamStart {
  /// Every begin, as (step, seed, timer).
  static final List<(String, int, bool)> begun = <(String, int, bool)>[];

  /// Set to make the next begin throw, as a failed write would.
  static bool fail = false;

  @override
  bool build() => false;

  @override
  Future<int?> begin(String step, int seed, {required bool timer}) async {
    begun.add((step, seed, timer));
    if (fail) throw Exception('no database');
    return 42;
  }
}
