/// BR-PLAN-09, BR-PLAN-10 and the two numbers Today shows about progress.
/// `docs/03-domain/plan-engine.md`.
///
/// Pure functions over counts and dates. The queries that produce those counts
/// live in `data/`; everything here can be tested by calling it.
library;

import 'package:deutschplan/domain/plan_engine.dart';

/// How many days in a row the learner has kept going.
///
/// Counts back from [today], or from yesterday when today has no activity yet
/// — opening the app in the morning must not read as a broken streak.
///
/// A rest day counts as kept (BR-PLAN-01: "streak preserved"). A study day with
/// no activity ends it.
///
/// [maxLookback] bounds the walk. A streak longer than a year is not worth the
/// scan, and an unbounded loop over dates is a hang waiting for a bad clock.
int streakLength({
  required PlanDate today,
  required Set<PlanDate> activeDays,
  required bool Function(PlanDate) isStudyDay,
  int maxLookback = 400,
}) {
  // Today counts only if something happened. Otherwise the streak is whatever
  // it was yesterday, and today is still open.
  var cursor = activeDays.contains(today) ? today : addDays(today, -1);
  var length = 0;

  for (var step = 0; step < maxLookback; step++) {
    final active = activeDays.contains(cursor);
    final rest = !isStudyDay(cursor);

    if (!active && !rest) break;

    // A rest day preserves the streak without lengthening it. Counting it
    // would let someone with a two-day study week claim seven.
    if (active) length++;

    cursor = addDays(cursor, -1);
  }

  return length;
}

/// FR-M2-02: the longest streak there has been, rest days kept as
/// `streakLength` keeps them — they carry a run without lengthening it.
int longestStreak({
  required Set<PlanDate> activeDays,
  required bool Function(PlanDate) isStudyDay,
  required PlanDate today,
}) {
  if (activeDays.isEmpty) return 0;
  final sorted = activeDays.toList()..sort();
  var best = 0;
  var run = 0;
  for (
    var day = sorted.first;
    day.compareTo(today) <= 0;
    day = addDays(day, 1)
  ) {
    if (activeDays.contains(day)) {
      run++;
      if (run > best) best = run;
    } else if (isStudyDay(day) && day != today) {
      // A study day with nothing done ends the run. Today is still open.
      run = 0;
    }
  }
  return best;
}

/// "Am I on schedule?" — how far behind the plan the learner is.
class ScheduleStatus {
  const ScheduleStatus({
    required this.planned,
    required this.introduced,
    required this.dailyNew,
  });

  /// New items planned for today or earlier.
  final int planned;

  /// How many of those the learner has actually done.
  final int introduced;

  /// The pace those days were planned at.
  final int dailyNew;

  /// Never negative: doing extra through the backlog is not "ahead", it is
  /// caught up. There is no plan beyond today to be ahead of.
  int get behind => planned - introduced < 0 ? 0 : planned - introduced;

  /// Days' worth of work outstanding.
  ///
  /// A fraction, because "half a day behind" is the honest answer and rounding
  /// it up to one would tell a learner who missed three words that they are a
  /// day down.
  double get daysBehind => dailyNew <= 0 ? 0 : behind / dailyNew;

  bool get onSchedule => behind == 0;
}

/// Seconds per item, for the time estimate (BR-PLAN-09).
class ItemSeconds {
  const ItemSeconds({
    required this.revision,
    required this.newWord,
    required this.grammar,
    required this.sentence,
  });

  /// The defaults the rule gives: 25 / 45 / 60 / 40.
  static const ItemSeconds defaults = ItemSeconds(
    revision: 25,
    newWord: 45,
    grammar: 60,
    sentence: 40,
  );

  final int revision;
  final int newWord;
  final int grammar;
  final int sentence;

  /// The learner's own timings where there are enough of them, the defaults
  /// elsewhere. A null field means "not measured", not "zero seconds".
  ItemSeconds withMeasured({
    int? revision,
    int? newWord,
    int? grammar,
    int? sentence,
  }) => ItemSeconds(
    revision: revision ?? this.revision,
    newWord: newWord ?? this.newWord,
    grammar: grammar ?? this.grammar,
    sentence: sentence ?? this.sentence,
  );

  @override
  String toString() => 'ItemSeconds($revision, $newWord, $grammar, $sentence)';
}

/// BR-PLAN-09: how long today's plan should take.
Duration timeEstimate({
  required int revisions,
  required int newWords,
  required int grammar,
  required int sentences,
  ItemSeconds seconds = ItemSeconds.defaults,
}) => Duration(
  seconds:
      revisions * seconds.revision +
      newWords * seconds.newWord +
      grammar * seconds.grammar +
      sentences * seconds.sentence,
);

/// How many sessions of history BR-PLAN-09 wants before it trusts the
/// learner's own timings over the defaults.
const int measuredTimingsAfterSessions = 7;

/// The middle value, or null when there is nothing to take a middle of.
///
/// Median rather than mean: one review interrupted by a phone call would drag
/// an average up for weeks.
int? medianOf(List<int> values) {
  if (values.isEmpty) return null;

  final sorted = <int>[...values]..sort();
  final middle = sorted.length ~/ 2;

  return sorted.length.isOdd
      ? sorted[middle]
      : ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

/// A gap longer than this is the learner putting the phone down, not time
/// spent on the next item.
///
/// Timings are derived from the gaps between consecutive log entries, because
/// nothing records seconds per item. Without a cut-off, a session resumed
/// after lunch would add a two-hour "review" to the median.
const Duration sessionGapLimit = Duration(minutes: 5);

/// Seconds between consecutive instants, dropping the gaps that are really
/// breaks.
///
/// [instants] must be in order. The first entry has no predecessor and so no
/// duration — the time spent on the first item of a session is not recoverable
/// from timestamps alone, and guessing it would bias every median down.
List<int> gapSeconds(List<DateTime> instants) {
  final gaps = <int>[];

  for (var i = 1; i < instants.length; i++) {
    final gap = instants[i].difference(instants[i - 1]);
    if (gap <= Duration.zero || gap > sessionGapLimit) continue;
    gaps.add(gap.inSeconds);
  }

  return gaps;
}

/// BR-PLAN-10: computed, never stored.
///
/// Stored would mean a second truth that drifts the moment a rating is undone.
bool dayComplete({
  required int openPlanItems,
  required int grammarDue,
  required int openSentences,
  required bool isStudyDay,
}) =>
    // A rest day is complete by definition (BR-PLAN-01), whatever is open —
    // there was nothing asked of the learner to leave undone.
    isStudyDay
    ? openPlanItems == 0 && grammarDue == 0 && openSentences == 0
    : true;

/// How many of the seven days [studyDaysMask] marks — Monday at bit 0, as
/// `PlanEngine.isStudyDay` reads it.
int studyDaysPerWeek(int studyDaysMask) {
  var count = 0;
  for (var day = 0; day < 7; day++) {
    if (studyDaysMask & (1 << day) != 0) count++;
  }
  return count;
}

/// FR-S2-04: about how many calendar days a step takes.
///
/// "The selected step's word count ÷ daily_new × (7 ÷ study days per week)",
/// in whole numbers: `words × 7 ÷ (dailyNew × days)`, rounded up. Rounded up
/// because a step with one word left over takes one more day, not none — and
/// in integers because the same sum in doubles puts 180 words at 7 a day over
/// six days at 30.000000000000004, which rounds up to 31.
///
/// Null when there is nothing to divide by: no study days, or no new words.
int? courseDays({
  required int words,
  required int dailyNew,
  required int studyDaysMask,
}) {
  final perWeek = studyDaysPerWeek(studyDaysMask);
  final perWeekNew = dailyNew * perWeek;
  if (perWeekNew <= 0) return null;
  return (words * 7 + perWeekNew - 1) ~/ perWeekNew;
}
