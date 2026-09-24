import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The ExamHub artboard: Mock 1 passed at 78 % in two attempts, Mock 2 at
/// 62 % in one, Mock 3 not sat; pass mark 60 %, listening on.
ExamHub artboardExamHub({
  List<SeedSummary>? seeds,
  Map<int, int> resume = const <int, int>{},
  int passPercent = 60,
  bool listening = true,
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
  passPercent: passPercent,
  listening: listening,
  reused: reused,
);

/// L10 without a database: the ExamHub artboard, for every step.
List<Override> examStub([ExamHub? hub]) => <Override>[
  examHubProvider.overrideWith((ref, code) async => hub ?? artboardExamHub()),
];
