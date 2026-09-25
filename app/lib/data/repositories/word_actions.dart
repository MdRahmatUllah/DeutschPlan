import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:drift/drift.dart';

/// What undoes a W1 action (FR-W1-04): the snackbar's *Undo* calls it once.
typedef Undo = Future<void> Function();

/// W1's actions on one word (`word-detail.md`, FR-W1-01…03). Each returns
/// its own undo, so the sheet's snackbar can put the word back exactly.
class WordActions {
  WordActions(this._db, this._rating, this._plans);

  final AppDatabase _db;
  final RatingService _rating;
  final DriftPlanStore _plans;

  /// FR-W1-01: [uid] joins today's plan as a new word, in the active step's
  /// plan — any step's To-do word may ([step] is the word's own, for a
  /// learner with no active step).
  ///
  /// A word already planned and not yet studied keeps its one row: a backlog
  /// row moves to today, and back on *Undo*. A second open row would outlive
  /// the first being studied, and serve a learned word again.
  Future<Undo> addToToday(
    String uid, {
    required String today,
    required String step,
  }) async {
    final open =
        await (_db.select(_db.planItems)
              ..where(
                (t) =>
                    t.wordUid.equals(uid) &
                    t.kind.equals(PlanKind.newWord.wire) &
                    t.completedAt.isNull(),
              )
              ..orderBy(<OrderClauseGenerator<PlanItems>>[
                (t) => OrderingTerm.desc(t.planDate),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (open != null) {
      if (open.planDate == today && open.skipped == 0) return () async {};
      Future<void> move(String from, PlanItem to) =>
          (_db.update(_db.planItems)..where(
                (t) =>
                    t.planDate.equals(from) &
                    t.wordUid.equals(uid) &
                    t.kind.equals(PlanKind.newWord.wire),
              ))
              .write(to.toCompanion(false));
      await move(open.planDate, open.copyWith(planDate: today, skipped: 0));
      return () => move(today, open);
    }

    Expression<bool> row(PlanItems t) =>
        t.planDate.equals(today) &
        t.wordUid.equals(uid) &
        t.kind.equals(PlanKind.newWord.wire);
    await _db
        .into(_db.planItems)
        .insert(
          PlanItemsCompanion.insert(
            planDate: today,
            wordUid: uid,
            kind: PlanKind.newWord.wire,
            sublevelCode: (await _plans.activeStep())?.sublevelCode ?? step,
          ),
        );
    return () => (_db.delete(_db.planItems)..where(row)).go();
  }

  /// FR-W1-02, BR-STATUS-04: a review rated Easy. Every plan row still open
  /// for the word — today's, or the backlog's — closes with it, or the word
  /// just marked known would still be served. A skipped row stays skipped:
  /// the day it belongs to is already complete (BR-PLAN-10).
  Future<Undo> markKnown(String uid, {required String today}) async {
    final open =
        await (_db.select(_db.planItems)
              ..where(
                (t) =>
                    t.wordUid.equals(uid) &
                    t.completedAt.isNull() &
                    t.skipped.equals(0) &
                    t.planDate.isSmallerOrEqualValue(today),
              )
              ..orderBy(<OrderClauseGenerator<PlanItems>>[
                (t) => OrderingTerm.desc(t.planDate),
              ]))
            .get();
    final first = open.firstOrNull;
    // The newest goes with the rating, so the rating's undo reopens it; the
    // rest close at the same moment and reopen with it.
    await _rating.markKnown(
      uid,
      planDate: first?.planDate,
      kind: switch (first?.kind) {
        null => null,
        'new' => PlanKind.newWord,
        _ => PlanKind.revise,
      },
    );
    final rest = open.skip(1).toList();
    if (first != null && rest.isNotEmpty) {
      final closed = await (_db.select(
        _db.planItems,
      )..where((t) => _same(t, first))).getSingle();
      for (final row in rest) {
        await (_db.update(_db.planItems)..where((t) => _same(t, row))).write(
          PlanItemsCompanion(completedAt: Value(closed.completedAt)),
        );
      }
    }
    return () => _db.transaction(() async {
      await _rating.undo();
      for (final row in rest) {
        await _db
            .into(_db.planItems)
            .insertOnConflictUpdate(row.toCompanion(false));
      }
    });
  }

  /// FR-W1-02, BR-STATUS-03: a suspended word is out of every plan, so its
  /// open plan rows go with it (#351), today's and the backlog's. Otherwise
  /// Today would still count it and the session serve it. *Resume* doesn't
  /// bring them back; the plan picks the word up again as it would any other.
  /// *Undo* restores the rows and the state as they were, which for a word
  /// never met is no state row at all.
  Future<Undo> suspend(String uid) => _db.transaction(() async {
    Expression<bool> open(PlanItems t) =>
        t.wordUid.equals(uid) & t.completedAt.isNull();
    final before = await _stateOf(uid);
    final rows = await (_db.select(_db.planItems)..where(open)).get();
    await _rating.suspend(uid);
    await (_db.delete(_db.planItems)..where(open)).go();
    return () => _db.transaction(() async {
      await _restore(uid, before);
      for (final row in rows) {
        await _db
            .into(_db.planItems)
            .insertOnConflictUpdate(row.toCompanion(false));
      }
    });
  });

  Future<Undo> resume(String uid) async {
    final before = await _stateOf(uid);
    await _rating.resume(uid);
    return () => _restore(uid, before);
  }

  /// FR-W1-02 *Reset word*: its state, its open plan rows from today on, and
  /// every `new` row, done or not — a word with a `new` row is never planned
  /// again (`DriftPlanStore.unplannedWords`), and a reset word is To do
  /// again. Its done revisions stay, as the day's history, and so do
  /// `daily_stats` and the review log. *Undo* puts back exactly what went.
  Future<Undo> reset(String uid, {required String today}) =>
      _db.transaction(() async {
        Expression<bool> planned(PlanItems t) =>
            t.wordUid.equals(uid) &
            ((t.planDate.isBiggerOrEqualValue(today) & t.completedAt.isNull()) |
                t.kind.equals(PlanKind.newWord.wire));
        final state = await _stateOf(uid);
        final rows = await (_db.select(_db.planItems)..where(planned)).get();
        await (_db.delete(
          _db.wordState,
        )..where((t) => t.wordUid.equals(uid))).go();
        await (_db.delete(_db.planItems)..where(planned)).go();
        return () => _db.transaction(() async {
          await _restore(uid, state);
          for (final row in rows) {
            await _db
                .into(_db.planItems)
                .insertOnConflictUpdate(row.toCompanion(false));
          }
        });
      });

  /// FR-W1-03: the card the word's revisions show, plain or cloze. Marked as
  /// the learner's own, so BR-FSRS-06's rule keeps it from then on (#316).
  Future<Undo> setCardMode(String uid, CardMode mode) async {
    final before = await _stateOf(uid);
    await _db
        .into(_db.wordState)
        .insertOnConflictUpdate(
          WordStateCompanion.insert(
            wordUid: uid,
            cardMode: Value(mode.name),
            cardModeManual: const Value(1),
          ),
        );
    return () => _restore(uid, before);
  }

  // The rows go back as companions with their nulls kept: a data class
  // leaves a null column out of the update, so a reopened row would stay done.
  Future<WordStateData?> _stateOf(String uid) => (_db.select(
    _db.wordState,
  )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();

  Future<void> _restore(String uid, WordStateData? before) => before == null
      ? (_db.delete(_db.wordState)..where((t) => t.wordUid.equals(uid))).go()
      : _db
            .into(_db.wordState)
            .insertOnConflictUpdate(before.toCompanion(false));

  static Expression<bool> _same(PlanItems t, PlanItem row) =>
      t.planDate.equals(row.planDate) &
      t.wordUid.equals(row.wordUid) &
      t.kind.equals(row.kind);
}
