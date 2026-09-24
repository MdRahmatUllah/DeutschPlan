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
  /// learner with no active step). Nothing to undo when it was there already.
  Future<Undo> addToToday(
    String uid, {
    required String today,
    required String step,
  }) async {
    Expression<bool> row(PlanItems t) =>
        t.planDate.equals(today) &
        t.wordUid.equals(uid) &
        t.kind.equals(PlanKind.newWord.wire);
    final there = await (_db.select(
      _db.planItems,
    )..where(row)).getSingleOrNull();
    if (there != null) return () async {};
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

  /// FR-W1-02, BR-STATUS-04: a review rated Easy. A plan row still open for
  /// the word — today's, or the backlog's — closes with it, or the word it
  /// was just marked known would still be served as new.
  Future<Undo> markKnown(String uid, {required String today}) async {
    final open =
        await (_db.select(_db.planItems)
              ..where(
                (t) =>
                    t.wordUid.equals(uid) &
                    t.completedAt.isNull() &
                    t.planDate.isSmallerOrEqualValue(today),
              )
              ..orderBy(<OrderClauseGenerator<PlanItems>>[
                (t) => OrderingTerm.desc(t.planDate),
              ])
              ..limit(1))
            .getSingleOrNull();
    await _rating.markKnown(
      uid,
      planDate: open?.planDate,
      kind: switch (open?.kind) {
        null => null,
        'new' => PlanKind.newWord,
        _ => PlanKind.revise,
      },
    );
    return () async {
      await _rating.undo();
    };
  }

  /// FR-W1-02, BR-STATUS-03.
  Future<Undo> suspend(String uid) async {
    await _rating.suspend(uid);
    return () => _rating.resume(uid);
  }

  Future<Undo> resume(String uid) async {
    await _rating.resume(uid);
    return () => _rating.suspend(uid);
  }

  /// FR-W1-02 *Reset word*: its state and its plan rows from today on. Rows
  /// already done stay: they are the day's history. The review log stays
  /// too. *Undo* puts back exactly what went.
  Future<Undo> reset(String uid, {required String today}) =>
      _db.transaction(() async {
        Expression<bool> planned(PlanItems t) =>
            t.wordUid.equals(uid) &
            t.planDate.isBiggerOrEqualValue(today) &
            t.completedAt.isNull();
        final state = await (_db.select(
          _db.wordState,
        )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();
        final rows = await (_db.select(_db.planItems)..where(planned)).get();
        await (_db.delete(
          _db.wordState,
        )..where((t) => t.wordUid.equals(uid))).go();
        await (_db.delete(_db.planItems)..where(planned)).go();
        return () => _db.transaction(() async {
          if (state != null) {
            await _db.into(_db.wordState).insertOnConflictUpdate(state);
          }
          for (final row in rows) {
            await _db.into(_db.planItems).insertOnConflictUpdate(row);
          }
        });
      });

  /// FR-W1-03: the card the word's revisions show, plain or cloze.
  Future<Undo> setCardMode(String uid, CardMode mode) async {
    final before =
        (await (_db.select(
          _db.wordState,
        )..where((t) => t.wordUid.equals(uid))).getSingleOrNull())?.cardMode ??
        CardMode.plain.name;
    Future<void> write(String value) => _db
        .into(_db.wordState)
        .insertOnConflictUpdate(
          WordStateCompanion.insert(wordUid: uid, cardMode: Value(value)),
        );
    await write(mode.name);
    return () => write(before);
  }
}
