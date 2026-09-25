import 'dart:convert';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

/// What a rating does to a word's scheduling.
///
/// Computed by `domain/fsrs.dart` — pure Dart, no database — and handed here
/// to be written. The split is `project-structure.md`'s: the scheduling maths
/// is unit-testable without a database, and this file is only responsible for
/// making the write atomic.
@immutable
class ScheduledState {
  const ScheduledState({
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.fsrsState,
    required this.reps,
    required this.lapses,
    required this.status,
    required this.cardMode,
    required this.elapsedDays,
    required this.scheduledDays,
  });

  final double stability;
  final double difficulty;

  /// A local date, `YYYY-MM-DD`: a study day is a local day.
  final String due;

  final int fsrsState;
  final int reps;
  final int lapses;

  /// Derived from stability (BR-STATUS-02); the caller has the threshold.
  final String status;

  /// `plain` or `cloze` — BR-FSRS-06 switches after two consecutive ≥ Good.
  final String cardMode;

  final int elapsedDays;
  final int scheduledDays;
}

/// Where a rating came from, for the stats split.
///
/// The CHECK on `review_log.source` rejects anything else, so this enum and
/// the database cannot drift apart.
enum ReviewSource { daily, quiz, exam, search, known, sentence }

/// What a plan row is for.
enum PlanKind {
  newWord,
  revise;

  String get wire => this == PlanKind.newWord ? 'new' : 'revise';
}

/// One entry of the daily plan, as it goes into `plan_items`.
@immutable
class PlanEntry {
  const PlanEntry({
    required this.planDate,
    required this.wordUid,
    required this.kind,
    required this.sublevelCode,
  });

  final String planDate;
  final String wordUid;
  final PlanKind kind;
  final String sublevelCode;
}

/// The daily plan, the ratings that complete it, and undo.
///
/// `docs/03-domain/plan-engine.md` decides *what* goes in a plan; this decides
/// nothing. It owns the writes, and the reason it exists as its own object is
/// that each of them touches four or five tables and has to be all-or-nothing.
class PlanRepository {
  PlanRepository(this._db);

  final AppDatabase _db;

  /// `undo_stack` is trimmed to this many rows.
  ///
  /// `user-database.md` says twenty. It is a safety net for a misclick, not a
  /// history: keeping every rating would make the table the largest thing in
  /// the database within a month, and it is excluded from the export anyway.
  static const int undoDepth = 20;

  /// Writes a whole day's plan. One transaction, as the doc requires.
  ///
  /// Half a plan is worse than none: the learner would open Today, see four
  /// of seven new words, and there would be nothing to say the rest were
  /// missing.
  ///
  /// Rows already there are left alone, which is what makes `openDay`
  /// idempotent — reopening the app on the same day must not double the plan.
  Future<void> writePlan(List<PlanEntry> entries) => _db.transaction(() async {
    await _db.batch((batch) {
      batch.insertAll(_db.planItems, <PlanItemsCompanion>[
        for (final entry in entries)
          PlanItemsCompanion.insert(
            planDate: entry.planDate,
            wordUid: entry.wordUid,
            kind: entry.kind.wire,
            sublevelCode: entry.sublevelCode,
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  });

  /// Records one rating.
  ///
  /// Five tables in one transaction: the new scheduling, the log entry, the
  /// plan row it completes, the day's totals, and the undo entry. A rating
  /// that landed in three of them would leave the learner's streak and their
  /// word list disagreeing, with nothing to say which was right.
  ///
  /// The undo entry is pushed **inside** the transaction and carries the
  /// state as it was before — so if the transaction rolls back there is no
  /// undo for something that never happened.
  Future<void> rate({
    required String uid,
    required int rating,
    required ScheduledState next,
    required ReviewSource source,
    required String reviewedAt,
    required String today,
    String? planDate,
    PlanKind? kind,
    int seconds = 0,
  }) => _db.transaction(() async {
    final before = await (_db.select(
      _db.wordState,
    )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();

    await _db
        .into(_db.wordState)
        .insertOnConflictUpdate(
          WordStateCompanion.insert(
            wordUid: uid,
            status: Value(next.status),
            introducedOn: Value(before?.introducedOn ?? today),
            due: Value(next.due),
            stability: Value(next.stability),
            difficulty: Value(next.difficulty),
            reps: Value(next.reps),
            lapses: Value(next.lapses),
            fsrsState: Value(next.fsrsState),
            lastReview: Value(reviewedAt),
            cardMode: Value(next.cardMode),
            timesLogged: Value(before?.timesLogged ?? 0),
            note: Value(before?.note),
          ),
        );

    // insertReturning, so the undo entry can name the row by its key. A
    // (word_uid, reviewed_at) pair is not one: two ratings of the same word
    // at the same timestamp — a quiz rating a batch, a caller passing a date
    // rather than an instant — would both be deleted by one undo.
    final logged = await _db
        .into(_db.reviewLog)
        .insertReturning(
          ReviewLogCompanion.insert(
            wordUid: uid,
            reviewedAt: reviewedAt,
            rating: rating,
            source: source.name,
            elapsedDays: Value(next.elapsedDays),
            scheduledDays: Value(next.scheduledDays),
          ),
        );

    if (planDate != null && kind != null) {
      await (_db.update(_db.planItems)..where(
            (t) =>
                t.planDate.equals(planDate) &
                t.wordUid.equals(uid) &
                t.kind.equals(kind.wire),
          ))
          .write(
            PlanItemsCompanion(
              completedAt: Value(reviewedAt),
              // A rated row is not a skipped one, whatever happened
              // yesterday. The backlog filters on completed_at and would be
              // right either way, but anything reading `skipped` would say
              // "you skipped this" about a word that is done.
              skipped: const Value(0),
            ),
          );
    }

    await _bumpDailyStats(
      today,
      newDone: kind == PlanKind.newWord ? 1 : 0,
      reviewsDone: kind == PlanKind.newWord ? 0 : 1,
      seconds: seconds,
    );

    await _pushUndo(
      uid: uid,
      before: before,
      reviewedAt: reviewedAt,
      reviewLogId: logged.id,
      planDate: planDate,
      kind: kind,
      today: today,
      seconds: seconds,
    );
  });

  /// Undoes the most recent rating.
  ///
  /// Restores `word_state` exactly as it was — including *no row at all*, for
  /// a word rated for the first time — deletes the log entry, reopens the plan
  /// row and takes the day's totals back down. Atomically, because a half
  /// undo is a word whose schedule and history disagree.
  ///
  /// Returns the uid that was undone, or `null` when there is nothing to undo.
  Future<String?> undo() => _db.transaction(() async {
    final entry =
        await (_db.select(_db.undoStack)
              ..orderBy(<OrderClauseGenerator<UndoStack>>[
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (entry == null) return null;

    final payload = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
    final uid = payload['word_uid'] as String;
    final before = payload['word_state'] as Map<String, dynamic>?;

    if (before == null) {
      // The word had never been rated, so "before" is no row. Deleting is the
      // restore — leaving an empty row would make it `learning` for ever.
      await (_db.delete(
        _db.wordState,
      )..where((t) => t.wordUid.equals(uid))).go();
    } else {
      await _db
          .into(_db.wordState)
          .insertOnConflictUpdate(
            WordStateCompanion.insert(
              wordUid: uid,
              status: Value(before['status'] as String),
              introducedOn: Value(before['introduced_on'] as String?),
              due: Value(before['due'] as String?),
              stability: Value((before['stability'] as num).toDouble()),
              difficulty: Value((before['difficulty'] as num).toDouble()),
              reps: Value(before['reps'] as int),
              lapses: Value(before['lapses'] as int),
              fsrsState: Value(before['fsrs_state'] as int),
              lastReview: Value(before['last_review'] as String?),
              cardMode: Value(before['card_mode'] as String),
              timesLogged: Value(before['times_logged'] as int),
              note: Value(before['note'] as String?),
            ),
          );
    }

    await (_db.delete(
      _db.reviewLog,
    )..where((t) => t.id.equals(payload['review_log_id'] as int))).go();

    final planDate = payload['plan_date'] as String?;
    final kind = payload['kind'] as String?;
    if (planDate != null && kind != null) {
      await (_db.update(_db.planItems)..where(
            (t) =>
                t.planDate.equals(planDate) &
                t.wordUid.equals(uid) &
                t.kind.equals(kind),
          ))
          .write(const PlanItemsCompanion(completedAt: Value<String?>(null)));
    }

    await _bumpDailyStats(
      payload['day'] as String,
      newDone: kind == 'new' ? -1 : 0,
      reviewsDone: kind == 'new' ? 0 : -1,
      // The time goes back too. Without it, BR-PLAN-09's estimate — which is
      // derived from these seconds — drifts upward every time someone undoes.
      seconds: -(payload['seconds'] as int? ?? 0),
    );

    await (_db.delete(_db.undoStack)..where((t) => t.id.equals(entry.id))).go();
    return uid;
  });

  /// Marks a plan row skipped. It stays in the backlog rather than completing.
  /// [skipped] false takes it back — the skip's *Undo*.
  Future<void> skip({
    required String planDate,
    required String uid,
    required PlanKind kind,
    bool skipped = true,
  }) =>
      (_db.update(_db.planItems)..where(
            (t) =>
                t.planDate.equals(planDate) &
                t.wordUid.equals(uid) &
                t.kind.equals(kind.wire),
          ))
          .write(
            // 1, not true: the DDL says INTEGER, so drift types it as an int.
            // SQLite has no boolean, and declaring BOOLEAN here would be a
            // schema change for a column that already stores the same byte.
            PlanItemsCompanion(skipped: Value(skipped ? 1 : 0)),
          );

  /// Today's plan rows, in the order the session presents them.
  Stream<List<PlanItem>> watchPlan(String date) =>
      (_db.select(_db.planItems)
            ..where((t) => t.planDate.equals(date))
            ..orderBy(<OrderClauseGenerator<PlanItems>>[
              (t) => OrderingTerm.asc(t.kind),
              (t) => OrderingTerm.asc(t.wordUid),
            ]))
          .watch();

  /// The backlog: open `new` rows from before today, newest day first.
  ///
  /// BR-PLAN-05 — there is no backlog table, because an incomplete plan row
  /// *is* the backlog. A second table would be a second truth.
  ///
  /// A suspended word's row isn't counted (#368): the word is out of the plan
  /// (BR-STATUS-03), so Today's backlog card doesn't wait on it, as
  /// `DriftPlanStore.backlogBefore` doesn't.
  Stream<List<PlanItem>> watchBacklog(String today) => _watched(
    _withStates(today)..where(
      _db.wordState.status.isNull() |
          _db.wordState.status.equals('suspended').not(),
    ),
  );

  /// Every backlog row, the suspended words' too, and again when one of its
  /// words' state changes. T4 shows each word's status and studies only the
  /// unsuspended ones, and a word suspended from W1 over it keeps its row
  /// (#368).
  Stream<List<PlanItem>> watchBacklogWithStates(String today) =>
      _watched(_withStates(today));

  JoinedSelectStatement<HasResultSet, dynamic> _withStates(String today) =>
      _backlog(today).join(<Join<HasResultSet, dynamic>>[
        leftOuterJoin(
          _db.wordState,
          _db.wordState.wordUid.equalsExp(_db.planItems.wordUid),
        ),
      ]);

  Stream<List<PlanItem>> _watched(
    JoinedSelectStatement<HasResultSet, dynamic> query,
  ) => query.watch().map(
    (rows) => <PlanItem>[for (final row in rows) row.readTable(_db.planItems)],
  );

  /// [watchBacklog], once: what a backlog session starts from.
  Future<List<PlanItem>> backlog(String today) => _backlog(today).get();

  SimpleSelectStatement<PlanItems, PlanItem> _backlog(String today) =>
      _db.select(_db.planItems)
        ..where(
          (t) =>
              t.kind.equals(PlanKind.newWord.wire) &
              t.completedAt.isNull() &
              t.planDate.isSmallerThanValue(today),
        )
        ..orderBy(<OrderClauseGenerator<PlanItems>>[
          (t) => OrderingTerm.desc(t.planDate),
          (t) => OrderingTerm.asc(t.wordUid),
        ]);

  /// FR-T6-01: marks [day]'s T6 as shown, once. True for the call that
  /// marked it; false when the day had already had its T6.
  Future<bool> claimDayComplete(String day) async {
    final changed = await _db.customUpdate(
      'INSERT INTO daily_stats (day, completed_shown) VALUES (?1, 1) '
      'ON CONFLICT (day) DO UPDATE SET completed_shown = 1 '
      'WHERE completed_shown = 0',
      variables: <Variable<Object>>[Variable<String>(day)],
      updates: <TableInfo<Table, Object?>>{_db.dailyStats},
    );
    return changed > 0;
  }

  /// FR-T6-01: whether [day] has had its T6.
  Future<bool> dayCompleteShown(String day) async {
    final row = await _db
        .customSelect(
          'SELECT completed_shown FROM daily_stats WHERE day = ?1',
          variables: <Variable<Object>>[Variable<String>(day)],
        )
        .getSingleOrNull();
    return (row?.read<int>('completed_shown') ?? 0) == 1;
  }

  /// Completes a plan row without a rating: T4's *Remove from course*.
  /// [at] null opens it again — the *Undo*.
  Future<void> complete({
    required String planDate,
    required String uid,
    required PlanKind kind,
    required String? at,
  }) =>
      (_db.update(_db.planItems)..where(
            (t) =>
                t.planDate.equals(planDate) &
                t.wordUid.equals(uid) &
                t.kind.equals(kind.wire),
          ))
          .write(PlanItemsCompanion(completedAt: Value(at)));

  /// Whether the learner has started a step.
  ///
  /// The router's onboarding guard reads this (`navigation.md`:
  /// "/onboarding/* redirects to /today once enrolled"). It counts every
  /// enrollment, not just the open one — someone who has finished a step and
  /// not yet started the next is still not a new learner.
  /// The first and last day the backlog's words were planned for: T1's
  /// "14 waiting from Tue–Wed". Both null when the backlog is empty.
  Future<({String? from, String? to})> backlogDays(String today) async {
    final row = await _db
        .customSelect(
          '''
SELECT MIN(plan_date) AS first, MAX(plan_date) AS last
FROM plan_items
WHERE kind = 'new' AND completed_at IS NULL AND plan_date < ?1
''',
          variables: <Variable<Object>>[Variable<String>(today)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .getSingle();
    return (
      from: row.readNullable<String>('first'),
      to: row.readNullable<String>('last'),
    );
  }

  /// [date]'s plan rows that are neither done nor skipped, as `(kind, uid)`:
  /// what a session reopened after a crash still has to ask.
  Future<Set<(String, String)>> stillOpen(String date) async {
    final rows = await _db
        .customSelect(
          'SELECT kind, word_uid FROM plan_items '
          'WHERE plan_date = ?1 AND completed_at IS NULL AND skipped = 0',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .get();
    return <(String, String)>{
      for (final row in rows)
        (row.read<String>('kind'), row.read<String>('word_uid')),
    };
  }

  /// How many words are due on or before [date], suspended ones aside: the
  /// "12" of TodayRest's "12 → 6 revisions".
  Future<int> dueBy(String date) async {
    final row = await _db
        .customSelect(
          '''
SELECT COUNT(*) AS n FROM word_state
WHERE due IS NOT NULL AND due <= ?1 AND status != 'suspended'
''',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.wordState},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// The day the first step was started: T1's "Day 34 of your course".
  ///
  /// The earliest enrollment rather than the active one, because a new step is
  /// a new enrollment and the course did not restart with it.
  Future<String?> courseStartedOn() async {
    final row = await _db
        .customSelect(
          'SELECT MIN(started_on) AS started FROM enrollments',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.enrollments},
        )
        .getSingle();
    return row.readNullable<String>('started');
  }

  Future<bool> hasEnrollment() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM enrollments')
        .getSingle();
    return row.read<int>('n') > 0;
  }

  Future<DailyStat?> statsFor(String day) => (_db.select(
    _db.dailyStats,
  )..where((t) => t.day.equals(day))).getSingleOrNull();

  /// M1's activity: how many items were practised on each day, as it changes
  /// — the heat-map's cells (FR-M1-02) and the header's days studied.
  ///
  /// Every kind of item counts, the activity the streak counts
  /// (`PlanStore.activeDays`), so a day inside the streak never shows as
  /// empty. Days with nothing are left out.
  ///
  /// ponytail: every day ever, one row a day — a few hundred rows after a
  /// year of study. Bound it by date if it ever shows in a profile.
  Stream<Map<String, int>> watchActivity() => _db
      .select(_db.dailyStats)
      .watch()
      .map(
        (rows) => <String, int>{
          for (final row in rows)
            if (_items(row) > 0) row.day: _items(row),
        },
      );

  static int _items(DailyStat row) =>
      row.newDone + row.reviewsDone + row.grammarDone + row.sentencesDone;

  Future<int> undoDepthNow() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM undo_stack')
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> _bumpDailyStats(
    String day, {
    required int newDone,
    required int reviewsDone,
    required int seconds,
  }) async {
    // One statement rather than read-then-write: two ratings landing in the
    // same millisecond would otherwise each read the same total and one would
    // be lost.
    await _db.customStatement(
      'INSERT INTO daily_stats (day, new_done, reviews_done, seconds) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(day) DO UPDATE SET '
      'new_done = MAX(new_done + excluded.new_done, 0), '
      'reviews_done = MAX(reviews_done + excluded.reviews_done, 0), '
      'seconds = MAX(seconds + excluded.seconds, 0)',
      <Object?>[day, newDone, reviewsDone, seconds],
    );
    // A raw statement, so drift has to be told which streams to re-emit.
    _db.markTablesUpdated(<TableInfo<Table, Object?>>{_db.dailyStats});
  }

  Future<void> _pushUndo({
    required String uid,
    required WordStateData? before,
    required String reviewedAt,
    required int reviewLogId,
    required String? planDate,
    required PlanKind? kind,
    required String today,
    required int seconds,
  }) async {
    await _db
        .into(_db.undoStack)
        .insert(
          UndoStackCompanion.insert(
            createdAt: reviewedAt,
            payloadJson: jsonEncode(<String, Object?>{
              'word_uid': uid,
              'reviewed_at': reviewedAt,
              'review_log_id': reviewLogId,
              'seconds': seconds,
              'plan_date': planDate,
              'kind': kind?.wire,
              'day': today,
              'word_state': before == null
                  ? null
                  : <String, Object?>{
                      'status': before.status,
                      'introduced_on': before.introducedOn,
                      'due': before.due,
                      'stability': before.stability,
                      'difficulty': before.difficulty,
                      'reps': before.reps,
                      'lapses': before.lapses,
                      'fsrs_state': before.fsrsState,
                      'last_review': before.lastReview,
                      'card_mode': before.cardMode,
                      'times_logged': before.timesLogged,
                      'note': before.note,
                    },
            }),
          ),
        );

    // Trimmed here rather than on a schedule: the table is only ever written
    // by this method, so this is the one place it can grow.
    await _db.customStatement(
      'DELETE FROM undo_stack WHERE id NOT IN '
      '(SELECT id FROM undo_stack ORDER BY id DESC LIMIT ?)',
      <Object?>[undoDepth],
    );
    _db.markTablesUpdated(<TableInfo<Table, Object?>>{_db.undoStack});
  }
}
