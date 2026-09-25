import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:drift/drift.dart';

/// [PlanStore] over drift — the engine's half of `plan_items` and friends.
///
/// The engine decides; this fetches and writes. Nothing here chooses anything:
/// there is no ordering rule, no limit and no date arithmetic in this file
/// beyond what SQL needs, because every one of those is a business rule and
/// business rules live in `domain/` where they can be tested without a
/// database. The one exception is noted on [revisionCandidates].
class DriftPlanStore implements PlanStore {
  DriftPlanStore(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  @override
  Future<ActiveStep?> activeStep() async {
    final row =
        await (_db.select(_db.enrollments)
              ..where((e) => e.completedOn.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;

    return ActiveStep(
      sublevelCode: row.sublevelCode,
      startedOn: row.startedOn,
      dailyNew: row.dailyNew,
      studyDaysMask: row.studyDaysMask,
    );
  }

  /// The next To-do words of a step in teaching order, never planned before.
  ///
  /// `seq_in_sublevel` is the teaching order (`content-model.md`), and the
  /// `NOT EXISTS` is what stops a word being planned twice — the backlog is
  /// made of plan rows, so a word already sitting in it must not come round
  /// again as new.
  ///
  /// Suspended words are excluded: BR-STATUS-03 says a suspended word is out
  /// of plans until it is resumed, and that has to include never having been
  /// introduced.
  @override
  Future<List<String>> unplannedWords(
    String sublevelCode, {
    required int limit,
  }) async {
    if (limit <= 0) return const <String>[];

    final rows = await _db
        .customSelect(
          '''
SELECT w.uid AS uid
FROM words w
LEFT JOIN word_state s ON s.word_uid = w.uid
WHERE w.sublevel_code = ?1
  AND COALESCE(s.status, 'todo') = 'todo'
  AND NOT EXISTS (
    SELECT 1 FROM plan_items p WHERE p.word_uid = w.uid AND p.kind = 'new'
  )
ORDER BY w.seq_in_sublevel
LIMIT ?2
''',
          variables: <Variable<Object>>[
            Variable<String>(sublevelCode),
            Variable<int>(limit),
          ],
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.words,
            _db.wordState,
            _db.planItems,
          },
        )
        .get();

    return <String>[for (final row in rows) row.read<String>('uid')];
  }

  /// Every word the learner has met and not suspended.
  ///
  /// No ordering and no limit: the engine ranks these with the same
  /// retrievability formula the scheduler uses, and doing it in SQL would mean
  /// a second copy of the forgetting curve that could drift from the first.
  /// At course scale this is a few thousand rows of four columns.
  ///
  /// `last_review` is stored as a UTC instant and the engine works in local
  /// days, so it becomes its local date here — the one piece of shaping in
  /// this file. Not `substr(…, 1, 10)`: that is the UTC date, a day off for
  /// a review east of Greenwich before its UTC midnight (#327).
  ///
  /// A word of the learner's own added to revision (#363) is due before it
  /// has been reviewed, so its due date stands in for the review it hasn't
  /// had. Due, it is ranked by that and never by retrievability. One whose
  /// word was deleted is not a candidate: a rating from a card still open can
  /// write its state again, and it would come back as a blank card forever.
  @override
  Future<List<RevisionCandidate>> revisionCandidates() async {
    final rows = await _db
        .customSelect(
          '''
SELECT word_uid AS uid, stability, due, last_review
FROM word_state
WHERE status IN ('learning', 'done')
  AND (last_review IS NOT NULL OR due IS NOT NULL)
  AND (word_uid NOT LIKE 'custom:%'
       OR EXISTS (SELECT 1 FROM custom_words c
                  WHERE 'custom:' || c.id = word_uid))
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.wordState,
            _db.customWords,
          },
        )
        .get();

    return <RevisionCandidate>[
      for (final row in rows)
        RevisionCandidate(
          uid: row.read<String>('uid'),
          stability: row.read<double>('stability'),
          lastReview: switch (row.read<String?>('last_review')) {
            final at? => planDate(DateTime.parse(at).toLocal()),
            null => row.read<String>('due'),
          },
          due: row.read<String?>('due'),
        ),
    ];
  }

  /// In the order the engine planned them.
  ///
  /// `ORDER BY rowid` is the insertion order, and insertion order is the
  /// answer for both kinds: new words were written in teaching order and
  /// revisions in BR-PLAN-03's priority. Without it the order is whatever the
  /// query plan happens to give — which is the same thing today, and would
  /// stop being so after an index change or a VACUUM, with no test to say so.
  ///
  /// Not `seq_in_sublevel`: that is right for new words and would destroy the
  /// revise priority.
  @override
  Future<List<String>> plannedOn(PlanDate date, PlanKind kind) async {
    final rows = await _db
        .customSelect(
          '''
SELECT word_uid AS uid
FROM plan_items
WHERE plan_date = ?1 AND kind = ?2
ORDER BY rowid
''',
          variables: <Variable<Object>>[
            Variable<String>(date),
            Variable<String>(kind.wire),
          ],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .get();

    return <String>[for (final row in rows) row.read<String>('uid')];
  }

  /// Topics whose FSRS due has arrived (BR-PLAN-02, BR-FSRS-05).
  ///
  /// Suspended ones are left out, the same as suspended words: BR-STATUS-03
  /// says a suspended item is out of plans until it is resumed, and grammar
  /// runs on the same scheduler and the same statuses.
  ///
  /// `due IS NOT NULL` is explicit rather than load-bearing: SQLite compares
  /// `NULL <= '2026-03-02'` to NULL, which is not true, so an unscheduled
  /// topic is excluded either way. I checked by deleting the clause and
  /// watching the test still pass. It stays because the alternative is a
  /// reader having to know that rule to see that the query is right.
  @override
  Future<List<String>> grammarDueOn(PlanDate date) async {
    final rows = await _db
        .customSelect(
          '''
SELECT grammar_uid AS uid
FROM grammar_state
WHERE due IS NOT NULL AND due <= ?1 AND status != 'suspended'
ORDER BY due, grammar_uid
''',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.grammarState,
          },
        )
        .get();

    return <String>[for (final row in rows) row.read<String>('uid')];
  }

  /// Adds plan rows in one transaction.
  ///
  /// `insertOnConflictUpdate` would overwrite `completed_at`, so this ignores
  /// a row that is already there: reopening a day must not un-complete what
  /// the learner has already done.
  ///
  /// `sublevel_code` comes from the word rather than the enrollment, so a
  /// revise row carries the step the word belongs to and not the step the
  /// learner happens to be on. A word of the learner's own (`custom:<id>`,
  /// #363) belongs to none, and takes the step being studied, or the last one
  /// started once none is: revision goes on after a step is finished.
  @override
  Future<void> addToPlan(
    PlanDate date,
    PlanKind kind,
    List<String> uids,
  ) async {
    if (uids.isEmpty) return;

    await _db.transaction(() async {
      for (final uid in uids) {
        await _db.customInsert(
          '''
INSERT OR IGNORE INTO plan_items (plan_date, word_uid, kind, sublevel_code)
SELECT ?1, ?2, ?3, code FROM (
  SELECT COALESCE(
    (SELECT w.sublevel_code FROM words w WHERE w.uid = ?2),
    (SELECT e.sublevel_code FROM enrollments e WHERE ?2 LIKE 'custom:%'
      ORDER BY e.completed_on IS NULL DESC, e.started_on DESC LIMIT 1)
  ) AS code
) WHERE code IS NOT NULL
''',
          variables: <Variable<Object>>[
            Variable<String>(date),
            Variable<String>(uid),
            Variable<String>(kind.wire),
          ],
          updates: <TableInfo<Table, Object>>{_db.planItems},
        );
      }
    });
  }

  /// The backlog (BR-PLAN-05): open `new` rows from before [today].
  ///
  /// Newest day first, because Today shows the most recent missed day at the
  /// top. Skipped rows stay in it — BR-PLAN-06 says a skip leaves the word
  /// uncompleted, and `skipped` is there to stop it being offered again in the
  /// same session, not to remove it.
  @override
  Future<List<String>> backlogBefore(PlanDate today) async {
    final rows = await _db
        .customSelect(
          '''
SELECT word_uid AS uid
FROM plan_items
WHERE kind = 'new' AND completed_at IS NULL AND plan_date < ?1
ORDER BY plan_date DESC, word_uid
''',
          variables: <Variable<Object>>[Variable<String>(today)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .get();

    return <String>[for (final row in rows) row.read<String>('uid')];
  }

  /// `last_planned_date` is stored as a `DateTime`, and the engine works in
  /// `YYYY-MM-DD` strings. Converted here rather than widening the setting: the
  /// setting is shared, and a second representation of a date in the settings
  /// table is a second thing to keep in step.
  @override
  Future<PlanDate?> lastPlannedDate() async {
    final stored = _settings.read(SettingKeys.lastPlannedDate);
    return stored == null ? null : planDate(stored);
  }

  @override
  Future<void> setLastPlannedDate(PlanDate date) =>
      _settings.write(SettingKeys.lastPlannedDate, parsePlanDate(date));

  /// The step after [sublevelCode] in course order (BR-COURSE-05).
  ///
  /// Ordered by the level first and the sublevel second: `sublevels.ord` runs
  /// 1, 2, 3 *within* a level, so A2.1 has ord 1 just as A1.1 does. Ordering
  /// on it alone would loop back to the start of the course at every level
  /// boundary.
  @override
  Future<String?> stepAfter(String sublevelCode) async {
    final rows = await _db
        .customSelect(
          '''
SELECT s.code AS code
FROM sublevels s
JOIN levels l ON l.code = s.level_code
WHERE (l.ord, s.ord) > (
  SELECT l2.ord, s2.ord
  FROM sublevels s2 JOIN levels l2 ON l2.code = s2.level_code
  WHERE s2.code = ?1
)
ORDER BY l.ord, s.ord
LIMIT 1
''',
          variables: <Variable<Object>>[Variable<String>(sublevelCode)],
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.sublevels,
            _db.levels,
          },
        )
        .get();

    return rows.isEmpty ? null : rows.first.read<String>('code');
  }

  /// A `customUpdate` naming `enrollments`, not a `customStatement`: L1 and
  /// L2 watch the table, and a raw statement would leave them showing the
  /// old step (#114).
  @override
  Future<void> completeStep(String sublevelCode, PlanDate on) =>
      _db.customUpdate(
        'UPDATE enrollments SET completed_on = ?2 '
        'WHERE sublevel_code = ?1 AND completed_on IS NULL',
        variables: <Variable<Object>>[
          Variable<String>(sublevelCode),
          Variable<String>(on),
        ],
        updates: <TableInfo<Table, Object?>>{_db.enrollments},
      );

  /// Opens an enrollment.
  ///
  /// An upsert on the primary key, so coming back to a step the learner
  /// finished reopens that row rather than failing on it.
  ///
  /// **Not `INSERT OR REPLACE`.** That resolves a conflict by *deleting* the
  /// conflicting rows, and `idx_one_active_enrollment` is a unique index over
  /// the open row — so enrolling while another step was still open silently
  /// removed that step's row, taking its start date and its BR-PLAN-08 pace
  /// with it. `ON CONFLICT` touches only the row named here, which leaves the
  /// partial index free to refuse a second open enrollment out loud. That
  /// refusal is the point: a caller that skipped `completeStep` has a bug, and
  /// the database saying so beats it losing a row.
  @override
  Future<void> enroll(ActiveStep step) => _db.customUpdate(
    '''
INSERT INTO enrollments
  (sublevel_code, started_on, daily_new, study_days_mask, completed_on)
VALUES (?1, ?2, ?3, ?4, NULL)
ON CONFLICT(sublevel_code) DO UPDATE SET
  started_on      = excluded.started_on,
  daily_new       = excluded.daily_new,
  study_days_mask = excluded.study_days_mask,
  completed_on    = NULL
''',
    variables: <Variable<Object>>[
      Variable<String>(step.sublevelCode),
      Variable<String>(step.startedOn),
      Variable<int>(step.dailyNew),
      Variable<int>(step.studyDaysMask),
    ],
    updates: <TableInfo<Table, Object?>>{_db.enrollments},
  );

  @override
  Future<bool> hasEverEnrolled() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM enrollments')
        .getSingle();
    return row.read<int>('n') > 0;
  }

  /// Days with any activity, for the streak.
  ///
  /// `daily_stats` is the record of what actually happened, so a day appears
  /// here only if something was done on it — which is the question the streak
  /// asks. A row of all zeroes does not count: `_bumpDailyStats` can create one
  /// with a rating that is later undone.
  @override
  Future<Set<PlanDate>> activeDays(
    PlanDate today, {
    required int lookbackDays,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT day
FROM daily_stats
WHERE day <= ?1 AND day >= ?2
  AND (new_done > 0 OR reviews_done > 0 OR grammar_done > 0
       OR sentences_done > 0)
''',
          variables: <Variable<Object>>[
            Variable<String>(today),
            Variable<String>(addDays(today, -lookbackDays)),
          ],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.dailyStats},
        )
        .get();

    return <PlanDate>{for (final row in rows) row.read<String>('day')};
  }

  /// The schedule check's two counts, in one pass.
  ///
  /// Only `new` rows: a missed revision is not "behind", FSRS simply
  /// reschedules it. And only up to today — there is no plan beyond it to be
  /// measured against.
  @override
  Future<(int, int)> newItemProgress(PlanDate today) async {
    final row = await _db
        .customSelect(
          '''
SELECT COUNT(*) AS planned,
       COUNT(completed_at) AS introduced
FROM plan_items
WHERE kind = 'new' AND plan_date <= ?1
''',
          variables: <Variable<Object>>[Variable<String>(today)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .getSingle();

    return (row.read<int>('planned'), row.read<int>('introduced'));
  }

  /// BR-PLAN-10: a row is open until it is completed *or* skipped.
  @override
  Future<int> openPlanItems(PlanDate date) async {
    final row = await _db
        .customSelect(
          '''
SELECT COUNT(*) AS n
FROM plan_items
WHERE plan_date = ?1 AND completed_at IS NULL AND skipped = 0
''',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.planItems},
        )
        .getSingle();

    return row.read<int>('n');
  }

  /// BR-PLAN-09's measured timings.
  ///
  /// Nothing records seconds per item, so these come from the gaps between
  /// consecutive log entries — which is what the doc says ("from `review_log`
  /// timestamps"). `gapSeconds` throws away the gaps that are really breaks.
  ///
  /// New and revise are told apart by joining to the plan row for that day;
  /// a rating with no plan row — from Search, a quiz, an exam — has no block
  /// to belong to and is left out rather than guessed at.
  @override
  Future<MeasuredSeconds> measuredSeconds() async {
    final sessions = await _db
        .customSelect(
          '''
SELECT COUNT(*) AS n FROM daily_stats
WHERE new_done > 0 OR reviews_done > 0 OR grammar_done > 0
   OR sentences_done > 0
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.dailyStats},
        )
        .getSingle();

    return MeasuredSeconds(
      sessions: sessions.read<int>('n'),
      newWord: medianOf(await _wordGaps('new')),
      revision: medianOf(await _wordGaps('revise')),
      grammar: medianOf(await _grammarGaps()),
    );
  }

  /// The gaps between consecutive ratings of plan rows of one kind.
  ///
  /// `_gapsByDay` is what separates the days, not the ordering: the last review
  /// of Monday and the first of Tuesday must never produce a gap between them.
  /// That would be a break of hours, which `sessionGapLimit` would drop anyway,
  /// but relying on the limit to fix a wrong grouping is how a subtler version
  /// of it survives.
  ///
  /// The ordering is by timestamp alone. Adding `plan_date` to it changed
  /// nothing — the join derives it from the timestamp — and a clause that
  /// cannot matter reads as one that does.
  Future<List<int>> _wordGaps(String kind) async {
    final rows = await _db
        .customSelect(
          '''
SELECT r.reviewed_at AS at, p.plan_date AS day
FROM review_log r
JOIN plan_items p
  ON p.word_uid = r.word_uid
 AND p.kind = ?1
 AND p.plan_date = substr(r.reviewed_at, 1, 10)
ORDER BY r.reviewed_at
''',
          variables: <Variable<Object>>[Variable<String>(kind)],
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.reviewLog,
            _db.planItems,
          },
        )
        .get();

    return _gapsByDay(<(String, String)>[
      for (final row in rows) (row.read<String>('day'), row.read<String>('at')),
    ]);
  }

  Future<List<int>> _grammarGaps() async {
    final rows = await _db
        .customSelect(
          '''
SELECT practised_at AS at, substr(practised_at, 1, 10) AS day
FROM grammar_practice_log
ORDER BY practised_at
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.grammarPracticeLog,
          },
        )
        .get();

    return _gapsByDay(<(String, String)>[
      for (final row in rows) (row.read<String>('day'), row.read<String>('at')),
    ]);
  }

  /// Gaps taken within each day and then pooled.
  static List<int> _gapsByDay(List<(String day, String at)> rows) {
    final byDay = <String, List<DateTime>>{};
    for (final (day, at) in rows) {
      (byDay[day] ??= <DateTime>[]).add(DateTime.parse(at));
    }

    return <int>[for (final day in byDay.values) ...gapSeconds(day)];
  }

  /// The most recently closed enrollment.
  ///
  /// By `completed_on` and then `started_on`, so two steps closed on the same
  /// day — which happens when a catch-up run burns through a short step —
  /// still resolve to the later one.
  @override
  Future<String?> lastCompletedStep() async {
    final rows = await _db
        .customSelect(
          '''
SELECT sublevel_code AS code
FROM enrollments
WHERE completed_on IS NOT NULL
ORDER BY completed_on DESC, started_on DESC
LIMIT 1
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.enrollments},
        )
        .get();

    return rows.isEmpty ? null : rows.first.read<String>('code');
  }
}
