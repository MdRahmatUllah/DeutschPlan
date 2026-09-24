import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:deutschplan/features/me/me_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'today_fixtures.dart';

/// The Me artboard's course: 1,248 done, 312 learning and 4,034 to do, A1.1
/// and A1.2 passed, A2.1 current with its exams still locked.
List<StepProgress> artboardMeCourse() => <StepProgress>[
  for (final step in artboardCourse())
    switch (step.code) {
      'A1.1' => _counts(step, done: 560, learning: 40, todo: 0),
      'A1.2' => _counts(step, done: 520, learning: 80, todo: 0),
      'A2.1' => _counts(step, done: 168, learning: 192, todo: 180),
      'A2.2' => _counts(step, done: 0, learning: 0, todo: 270),
      _ => step,
    },
];

StepProgress _counts(
  StepProgress step, {
  required int done,
  required int learning,
  required int todo,
}) => StepProgress(
  code: step.code,
  levelCode: step.levelCode,
  words: done + learning + todo,
  todo: todo,
  learning: learning,
  done: done,
  grammar: step.grammar,
  grammarLearned: step.grammarLearned,
  unlocked: step.unlocked,
  passedSeed: step.passedSeed,
  startedOn: step.startedOn,
  completedOn: step.completedOn,
  dailyNew: step.dailyNew,
  studyDaysMask: step.studyDaysMask,
);

/// The Me artboard's heat-map, a column a week and a digit a day from
/// Monday, in the shades it draws: 2 is 10–19 items, 3 is 20–39, 4 is 40 or
/// more. The last week is the artboards' Monday, 21 September.
const List<String> artboardHeatMap = <String>[
  '0022333',
  '0223334',
  '2233344',
  '2333440',
  '3334400',
  '3344002',
  '3440022',
  '4400223',
  '4002233',
  '0022333',
  '0223334',
  '2000000',
];

/// The items that draw [artboardHeatMap], keyed by day.
Map<String, int> artboardActivity() {
  const items = <int>[0, 5, 15, 30, 45];
  final days = activityWeeks('2026-09-21');
  return <String, int>{
    for (final (week, column) in artboardHeatMap.indexed)
      for (final (day, shade) in column.split('').indexed)
        if (shade != '0') days[week][day]!: items[int.parse(shade)],
  };
}

/// The Me artboard: a 12-day streak, learning since 19 August, two days
/// behind with 14 words in the backlog.
MeView artboardMe({
  List<StepProgress>? steps,
  ScheduleStatus schedule = const ScheduleStatus(
    planned: 140,
    introduced: 126,
    dailyNew: 7,
  ),
  Map<String, int>? activity,
  PlanDate? since = '2026-08-19',
}) => (
  today: '2026-09-21',
  steps: steps ?? artboardMeCourse(),
  streak: 12,
  since: since,
  activity: activity ?? artboardActivity(),
  schedule: schedule,
  doneDays: 7,
  unlockPercent: 90,
);

/// M1 without a database: the Me artboard, and Maruf.
List<Override> meStub([MeView? view]) => <Override>[
  meViewProvider.overrideWith((ref) async => view ?? artboardMe()),
  learnerNameProvider.overrideWith(StubLearnerName.new),
];

/// The artboard's name, renamed in memory.
class StubLearnerName extends LearnerName {
  @override
  String? build() => 'Maruf';

  @override
  Future<void> rename(String name) async =>
      state = name.trim().isEmpty ? null : name.trim();
}
