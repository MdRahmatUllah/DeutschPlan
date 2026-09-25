import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:drift/drift.dart';

/// Rating a word: the piece between `domain/fsrs.dart` and `plan_items`.
///
/// `PlanRepository.rate` writes five tables atomically but is handed the new
/// scheduling; `Fsrs` computes the new scheduling but has never heard of a
/// database. This reads the row, runs the scheduler and derives the two things
/// that are *not* FSRS — the status (BR-STATUS-02) and the card format
/// (BR-FSRS-06) — then hands the result over.
///
/// One class rather than a method on `PlanRepository`, because those
/// derivations need settings and the review history, and putting them there
/// would give the repository opinions about business rules.
class RatingService {
  RatingService(this._db, this._settings, this._plan, this._words, this._now);

  final AppDatabase _db;
  final SettingsRepository _settings;
  final PlanRepository _plan;
  final WordRepository _words;

  /// The clock. `state-management.md`: a study day is a local day, and a
  /// second source of "now" means two answers to "is this due".
  final DateTime Function() _now;

  /// BR-FSRS-06: two consecutive Good or Easy switch the card to cloze.
  static const int clozeAfterConsecutive = 2;

  /// Records a rating (BR-FSRS-02).
  ///
  /// Runs FSRS over the word's current state, derives the new status and card
  /// format, and writes the lot in one transaction. [planDate] and [kind] mark
  /// the plan row complete when the rating came from the daily plan; a rating
  /// from Search or a quiz leaves them null and completes nothing.
  Future<void> rate(
    String uid,
    Rating rating, {
    required ReviewSource source,
    String? planDate,
    PlanKind? kind,
    int seconds = 0,
  }) async {
    final now = _now();
    final today = _today(now);

    final before = await _stateOf(uid);
    final next = _scheduler().review(_cardStateOf(before), rating, now.toUtc());

    await _plan.rate(
      uid: uid,
      rating: rating.value,
      next: ScheduledState(
        stability: next.stability,
        difficulty: next.difficulty,
        due: _dateOf(next.due!),
        fsrsState: next.state.value,
        reps: next.reps,
        lapses: next.lapses,
        // BR-STATUS-03: a rating never resumes a suspended word. The
        // schedule still moves, and *Resume* derives the status from it.
        status: before?.status == WordStatus.suspended.name
            ? WordStatus.suspended.name
            : _statusFor(next).name,
        cardMode: (await _cardModeFor(uid, rating)).name,
        elapsedDays: _elapsedDays(before, now),
        scheduledDays: next.scheduledDays,
      ),
      source: source,
      reviewedAt: now.toUtc().toIso8601String(),
      today: today,
      planDate: planDate,
      kind: kind,
      seconds: seconds,
    );
  }

  /// FR-T2-05: the days each rating would schedule [uid] for.
  ///
  /// The same row, scheduler and clock [rate] uses, so the interval under a
  /// button is the interval that button writes.
  Future<Map<Rating, int>> preview(String uid) async {
    final state = _cardStateOf(await _stateOf(uid));
    final scheduler = _scheduler();
    final now = _now().toUtc();
    return <Rating, int>{
      for (final rating in Rating.values)
        rating: scheduler.review(state, rating, now).scheduledDays,
    };
  }

  Future<WordStateData?> _stateOf(String uid) => (_db.select(
    _db.wordState,
  )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();

  Fsrs _scheduler() =>
      Fsrs(desiredRetention: _settings.read(SettingKeys.desiredRetention));

  /// BR-STATUS-04: "I know it" is a first review rated Easy.
  ///
  /// Logged with source `known` so the stats can tell a word the learner
  /// claimed from one they actually studied.
  ///
  /// Takes the plan row too, because the button is for a *new word* — which is
  /// a word sitting in today's plan. Without it the row stays open and the
  /// word turns up in tomorrow's backlog after the learner has just said they
  /// know it.
  Future<void> markKnown(String uid, {String? planDate, PlanKind? kind}) =>
      rate(
        uid,
        Rating.easy,
        source: ReviewSource.known,
        planDate: planDate,
        kind: kind,
      );

  /// BR-STATUS-03. The FSRS state is untouched: resuming picks up the
  /// schedule, it does not restart it.
  Future<void> suspend(String uid) => _words.suspend(uid);

  /// Puts the word back to whatever its stability says it is (BR-STATUS-02),
  /// not to whatever it was before it was suspended.
  Future<void> resume(String uid) => _words.resume(uid);

  /// Undoes the most recent rating, or returns null if there is nothing to
  /// undo.
  Future<String?> undo() => _plan.undo();

  /// The FSRS view of a stored row.
  ///
  /// A missing row is a fresh card — which is the right reading: a word with
  /// no `word_state` has never been reviewed.
  CardState _cardStateOf(WordStateData? row) {
    if (row == null || row.lastReview == null) return const CardState();

    return CardState(
      stability: row.stability,
      difficulty: row.difficulty,
      reps: row.reps,
      lapses: row.lapses,
      state: FsrsState.parse(row.fsrsState),
      lastReview: DateTime.parse(row.lastReview!),
      due: row.due == null ? null : DateTime.parse(row.due!),
      // Not stored: `word_state` has no `scheduled_days` column, and nothing
      // in `Fsrs.review` reads it back. It is an output, not an input.
      scheduledDays: 0,
    );
  }

  WordStatus _statusFor(CardState next) => statusForStability(
    next.stability,
    _settings.read(SettingKeys.doneStabilityDays),
  );

  /// BR-FSRS-06: cloze after two consecutive Good or Easy.
  ///
  /// Counts *this* rating plus the previous one, so the switch happens on the
  /// second, not the third. Anything below Good sends it back to plain — the
  /// rule is about a run, and a word the learner just failed is not one they
  /// are ready to produce from a gap.
  ///
  /// **It does not yet respect a manual switch.** BR-FSRS-06 also says the
  /// learner can put a cloze card back to plain from Word detail, and W1's
  /// card toggle (#141) writes `card_mode` by hand. This reads only the
  /// ratings and cannot tell that choice from a run-broken `plain`, so the
  /// choice lasts until the next review: set back to plain, a word goes cloze
  /// again on its next Good. Respecting it needs somewhere to record the
  /// choice, a schema change, which is #316.
  Future<CardMode> _cardModeFor(String uid, Rating rating) async {
    if (rating.value < Rating.good.value) return CardMode.plain;

    final recent = await _db
        .customSelect(
          '''
SELECT rating
FROM review_log
WHERE word_uid = ?1
ORDER BY reviewed_at DESC, id DESC
LIMIT ?2
''',
          variables: <Variable<Object>>[
            Variable<String>(uid),
            Variable<int>(clozeAfterConsecutive - 1),
          ],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.reviewLog},
        )
        .get();

    if (recent.length < clozeAfterConsecutive - 1) return CardMode.plain;

    final allGood = recent.every(
      (row) => row.read<int>('rating') >= Rating.good.value,
    );
    return allGood ? CardMode.cloze : CardMode.plain;
  }

  /// Whole days since the last review, for `review_log.elapsed_days`.
  ///
  /// Zero on a first review: nothing elapsed, because there was nothing to
  /// elapse from.
  int _elapsedDays(WordStateData? before, DateTime now) {
    final last = before?.lastReview;
    if (last == null) return 0;

    return elapsedDays(DateTime.parse(last), now);
  }

  /// A local date, `YYYY-MM-DD` — a study day is a local day.
  String _today(DateTime now) => planDate(now.toLocal());

  String _dateOf(DateTime day) => planDate(day);
}

/// BR-STATUS-02: `done` is derived from stability, never set by hand.
///
/// A lapse drops the stability, which is what moves a `done` word back to
/// `learning` — there is no separate rule for it, and that is the point of
/// deriving rather than storing.
///
/// Top-level and pure so the boundary can be tested. `>=`, not `>`, and the
/// difference is unreachable through the service: FSRS stabilities are
/// products of the weights and never land exactly on an integer threshold, so
/// planting `>` there changes nothing observable. The rule still says `>=`,
/// and this is where that can be held to.
WordStatus statusForStability(double stability, int doneStabilityDays) =>
    stability >= doneStabilityDays ? WordStatus.done : WordStatus.learning;

/// What `word_state.card_mode` stores (BR-FSRS-06).
enum CardMode { plain, cloze }

/// Rating a grammar topic (BR-FSRS-05): `domain/fsrs.dart` over
/// `grammar_state`, as [RatingService] is for words.
class GrammarRatingService {
  GrammarRatingService(this._grammar, this._settings, this._now);

  final GrammarRepository _grammar;
  final SettingsRepository _settings;
  final DateTime Function() _now;

  /// FR-L4-01: *Mark as learned* — a first review rated Good, so the topic
  /// enters the schedule as learning.
  Future<void> markLearned(String uid) async {
    final now = _now();
    final before = (await _grammar.find(uid))?.state;
    final next = Fsrs(
      desiredRetention: _settings.read(SettingKeys.desiredRetention),
    ).review(_cardStateOf(before), Rating.good, now.toUtc());
    await _grammar.schedule(
      uid: uid,
      stability: next.stability,
      difficulty: next.difficulty,
      due: planDate(next.due!),
      reps: next.reps,
      lapses: next.lapses,
      lastReview: now.toUtc().toIso8601String(),
    );
  }

  /// FR-L15-03: a finished run, rated as a whole (BR-FSRS-05: all right
  /// Good, one wrong Hard, more Again), scheduled and logged.
  Future<void> ratePractice(
    String uid, {
    required int items,
    required int correct,
  }) async {
    final now = _now();
    final result = PracticeResult(
      items: items,
      correct: correct,
      practisedAt: now.toUtc().toIso8601String(),
    );
    final before = (await _grammar.find(uid))?.state;
    final next = Fsrs(
      desiredRetention: _settings.read(SettingKeys.desiredRetention),
    ).review(_cardStateOf(before), Rating.parse(result.rating), now.toUtc());
    await _grammar.recordPractice(
      uid: uid,
      result: result,
      stability: next.stability,
      difficulty: next.difficulty,
      due: planDate(next.due!),
      reps: next.reps,
      lapses: next.lapses,
      today: planDate(now),
    );
  }

  /// The FSRS view of a topic's row. `grammar_state` keeps no FSRS state
  /// column: a topic reviewed before is in review, one never reviewed is
  /// fresh.
  CardState _cardStateOf(GrammarStateData? row) {
    if (row == null || row.lastReview == null) return const CardState();
    return CardState(
      stability: row.stability,
      difficulty: row.difficulty,
      reps: row.reps,
      lapses: row.lapses,
      state: FsrsState.review,
      lastReview: DateTime.parse(row.lastReview!),
      due: row.due == null ? null : DateTime.parse(row.due!),
    );
  }
}
