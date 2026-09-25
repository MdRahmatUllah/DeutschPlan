import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/progress_stats.dart';
import 'package:deutschplan/features/me/progress_screen.dart';

/// The Progress artboard's week (21–27 September 2026): 85 cards, nothing on
/// Tuesday and Wednesday, 88 % remembered against a 90 % target.
ProgressView artboardProgress({
  int? retentionDaysLeft,
  double? retentionOverall = 0.88,
}) => (
  bars: const <ProgressBar>[
    (start: '2026-09-21', reviews: 11, newWords: 6),
    (start: '2026-09-22', reviews: 0, newWords: 0),
    (start: '2026-09-23', reviews: 0, newWords: 0),
    (start: '2026-09-24', reviews: 20, newWords: 6),
    (start: '2026-09-25', reviews: 13, newWords: 6),
    (start: '2026-09-26', reviews: 9, newWords: 6),
    (start: '2026-09-27', reviews: 6, newWords: 2),
  ],
  retention: const <double?>[0.86, 0.9, 0.88, 0.92, 0.89, 0.9, 0.93],
  retentionOverall: retentionOverall,
  target: 0.9,
  retentionDaysLeft: retentionDaysLeft,
  totals: (seconds: 6 * 3600 + 48 * 60, introduced: 1560, reviews: 4912),
  streak: 12,
  best: 19,
);

/// The artboard's steps: A1.1 and A1.2 done, A2.1 184 of 540.
List<StepProgress> artboardProgressSteps() => <StepProgress>[
  for (final (code, level, done, learning, words, passed)
      in <(String, String, int, int, int, bool)>[
        ('A1.1', 'A1', 480, 0, 480, true),
        ('A1.2', 'A1', 470, 0, 470, true),
        ('A2.1', 'A2', 184, 20, 540, false),
        ('A2.2', 'A2', 0, 0, 498, false),
      ])
    StepProgress(
      code: code,
      levelCode: level,
      words: words,
      todo: words - done - learning,
      learning: learning,
      done: done,
      grammar: 10,
      grammarLearned: passed ? 10 : 3,
      unlocked: passed,
      passedSeed: passed ? 1 : null,
      startedOn: code == 'A2.2' ? null : '2026-06-01',
      completedOn: passed ? '2026-08-01' : null,
      dailyNew: 7,
      studyDaysMask: 127,
    ),
];
