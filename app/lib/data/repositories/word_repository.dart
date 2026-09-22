import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

part 'word_repository.g.dart';

/// The four statuses `BR-STATUS-01` names.
///
/// Stored as text in `word_state.status`, with a CHECK that rejects anything
/// else — so this enum and the database agree by construction rather than by
/// convention.
enum WordStatus {
  /// Never introduced. A word with no `word_state` row at all is this.
  todo,

  /// Introduced, still being reviewed.
  learning,

  /// FSRS stability has reached `done_stability_days`. **Derived**
  /// (BR-STATUS-02) — a lapse moves it back to [learning].
  done,

  /// Paused by the learner. Excluded from everything (BR-STATUS-03), and the
  /// FSRS state is kept so resuming picks up where it left off.
  suspended;

  static WordStatus parse(String? value) => switch (value) {
    'learning' => WordStatus.learning,
    'done' => WordStatus.done,
    'suspended' => WordStatus.suspended,
    _ => WordStatus.todo,
  };

  String get wire => name;
}

/// A word and what the learner has done with it.
@immutable
class WordWithState {
  const WordWithState({
    required this.word,
    required this.state,
    required this.status,
  });

  final Word word;
  final WordStateData? state;

  /// Derived in SQL against the learner's `done_stability_days`, not read
  /// from `word_state.status` — that column is a cache, and a threshold the
  /// learner just moved would leave it a rating behind (BR-STATUS-02).
  final WordStatus status;

  String get uid => word.uid;

  bool get isSuspended => status == WordStatus.suspended;
}

/// Words, their state, and the transitions between statuses.
///
/// `docs/02-data/user-database.md` and `docs/04-screens/word-detail.md`.
///
/// Everything that reads for *learning* excludes suspended words. That is
/// BR-STATUS-03, and it is enforced in the SQL rather than by each caller
/// remembering — a plan that quietly included a suspended word would look like
/// the suspension never took.
///
/// **Every write goes through drift's API**, never `customStatement`. drift
/// works out which streams to re-emit from the tables a typed write touches;
/// a raw statement changes the same rows and tells it nothing, so Today and
/// the step list would keep showing the old numbers until something else
/// happened to invalidate them. That is the acceptance criterion about "no
/// manual invalidation", and it only holds if nothing writes behind drift's
/// back.
@DriftAccessor(include: <String>{'../db/word_queries.drift'})
class WordRepository extends DatabaseAccessor<AppDatabase>
    with _$WordRepositoryMixin {
  WordRepository(super.db, this._settings);

  final SettingsRepository _settings;

  /// `done_stability_days`, read on every query rather than cached.
  ///
  /// It is a Settings row the learner moves, and the derivation happens in
  /// SQL — so the value has to come from here each time or the lists would
  /// answer with the threshold that was current when this object was built.
  /// A double because it is compared against `stability`, which is REAL.
  double get _doneAfter =>
      _settings.read(SettingKeys.doneStabilityDays).toDouble();

  /// Every word of a step, suspended ones included — the Words tab shows them
  /// greyed rather than hiding them.
  Stream<List<WordWithState>> watchStep(String code) =>
      wordsWithStateForStep(_doneAfter, code).watch().map(
        (rows) => <WordWithState>[
          for (final row in rows)
            WordWithState(
              word: row.w,
              state: row.s,
              status: WordStatus.parse(row.derivedStatus),
            ),
        ],
      );

  /// The same step, ready to be learned from. BR-STATUS-03.
  Stream<List<WordWithState>> watchLearnableStep(String code) =>
      learnableWordsForStep(_doneAfter, code).watch().map(
        (rows) => <WordWithState>[
          for (final row in rows)
            WordWithState(
              word: row.w,
              state: row.s,
              status: WordStatus.parse(row.derivedStatus),
            ),
        ],
      );

  Stream<List<WordWithState>> watchCategory(int categoryId) =>
      wordsWithStateForCategory(_doneAfter, categoryId).watch().map(
        (rows) => <WordWithState>[
          for (final row in rows)
            WordWithState(
              word: row.w,
              state: row.s,
              status: WordStatus.parse(row.derivedStatus),
            ),
        ],
      );

  Stream<WordWithState?> watchWord(String uid) =>
      wordWithState(_doneAfter, uid).watch().map(
        (rows) => rows.isEmpty
            ? null
            : WordWithState(
                word: rows.single.w,
                state: rows.single.s,
                status: WordStatus.parse(rows.single.derivedStatus),
              ),
      );

  /// Everything due on or before [today], excluding suspended words.
  ///
  /// [today] is a local date string — `plan_items.plan_date` and
  /// `word_state.due` are local days, because a study day is a local day.
  Stream<List<WordWithState>> watchDue(String today) =>
      dueWords(_doneAfter, today).watch().map(
        (rows) => <WordWithState>[
          for (final row in rows)
            WordWithState(
              word: row.w,
              state: row.s,
              status: WordStatus.parse(row.derivedStatus),
            ),
        ],
      );

  Future<WordWithState?> find(String uid) async {
    final rows = await wordWithState(_doneAfter, uid).get();
    return rows.isEmpty
        ? null
        : WordWithState(
            word: rows.single.w,
            state: rows.single.s,
            status: WordStatus.parse(rows.single.derivedStatus),
          );
  }

  Stream<StatusCountsForStepResult> watchStatusCounts(String code) =>
      statusCountsForStep(_doneAfter, code).watchSingle();

  /// Suspends a word. Its FSRS state is untouched (BR-STATUS-03).
  Future<void> suspend(String uid) => _setStatus(uid, WordStatus.suspended);

  /// Resumes a suspended word.
  ///
  /// The status it goes back to is derived, not remembered: a word with
  /// stability past the threshold is `done`, one that has been reviewed is
  /// `learning`, and one that never was is `todo`. Storing the old status
  /// would let it come back as `done` after the threshold had been lowered.
  Future<void> resume(String uid) async {
    final state = await (select(
      db.wordState,
    )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();
    if (state == null) return;

    // `derivedStatus`, not `statusFor`: the latter answers "suspended" for a
    // suspended row, which is correct everywhere except here — resuming would
    // then set it back to suspended and nothing would ever come out of it.
    await _setStatus(uid, derivedStatus(state));
  }

  /// BR-STATUS-02: `done` is derived from stability, never set by hand.
  ///
  /// Read from settings on every call rather than cached, because
  /// `done_stability_days` is a Settings row the learner can move — and when
  /// they do, every word's status has to follow without a rebuild.
  WordStatus statusFor(WordStateData state) =>
      state.status == WordStatus.suspended.wire
      ? WordStatus.suspended
      : derivedStatus(state);

  /// What the FSRS state alone says, ignoring any suspension.
  ///
  /// This is the derivation BR-STATUS-02 describes. It is separate from
  /// [statusFor] because resuming needs the answer a suspended row would have
  /// had — asking [statusFor] there returns `suspended` and the word can never
  /// come back.
  WordStatus derivedStatus(WordStateData state) {
    // Introduced is what decides, not reviewed: `introduce()` writes the date
    // and leaves reps at 0, and reading that as never-met would put the word
    // back to `todo` on the next refresh and offer it as new again.
    if (state.introducedOn == null && state.reps == 0) return WordStatus.todo;

    final threshold = _settings.read(SettingKeys.doneStabilityDays);
    return state.stability >= threshold ? WordStatus.done : WordStatus.learning;
  }

  /// Recomputes and stores the derived status for one word.
  ///
  /// Called after every rating. The stored column is a cache of the
  /// derivation, kept because the status chip is drawn in a list and a
  /// per-row computation would mean reading settings once per row.
  Future<WordStatus> refreshStatus(String uid) async {
    final state = await (select(
      db.wordState,
    )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();
    if (state == null) return WordStatus.todo;

    final status = statusFor(state);
    if (status.wire != state.status) await _setStatus(uid, status);
    return status;
  }

  /// Upsert, not update: a word at `todo` has no `word_state` row at all, and
  /// `word-detail.md` offers *Suspend* on exactly those. An UPDATE would match
  /// nothing, the chip would flip, and the next read would say `todo` again.
  Future<void> _setStatus(String uid, WordStatus status) async {
    await into(db.wordState).insertOnConflictUpdate(
      WordStateCompanion.insert(wordUid: uid, status: Value(status.wire)),
    );
  }

  /// Creates the state row a word gets when it is first introduced.
  ///
  /// `introduced_on` is a local date: "the day I met this word" is a local
  /// day, and it is what the streak and the stats read.
  Future<void> introduce(String uid, {required String today}) async {
    await into(db.wordState).insert(
      WordStateCompanion.insert(
        wordUid: uid,
        status: const Value('learning'),
        introducedOn: Value(today),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
