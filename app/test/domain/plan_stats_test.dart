@TestOn('vm')
library;

import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// Streak, schedule check and time estimate — #79.
///
/// BR-PLAN-09 and BR-PLAN-10, plus the two numbers Today shows about progress.
/// Pure functions, so these are called directly.
void main() {
  /// A Monday.
  const monday = '2026-03-02';

  /// Every day is a study day unless a test says otherwise.
  bool always(PlanDate _) => true;

  /// Weekdays only.
  bool weekdays(PlanDate day) => parsePlanDate(day).weekday <= 5;

  Set<PlanDate> days(Iterable<int> offsets) => <PlanDate>{
    for (final offset in offsets) addDays(monday, offset),
  };

  group('the streak', () {
    test('counts consecutive days back from today', () {
      expect(
        streakLength(
          today: addDays(monday, 4),
          activeDays: days(<int>[0, 1, 2, 3, 4]),
          isStudyDay: always,
        ),
        5,
      );
    });

    test('stops at the first study day with nothing done', () {
      expect(
        streakLength(
          today: addDays(monday, 4),
          activeDays: days(<int>[0, 1, 3, 4]),
          isStudyDay: always,
        ),
        2,
        reason: 'day 2 was missed, so only days 3 and 4 count',
      );
    });

    test('a day with nothing done today does not break it', () {
      // Opening the app in the morning must not read as a broken streak.
      expect(
        streakLength(
          today: addDays(monday, 5),
          activeDays: days(<int>[0, 1, 2, 3, 4]),
          isStudyDay: always,
        ),
        5,
      );
    });

    test('and today counts as soon as something is done', () {
      expect(
        streakLength(
          today: addDays(monday, 5),
          activeDays: days(<int>[0, 1, 2, 3, 4, 5]),
          isStudyDay: always,
        ),
        6,
      );
    });

    test('a rest day preserves it without lengthening it', () {
      // BR-PLAN-01: "streak preserved". Saturday and Sunday are skipped, and
      // the previous Friday still counts.
      expect(
        streakLength(
          today: addDays(monday, 7),
          activeDays: days(<int>[0, 1, 2, 3, 4, 7]),
          isStudyDay: weekdays,
        ),
        6,
        reason: 'five weekdays plus the next Monday',
      );
    });

    test('and a rest day alone is a streak of nothing', () {
      // Counting rest days would let a two-day study week claim seven.
      expect(
        streakLength(
          today: addDays(monday, 5),
          activeDays: <PlanDate>{},
          isStudyDay: weekdays,
        ),
        0,
      );
    });

    test('a missed study day between rest days still ends it', () {
      expect(
        streakLength(
          today: addDays(monday, 7),
          activeDays: days(<int>[0, 1, 2, 7]),
          isStudyDay: weekdays,
        ),
        1,
        reason: 'Thursday and Friday were missed',
      );
    });

    test('no activity at all is zero, not one', () {
      expect(
        streakLength(
          today: monday,
          activeDays: <PlanDate>{},
          isStudyDay: always,
        ),
        0,
      );
    });

    test('and it is bounded rather than walking forever', () {
      // Every day active and every day a study day: without the bound this
      // walks back to year zero.
      var asked = 0;
      final unbounded = streakLength(
        today: monday,
        activeDays: _AlwaysIn(() => asked++),
        isStudyDay: always,
        maxLookback: 30,
      );

      expect(unbounded, 30);
      expect(asked, lessThan(40), reason: 'it kept walking past the bound');
    });
  });

  group('the schedule check', () {
    test('behind is planned minus introduced', () {
      const status = ScheduleStatus(planned: 21, introduced: 14, dailyNew: 7);

      expect(status.behind, 7);
      expect(status.daysBehind, 1.0);
      expect(status.onSchedule, isFalse);
    });

    test('on schedule when everything planned is done', () {
      const status = ScheduleStatus(planned: 21, introduced: 21, dailyNew: 7);

      expect(status.behind, 0);
      expect(status.daysBehind, 0);
      expect(status.onSchedule, isTrue);
    });

    test('doing extra is caught up, not ahead', () {
      // There is no plan beyond today to be ahead of — a learner who worked
      // through the backlog has caught up, and a negative "days behind" would
      // read as credit they do not have.
      const status = ScheduleStatus(planned: 14, introduced: 21, dailyNew: 7);

      expect(status.behind, 0);
      expect(status.daysBehind, 0);
      expect(status.onSchedule, isTrue);
    });

    test('days behind is a fraction, not a whole day', () {
      // Rounding three missed words up to a whole day tells the learner
      // something worse than the truth.
      const status = ScheduleStatus(planned: 10, introduced: 7, dailyNew: 7);

      expect(status.behind, 3);
      expect(status.daysBehind, closeTo(3 / 7, 0.0001));
    });

    test('a zero pace does not divide by zero', () {
      const status = ScheduleStatus(planned: 10, introduced: 0, dailyNew: 0);

      expect(status.daysBehind, 0);
      expect(status.daysBehind.isNaN, isFalse);
      expect(status.daysBehind.isInfinite, isFalse);
    });
  });

  group('BR-PLAN-09 — the time estimate', () {
    test('uses 25 / 45 / 60 / 40 by default', () {
      expect(
        timeEstimate(revisions: 1, newWords: 1, grammar: 1, sentences: 1),
        const Duration(seconds: 170),
      );
    });

    test('a full default day is about eleven minutes', () {
      // Ten revisions, seven new, one grammar topic, three sentences.
      expect(
        timeEstimate(revisions: 10, newWords: 7, grammar: 1, sentences: 3),
        const Duration(seconds: 25 * 10 + 45 * 7 + 60 + 40 * 3),
      );
    });

    test('an empty day is no time at all', () {
      expect(
        timeEstimate(revisions: 0, newWords: 0, grammar: 0, sentences: 0),
        Duration.zero,
      );
    });

    test('the learner\'s own timings replace the defaults', () {
      final mine = ItemSeconds.defaults.withMeasured(revision: 10, newWord: 20);

      expect(
        timeEstimate(
          revisions: 2,
          newWords: 2,
          grammar: 1,
          sentences: 1,
          seconds: mine,
        ),
        const Duration(seconds: 10 * 2 + 20 * 2 + 60 + 40),
        reason: 'grammar and sentences keep their defaults',
      );
    });

    test('and a timing that could not be measured keeps its default', () {
      // Null means "not measured", not "zero seconds" — the difference between
      // a default and an estimate of nothing.
      final partial = ItemSeconds.defaults.withMeasured(revision: null);

      expect(partial.revision, 25);
    });
  });

  group('the median', () {
    test('is the middle of an odd list', () {
      expect(medianOf(<int>[5, 1, 3]), 3);
    });

    test('and the mean of the middle two of an even one', () {
      expect(medianOf(<int>[1, 2, 3, 4]), 3, reason: '(2 + 3) / 2 rounds to 3');
      expect(medianOf(<int>[10, 20]), 15);
    });

    test('nothing to average is null, not zero', () {
      expect(medianOf(<int>[]), isNull);
    });

    test('one outlier does not move it, which is why it is not a mean', () {
      // A review interrupted by a phone call would drag an average up for
      // weeks.
      expect(medianOf(<int>[20, 22, 24, 26, 3600]), 24);
    });

    test('it does not reorder the caller\'s list', () {
      final values = <int>[5, 1, 3];
      medianOf(values);
      expect(values, <int>[5, 1, 3]);
    });
  });

  group('the gaps timings come from', () {
    DateTime at(int second) => DateTime.utc(2026, 3, 2, 9, 0, second);

    test('are the differences between consecutive entries', () {
      expect(gapSeconds(<DateTime>[at(0), at(20), at(50)]), <int>[20, 30]);
    });

    test('and the first entry contributes nothing', () {
      // Time spent on the first item of a session is not recoverable from
      // timestamps, and guessing it would bias every median down.
      expect(gapSeconds(<DateTime>[at(0)]), isEmpty);
      expect(gapSeconds(<DateTime>[]), isEmpty);
    });

    test('a break is dropped rather than counted', () {
      expect(
        gapSeconds(<DateTime>[
          at(0),
          at(20),
          DateTime.utc(2026, 3, 2, 11),
          DateTime.utc(2026, 3, 2, 11, 0, 30),
        ]),
        <int>[20, 30],
        reason: 'the two-hour gap is lunch, not a review',
      );
    });

    test('the limit is five minutes', () {
      expect(gapSeconds(<DateTime>[at(0), at(300)]), <int>[300]);
      expect(gapSeconds(<DateTime>[at(0), at(301)]), isEmpty);
    });

    test('and a clock that went backwards contributes nothing', () {
      expect(gapSeconds(<DateTime>[at(50), at(20)]), isEmpty);
      expect(gapSeconds(<DateTime>[at(20), at(20)]), isEmpty);
    });
  });

  group('BR-PLAN-10 — day complete', () {
    test('is true when nothing is open', () {
      expect(
        dayComplete(
          openPlanItems: 0,
          grammarDue: 0,
          openSentences: 0,
          isStudyDay: true,
        ),
        isTrue,
      );
    });

    test('and false while any one of the three is', () {
      for (final open in const <(int, int, int)>[
        (1, 0, 0),
        (0, 1, 0),
        (0, 0, 1),
      ]) {
        expect(
          dayComplete(
            openPlanItems: open.$1,
            grammarDue: open.$2,
            openSentences: open.$3,
            isStudyDay: true,
          ),
          isFalse,
          reason: '$open',
        );
      }
    });

    test('a rest day is complete whatever is open', () {
      // BR-PLAN-01: rest days count as complete for the streak. Nothing was
      // asked of the learner, so nothing was left undone.
      expect(
        dayComplete(
          openPlanItems: 7,
          grammarDue: 2,
          openSentences: 3,
          isStudyDay: false,
        ),
        isTrue,
      );
    });
  });
}

/// A set that says every date is in it, and counts how often it is asked.
///
/// The streak walk has to stop on its own; a set built from real dates would
/// run out before the bound and prove nothing.
class _AlwaysIn implements Set<PlanDate> {
  _AlwaysIn(this._onAsk);

  final void Function() _onAsk;

  @override
  bool contains(Object? element) {
    _onAsk();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
