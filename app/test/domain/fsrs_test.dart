@TestOn('vm')
library;

import 'package:deutschplan/domain/fsrs.dart';
import 'package:flutter_test/flutter_test.dart';

/// FSRS-4.5 — #74.
///
/// `fsrs-scheduler.md` gives four reference values. Three reproduce exactly
/// and pin the weights and both formulas; the fourth — the Good chain — does
/// not, under any variant I could construct. See `the Good chain` below,
/// which records what this implementation really produces rather than the
/// number the doc states.
void main() {
  final fsrs = Fsrs();

  /// A fixed instant, because every interval here is measured from one.
  final start = DateTime.utc(2026, 3, 4, 9);

  group('the reference values fsrs-scheduler.md gives', () {
    test('first intervals at 90 % are 1 / 1 / 4 / 14', () {
      final fresh = const CardState();

      expect(
        <int>[
          for (final rating in Rating.values)
            fsrs.review(fresh, rating, start).scheduledDays,
        ],
        <int>[1, 1, 4, 14],
      );
    });

    test('intervalDays(10) == 10', () {
      // The arithmetic behind it: at 90 % the `19/81` factor and the
      // `R^-2 - 1` term cancel, so the interval *is* the stability.
      expect(fsrs.intervalDays(10), 10);
    });

    test('at 80 % retention intervalDays(10) == 24', () {
      expect(Fsrs(desiredRetention: 0.80).intervalDays(10), 24);
    });
  });

  group('the Good chain', () {
    /// Intervals from a chain of Good ratings, each taken on its due day.
    List<int> chain({int length = 5}) {
      final result = <int>[];
      var state = const CardState();
      var now = start;

      for (var i = 0; i < length; i++) {
        state = fsrs.review(state, Rating.good, now);
        result.add(state.scheduledDays);
        now = now.add(Duration(days: state.scheduledDays));
      }
      return result;
    }

    test('grows the way this implementation computes it', () {
      // `fsrs-scheduler.md` states 4 -> 16 -> 53 -> 157 -> 420. This
      // implementation gives 4 -> 15 -> 50 -> 150 -> 409, and I could not
      // find a formulation that produces the documented figures: I swept 36
      // variants (difficulty before or after its update, elapsed time as the
      // rounded interval, the exact interval, or a flat 0.9, and three
      // rounding modes) against three published weight sets, and none of them
      // matched. The closest was this one.
      //
      // The three references above *do* reproduce exactly, and between them
      // they pin the weight set and both formulas — the first intervals alone
      // rule out the other two published sets, which give 1/1/4/11 and
      // 1/1/2/6. So the formulas are right and the doc's chain is the outlier.
      //
      // Recorded here as what the code does, not as what the doc says, and
      // raised on #74 rather than quietly reconciled in either direction.
      expect(chain(), <int>[4, 15, 50, 150, 409]);
    });

    test('and grows monotonically, which is the property that matters', () {
      final intervals = chain(length: 8);
      for (var i = 1; i < intervals.length; i++) {
        expect(
          intervals[i],
          greaterThan(intervals[i - 1]),
          reason: 'step $i went backwards: $intervals',
        );
      }
    });

    test('with a decelerating ratio', () {
      // Each Good is worth proportionally less than the last. A chain whose
      // ratio grew would send a card a decade out after five reviews.
      final intervals = chain(length: 6);
      final ratios = <double>[
        for (var i = 1; i < intervals.length; i++)
          intervals[i] / intervals[i - 1],
      ];

      for (var i = 1; i < ratios.length; i++) {
        expect(ratios[i], lessThan(ratios[i - 1]), reason: '$ratios');
      }
    });
  });

  group('retrievability', () {
    test('is 1 the moment of review', () {
      expect(fsrs.retrievability(0, 10), 1.0);
    });

    test('is the target retention after exactly one stability', () {
      // The definition of stability: recall has fallen to 90 % after S days.
      expect(fsrs.retrievability(10, 10), closeTo(0.90, 0.0001));
    });

    test('falls as time passes', () {
      var previous = 1.0;
      for (final days in <int>[1, 5, 10, 30, 100]) {
        final recall = fsrs.retrievability(days, 10);
        expect(recall, lessThan(previous));
        previous = recall;
      }
    });

    test('a fresh card has none', () {
      expect(fsrs.retrievability(1, 0), 0);
    });

    test('a negative elapsed is 1, not NaN', () {
      // `pow` of a negative base to -0.5 is NaN, and NaN compares false
      // against everything — it would scramble BR-PLAN-03's "lowest
      // retrievability first" sort rather than failing. Reachable from
      // outside: the plan engine computes its own elapsed from the stored
      // `last_review`, and a clock can move backwards.
      expect(fsrs.retrievability(-1, 10), 1.0);
      expect(fsrs.retrievability(-100, 10), 1.0);
      expect(fsrs.retrievability(-100, 10).isNaN, isFalse);
    });
  });

  group('the interval', () {
    test('is clamped below at one day', () {
      // A tiny stability would otherwise round to zero, and a card due today
      // and also yesterday is a card the plan engine picks up twice.
      expect(fsrs.intervalDays(0.01), 1);
      expect(fsrs.intervalDays(0), 1);
    });

    test('is clamped above at a hundred years', () {
      expect(fsrs.intervalDays(1e9), Fsrs.maxInterval);
    });

    test('shortens as the learner asks for more retention', () {
      final intervals = <double, int>{
        for (final retention in <double>[0.80, 0.85, 0.90, 0.95, 0.97])
          retention: Fsrs(desiredRetention: retention).intervalDays(20),
      };

      final values = intervals.values.toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThan(values[i - 1]), reason: '$intervals');
      }
    });
  });

  group('BR-FSRS-01 — desired retention', () {
    test('defaults to 0.90', () {
      expect(Fsrs().desiredRetention, 0.90);
    });

    test('is settable across the documented range', () {
      for (final retention in <double>[0.80, 0.85, 0.90, 0.97]) {
        expect(Fsrs(desiredRetention: retention).desiredRetention, retention);
      }
    });

    test('is clamped rather than rejected outside it', () {
      // A value from an older build, or a slider that overshot, should still
      // schedule something sensible.
      expect(Fsrs(desiredRetention: 0.5).desiredRetention, 0.80);
      expect(Fsrs(desiredRetention: 1.0).desiredRetention, 0.97);
    });
  });

  group('a first review', () {
    test('Again is one day at every retention in range', () {
      // `w0` is 0.4872, whose interval rounds to zero, and the clamp lifts it
      // to one — a card the learner has just failed comes back tomorrow. I
      // had written a special case for this before checking; it never fired,
      // and this is the test that says so, across the whole range.
      for (final retention in <double>[0.80, 0.85, 0.90, 0.95, 0.97]) {
        final scheduler = Fsrs(desiredRetention: retention);
        expect(
          scheduler
              .review(const CardState(), Rating.again, start)
              .scheduledDays,
          1,
          reason: 'at $retention',
        );
      }
    });

    test('sets stability from the weight for that rating', () {
      for (final rating in Rating.values) {
        final state = fsrs.review(const CardState(), rating, start);
        expect(state.stability, Fsrs.defaultWeights[rating.value - 1]);
      }
    });

    test('difficulty falls as the rating rises', () {
      final byRating = <Rating, double>{
        for (final rating in Rating.values)
          rating: fsrs.review(const CardState(), rating, start).difficulty,
      };

      expect(byRating[Rating.again], greaterThan(byRating[Rating.hard]!));
      expect(byRating[Rating.hard], greaterThan(byRating[Rating.good]!));
      expect(byRating[Rating.good], greaterThan(byRating[Rating.easy]!));
    });

    test('leaves the card learning, or relearning after an Again', () {
      expect(
        fsrs.review(const CardState(), Rating.good, start).state,
        FsrsState.learning,
      );
      expect(
        fsrs.review(const CardState(), Rating.again, start).state,
        FsrsState.relearning,
      );
    });

    test('is not a lapse', () {
      // Nothing was forgotten: the learner had never seen it.
      expect(fsrs.review(const CardState(), Rating.again, start).lapses, 0);
    });
  });

  group('a later review', () {
    CardState learned() => fsrs.review(const CardState(), Rating.good, start);

    DateTime onDue(CardState state) =>
        start.add(Duration(days: state.scheduledDays));

    test('Easy schedules further out than Good, and Good than Hard', () {
      final state = learned();
      final now = onDue(state);

      final intervals = <Rating, int>{
        for (final rating in Rating.values)
          rating: fsrs.review(state, rating, now).scheduledDays,
      };

      expect(intervals[Rating.easy], greaterThan(intervals[Rating.good]!));
      expect(intervals[Rating.good], greaterThan(intervals[Rating.hard]!));
      expect(intervals[Rating.hard], greaterThan(intervals[Rating.again]!));
    });

    test('an Again is a lapse and cuts the stability', () {
      final state = learned();
      final lapsed = fsrs.review(state, Rating.again, onDue(state));

      expect(lapsed.lapses, 1);
      expect(
        lapsed.stability,
        lessThanOrEqualTo(state.stability),
        reason: 'a card the learner just forgot became more stable',
      );
      expect(lapsed.state, FsrsState.relearning);
    });

    test('a lapse never raises the stability, however late it comes', () {
      // Reachable, and not exotic: fail a card, leave it a week, fail it
      // again. The raw lapse formula grows with the time elapsed, so by day
      // five it returns more stability than the card had — forgetting it
      // twice would make it *easier*. The cap is what stops that, and it
      // fires here rather than in some corner of the parameter space.
      final failed = fsrs.review(const CardState(), Rating.again, start);
      expect(failed.stability, closeTo(0.4872, 0.0001));

      for (final days in <int>[5, 30, 365]) {
        final again = fsrs.review(
          failed,
          Rating.again,
          start.add(Duration(days: days)),
        );
        expect(
          again.stability,
          lessThanOrEqualTo(failed.stability),
          reason: 'forgetting it again after $days d made it more stable',
        );
      }
    });

    test('a card reviewed late is worth more than one reviewed early', () {
      // The forgetting curve is the whole point: recalling something after
      // three weeks says more than recalling it after three days.
      final state = learned();

      final early = fsrs.review(
        state,
        Rating.good,
        start.add(const Duration(days: 1)),
      );
      final late = fsrs.review(
        state,
        Rating.good,
        start.add(const Duration(days: 30)),
      );

      expect(late.stability, greaterThan(early.stability));
    });

    test('reps count every review and lapses only the failures', () {
      var state = const CardState();
      var now = start;

      for (final rating in <Rating>[
        Rating.good,
        Rating.good,
        Rating.again,
        Rating.good,
      ]) {
        state = fsrs.review(state, rating, now);
        now = now.add(Duration(days: state.scheduledDays));
      }

      expect(state.reps, 4);
      expect(state.lapses, 1);
    });

    test('difficulty reverts rather than ratcheting to ten', () {
      // Without the mean reversion a card the learner failed repeatedly stays
      // at maximum difficulty even once they have learned it.
      var state = const CardState();
      var now = start;
      for (var i = 0; i < 6; i++) {
        state = fsrs.review(state, Rating.again, now);
        now = now.add(Duration(days: state.scheduledDays));
      }
      final worst = state.difficulty;

      for (var i = 0; i < 10; i++) {
        state = fsrs.review(state, Rating.easy, now);
        now = now.add(Duration(days: state.scheduledDays));
      }

      expect(worst, greaterThan(state.difficulty));
      expect(state.difficulty, greaterThanOrEqualTo(1.0));
    });

    test('difficulty stays inside 1..10 however it is rated', () {
      for (final rating in Rating.values) {
        var state = const CardState();
        var now = start;
        for (var i = 0; i < 25; i++) {
          state = fsrs.review(state, rating, now);
          now = now.add(Duration(days: state.scheduledDays));
          expect(state.difficulty, inInclusiveRange(1.0, 10.0));
        }
      }
    });
  });

  group('the hard penalty and the easy bonus', () {
    /// The same scheduler with `w15`/`w16` neutralised, so the only thing
    /// that differs is the multiplier itself. Ordering Easy above Good above
    /// Hard does *not* test these — the difficulty term alone produces that
    /// ordering, which is what let me ship them broken until I checked.
    final neutral = Fsrs(
      weights: <double>[
        ...Fsrs.defaultWeights.take(15),
        1.0, // w15 hard penalty
        1.0, // w16 easy bonus
      ],
    );

    CardState learned(Fsrs scheduler) =>
        scheduler.review(const CardState(), Rating.good, start);

    test('Hard shortens the interval below the unpenalised one', () {
      final state = learned(fsrs);
      final now = start.add(Duration(days: state.scheduledDays));

      final penalised = fsrs.review(state, Rating.hard, now);
      final unpenalised = neutral.review(learned(neutral), Rating.hard, now);

      expect(penalised.stability, lessThan(unpenalised.stability));
      expect(penalised.scheduledDays, lessThan(unpenalised.scheduledDays));
    });

    test('Easy lengthens it above the unbonused one', () {
      final state = learned(fsrs);
      final now = start.add(Duration(days: state.scheduledDays));

      final bonused = fsrs.review(state, Rating.easy, now);
      final unbonused = neutral.review(learned(neutral), Rating.easy, now);

      expect(bonused.stability, greaterThan(unbonused.stability));
      expect(bonused.scheduledDays, greaterThan(unbonused.scheduledDays));
    });

    test('and neither touches a Good or an Again', () {
      // They are multipliers on their own rating only. If `w16` leaked into
      // Good, every interval in the app would be three times too long.
      final state = learned(fsrs);
      final now = start.add(Duration(days: state.scheduledDays));

      for (final rating in <Rating>[Rating.again, Rating.good]) {
        expect(
          fsrs.review(state, rating, now).stability,
          closeTo(
            neutral.review(learned(neutral), rating, now).stability,
            1e-9,
          ),
          reason: rating.name,
        );
      }
    });
  });

  group('the dates', () {
    test('due is the scheduled number of days from today', () {
      final state = fsrs.review(const CardState(), Rating.good, start);
      final today = DateTime(
        start.toLocal().year,
        start.toLocal().month,
        start.toLocal().day,
      );

      expect(state.due, today.add(Duration(days: state.scheduledDays)));
    });

    test('due is a local midnight, not an instant', () {
      // `word_state.due` is a local date string and a study day is a local
      // day. An instant would put two cards of the same day on either side of
      // a boundary the learner cannot see.
      final state = fsrs.review(const CardState(), Rating.good, start);

      expect(state.due!.hour, 0);
      expect(state.due!.minute, 0);
      expect(state.due!.isUtc, isFalse);
    });

    test('a day added to a due date is a calendar day, not 24 hours', () {
      // `add(Duration(days: n))` adds absolute time, so a local midnight
      // drifts by an hour whenever the offset changes. This machine is in
      // `W. Europe`, where 2026-10-25 midnight plus one day lands at
      // 2026-10-25 23:00 — the day before. `word_state.due` is a date string,
      // so every card rated that day would be written as due today and come
      // back the same evening.
      //
      // Skipped where the machine has no DST: there is nothing to cross, and
      // a test that silently passes everywhere is worse than one that says
      // where it applies.
      final transitions = <DateTime>[
        for (var day = 0; day < 365; day++)
          if (DateTime(2026, 1, 1 + day).timeZoneOffset !=
              DateTime(2026, 1, 2 + day).timeZoneOffset)
            DateTime(2026, 1, 1 + day),
      ];
      if (transitions.isEmpty) {
        markTestSkipped('the local zone has no DST transition in 2026');
        return;
      }

      for (final eve in transitions) {
        final reviewed = fsrs.review(
          const CardState(),
          Rating.good,
          eve.add(const Duration(hours: 9)).toUtc(),
        );
        final expected = DateTime(
          eve.year,
          eve.month,
          eve.day + reviewed.scheduledDays,
        );

        expect(reviewed.due, expected, reason: 'reviewed on $eve');
        expect(reviewed.due!.hour, 0, reason: 'reviewed on $eve');
      }
    });

    test('a clock that moved backwards does not give a negative elapsed', () {
      // It happens: a timezone change, a manual clock set. A negative elapsed
      // would give a retrievability above 1 and a nonsense interval.
      final state = fsrs.review(const CardState(), Rating.good, start);
      final backwards = fsrs.review(
        state,
        Rating.good,
        start.subtract(const Duration(days: 5)),
      );

      expect(backwards.scheduledDays, greaterThan(0));
      expect(backwards.stability, greaterThan(0));
    });
  });

  group('the rating bar preview', () {
    test('is four intervals in Again/Hard/Good/Easy order', () {
      final preview = fsrs.preview(const CardState(), start);

      expect(preview, hasLength(4));
      expect(preview, <int>[1, 1, 4, 14]);
    });

    test('matches what rating that way actually schedules', () {
      // The preview is a promise. A learner who taps Good after reading "4 d"
      // and gets 6 has been lied to.
      final state = fsrs.review(const CardState(), Rating.good, start);
      final now = start.add(Duration(days: state.scheduledDays));

      final preview = fsrs.preview(state, now);
      for (final rating in Rating.values) {
        expect(
          fsrs.review(state, rating, now).scheduledDays,
          preview[rating.value - 1],
          reason: rating.name,
        );
      }
    });

    test('does not change the card', () {
      final state = fsrs.review(const CardState(), Rating.good, start);
      final before = state.toString();

      fsrs.preview(state, start);

      expect(state.toString(), before);
    });
  });

  group('the enums the database stores', () {
    test('ratings round-trip', () {
      for (final rating in Rating.values) {
        expect(Rating.parse(rating.value), rating);
      }
    });

    test('a rating outside BR-FSRS-02 is refused', () {
      expect(() => Rating.parse(0), throwsArgumentError);
      expect(() => Rating.parse(5), throwsArgumentError);
    });

    test('states round-trip', () {
      for (final state in FsrsState.values) {
        expect(FsrsState.parse(state.value), state);
      }
    });

    test('a state outside 0..3 is refused the same way a rating is', () {
      // `fsrs_state` has no CHECK constraint, so a restored backup or a later
      // migration can put anything in it. A bare `firstWhere` says only "No
      // element", which names neither the column nor the value.
      for (final value in <int>[-1, 4, 99]) {
        expect(
          () => FsrsState.parse(value),
          throwsArgumentError,
          reason: '$value',
        );
      }
    });
  });

  test('a wrong number of weights is refused', () {
    // Silently padding or truncating would schedule everything subtly wrong
    // with nothing on screen to say so.
    expect(() => Fsrs(weights: <double>[1, 2, 3]), throwsArgumentError);
    expect(Fsrs(weights: Fsrs.defaultWeights).weights, Fsrs.defaultWeights);
  });
}
