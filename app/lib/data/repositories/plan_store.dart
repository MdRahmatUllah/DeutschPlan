import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';
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
  /// `last_review` is stored as an instant and the engine works in local days,
  /// so it is cut to its date here — the one piece of shaping in this file.
  @override
  Future<List<RevisionCandidate>> revisionCandidates() async {
    final rows = await _db
        .customSelect(
          '''
SELECT word_uid AS uid, stability, due, substr(last_review, 1, 10) AS reviewed
FROM word_state
WHERE status IN ('learning', 'done')
  AND last_review IS NOT NULL
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.wordState},
        )
        .get();

    return <RevisionCandidate>[
      for (final row in rows)
        RevisionCandidate(
          uid: row.read<String>('uid'),
          stability: row.read<double>('stability'),
          lastReview: row.read<String>('reviewed'),
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
  /// learner happens to be on.
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
SELECT ?1, ?2, ?3, w.sublevel_code FROM words w WHERE w.uid = ?2
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
}
