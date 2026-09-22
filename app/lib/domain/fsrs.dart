/// FSRS-4.5, day-granular and dependency-free. `docs/03-domain/fsrs-scheduler.md`.
///
/// Plain Dart: no Flutter, no drift. `PlanRepository` and `GrammarRepository`
/// both hand a `CardState` in and store what comes out, which is why the
/// scheduling maths lives nowhere near the database.
///
/// Day-granular on purpose. A study day is a local day, `word_state.due` is a
/// date string, and an interval measured in hours would put two cards of the
/// same day on either side of a boundary the learner cannot see.
library;

import 'dart:math' as math;

/// BR-FSRS-02: 1 Again · 2 Hard · 3 Good · 4 Easy.
enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);

  /// What `review_log.rating` stores, and the index into the first four
  /// weights.
  final int value;

  static Rating parse(int value) => switch (value) {
    1 => Rating.again,
    2 => Rating.hard,
    3 => Rating.good,
    4 => Rating.easy,
    _ => throw ArgumentError.value(value, 'rating', 'BR-FSRS-02 allows 1..4'),
  };
}

/// Where a card is in its life. Stored as `word_state.fsrs_state`.
enum FsrsState {
  /// Never reviewed.
  fresh(0),

  /// Reviewed at least once and being learned.
  learning(1),

  /// Scheduled at intervals.
  review(2),

  /// Lapsed and being relearned.
  relearning(3);

  const FsrsState(this.value);

  final int value;

  static FsrsState parse(int value) => FsrsState.values.firstWhere(
    (state) => state.value == value,
    // `firstWhere` throws a bare "No element" otherwise, which names neither
    // the column nor the value. `fsrs_state` has no CHECK constraint, so a
    // restored backup or a later migration can put anything in it.
    orElse: () =>
        throw ArgumentError.value(value, 'fsrs_state', 'expects 0..3'),
  );
}

/// A card's scheduling, as `word_state` and `grammar_state` store it.
class CardState {
  const CardState({
    this.stability = 0,
    this.difficulty = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = FsrsState.fresh,
    this.lastReview,
    this.due,
    this.scheduledDays = 0,
  });

  /// Days at which recall probability falls to 90 %. Zero on a fresh card.
  final double stability;

  /// 1…10. How hard this card is for this learner.
  final double difficulty;

  final int reps;
  final int lapses;
  final FsrsState state;

  /// UTC instant of the last review, or null on a fresh card.
  final DateTime? lastReview;

  /// The local day it is next due, or null on a fresh card.
  final DateTime? due;

  /// The interval that produced [due]. The rating bar's preview is four of
  /// these, one per rating.
  final int scheduledDays;

  bool get isFresh => state == FsrsState.fresh;

  @override
  String toString() =>
      'CardState(S: ${stability.toStringAsFixed(4)}, '
      'D: ${difficulty.toStringAsFixed(4)}, reps: $reps, lapses: $lapses, '
      '${state.name}, +$scheduledDays d)';
}

/// The scheduler.
class Fsrs {
  Fsrs({List<double>? weights, double desiredRetention = defaultRetention})
    : weights = weights ?? defaultWeights,
      desiredRetention = desiredRetention.clamp(minRetention, maxRetention) {
    if (this.weights.length != defaultWeights.length) {
      throw ArgumentError.value(
        weights,
        'weights',
        'FSRS-4.5 takes ${defaultWeights.length} weights',
      );
    }
  }

  /// The published FSRS-4.5 defaults (BR-FSRS-01).
  ///
  /// These are the set that reproduces the first-review intervals
  /// `fsrs-scheduler.md` gives — 1 / 1 / 4 / 14 days at 90 % — which is what
  /// identifies them: the other published sets give 1/1/4/11 and 1/1/2/6.
  static const List<double> defaultWeights = <double>[
    0.4872, // w0  initial stability, Again
    1.4003, // w1  initial stability, Hard
    3.7145, // w2  initial stability, Good
    13.8206, // w3  initial stability, Easy
    5.1618, // w4  initial difficulty
    1.2298, // w5  initial difficulty slope
    0.8975, // w6  difficulty step per rating
    0.0310, // w7  mean reversion towards the Easy difficulty
    1.6474, // w8  stability growth
    0.1367, // w9  stability saturation
    1.0461, // w10 retrievability sensitivity
    2.1072, // w11 lapse: stability scale
    0.0793, // w12 lapse: difficulty exponent
    0.3246, // w13 lapse: stability exponent
    1.5870, // w14 lapse: retrievability sensitivity
    0.2272, // w15 hard penalty
    2.8755, // w16 easy bonus
  ];

  /// BR-FSRS-01: default 0.90, settable 0.80–0.97.
  static const double defaultRetention = 0.90;
  static const double minRetention = 0.80;
  static const double maxRetention = 0.97;

  /// `19/81`, the constant in FSRS-4.5's forgetting curve.
  ///
  /// It is what makes `intervalDays(S) == S` at 90 %: the factor and the
  /// `R^-2 - 1` term cancel exactly there, which is the arithmetic behind
  /// `intervalDays(10) == 10` in the spec.
  static const double factor = 19 / 81;

  /// The longest interval anyone is scheduled, in days. A hundred years.
  static const int maxInterval = 36500;

  final List<double> weights;

  /// Clamped in the constructor, so a setting outside the range is corrected
  /// rather than rejected — a stored 0.5 from an older build should still
  /// schedule something sensible.
  final double desiredRetention;

  /// Probability of recall [elapsedDays] after a review of a card with this
  /// [stability].
  ///
  /// `(1 + 19/81 · t/S)^(-0.5)`.
  double retrievability(num elapsedDays, double stability) {
    if (stability <= 0) return 0;

    // `pow` of a negative base to -0.5 is NaN, and NaN compares false against
    // everything — a clock that moved backwards would scramble BR-PLAN-03's
    // "lowest retrievability first" sort rather than failing. Nothing recalls
    // worse than perfectly at the moment of review, so zero is the floor.
    if (elapsedDays <= 0) return 1;

    return math.pow(1 + factor * elapsedDays / stability, -0.5).toDouble();
  }

  /// Days until recall falls to [desiredRetention].
  ///
  /// `S / (19/81) · (R^(-2) − 1)`, clamped 1…36500 — a card is never due
  /// today-and-also-yesterday, and never a thousand years out.
  int intervalDays(double stability) {
    if (stability <= 0) return 1;
    final raw =
        stability / factor * (math.pow(desiredRetention, -2).toDouble() - 1);
    return raw.round().clamp(1, maxInterval);
  }

  /// The four intervals the rating bar previews, in Again/Hard/Good/Easy
  /// order. `fsrs-scheduler.md`: computed on reveal, one `review` per rating.
  List<int> preview(CardState state, DateTime now) => <int>[
    for (final rating in Rating.values)
      review(state, rating, now).scheduledDays,
  ];

  /// Schedules [state] after a rating at [now].
  ///
  /// [now] is a UTC instant; the returned `due` is a local day, because
  /// `word_state.due` is a local date string and a study day is a local day.
  CardState review(CardState state, Rating rating, DateTime now) {
    final elapsed = state.isFresh || state.lastReview == null
        ? 0
        : _daysBetween(state.lastReview!, now);

    final (stability, difficulty) = state.isFresh
        ? _first(rating)
        : _later(state, rating, elapsed);

    // An Again on a first review comes out at one day without a special case:
    // `w0` is small enough that the interval rounds to zero and the clamp in
    // `intervalDays` lifts it, at every retention in the 0.80–0.97 range. I
    // wrote the special case first, then found it never fired.
    final scheduled = intervalDays(stability);

    return CardState(
      stability: stability,
      difficulty: difficulty,
      reps: state.reps + 1,
      lapses: state.lapses + (rating == Rating.again && !state.isFresh ? 1 : 0),
      state: switch (rating) {
        Rating.again => FsrsState.relearning,
        _ => state.isFresh ? FsrsState.learning : FsrsState.review,
      },
      lastReview: now,
      due: _addDays(_startOfDay(now.toLocal()), scheduled),
      scheduledDays: scheduled,
    );
  }

  /// First review: `S = w[rating-1]`, `D = clamp(w4 − (rating−3)·w5, 1, 10)`.
  (double, double) _first(Rating rating) =>
      (weights[rating.value - 1], _initialDifficulty(rating));

  double _initialDifficulty(Rating rating) =>
      (weights[4] - (rating.value - 3) * weights[5]).clamp(1.0, 10.0);

  (double, double) _later(CardState state, Rating rating, int elapsed) {
    final recall = retrievability(elapsed, state.stability);
    final difficulty = _nextDifficulty(state.difficulty, rating);

    final stability = rating == Rating.again
        ? _lapsed(state.stability, difficulty, recall)
        : _recalled(state.stability, difficulty, recall, rating);

    return (stability, difficulty);
  }

  /// Difficulty drifts by the rating, then reverts towards the difficulty an
  /// Easy first review would have given (`w7`).
  ///
  /// Without the reversion a card the learner keeps failing ratchets to 10 and
  /// stays there even once they have learned it.
  double _nextDifficulty(double difficulty, Rating rating) {
    final stepped = difficulty - weights[6] * (rating.value - 3);
    final reverted =
        weights[7] * _initialDifficulty(Rating.easy) +
        (1 - weights[7]) * stepped;
    return reverted.clamp(1.0, 10.0);
  }

  /// Stability after a successful recall.
  double _recalled(
    double stability,
    double difficulty,
    double recall,
    Rating rating,
  ) {
    final hard = rating == Rating.hard ? weights[15] : 1.0;
    final easy = rating == Rating.easy ? weights[16] : 1.0;

    final growth =
        math.exp(weights[8]) *
        (11 - difficulty) *
        math.pow(stability, -weights[9]).toDouble() *
        (math.exp((1 - recall) * weights[10]) - 1) *
        hard *
        easy;

    return stability * (1 + growth);
  }

  /// Stability after a lapse. Never above the stability it had — a card the
  /// learner just forgot has not become easier.
  double _lapsed(double stability, double difficulty, double recall) {
    final lapsed =
        weights[11] *
        math.pow(difficulty, -weights[12]).toDouble() *
        (math.pow(stability + 1, weights[13]).toDouble() - 1) *
        math.exp((1 - recall) * weights[14]);

    return math.min(lapsed, stability);
  }

  /// Whole days between two instants, floored and never negative.
  ///
  /// Floored because a review taken a few hours early is the same study day,
  /// and never negative because a learner whose clock moves backwards would
  /// otherwise get a negative elapsed time and a nonsense retrievability.
  static int _daysBetween(DateTime from, DateTime to) {
    final days = to.difference(from).inDays;
    return days < 0 ? 0 : days;
  }

  static DateTime _startOfDay(DateTime local) =>
      DateTime(local.year, local.month, local.day);

  /// Adds whole calendar days to a local midnight.
  ///
  /// Not `add(Duration(days: n))`: that adds absolute time, so a local
  /// midnight plus a day drifts by an hour whenever the offset changes. In
  /// `W. Europe`, 2026-10-25 midnight plus one day comes out at 2026-10-25
  /// 23:00 — the day before. `word_state.due` is a date string, so every card
  /// rated that day would be written as due today and come back the same
  /// evening. `DateTime` normalises an overflowing day field instead.
  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);
}
