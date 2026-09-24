import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/plan_engine.dart' show PlanDate, planDate;
import 'package:deutschplan/domain/progress_stats.dart';
import 'package:drift/drift.dart';

/// M2's totals (`progress.md`).
typedef ProgressTotals = ({
  /// FR-M2-03: `daily_stats.seconds`, summed.
  int seconds,

  /// Words met at least once: as `WordRepository` tells To-do from the rest,
  /// a day it was introduced or a rating given — one rated from search or a
  /// quiz has no `introduced_on`.
  int introduced,

  /// Every rating ever given.
  int reviews,
});

/// What M2 reads: `daily_stats` for the bars and totals, `review_log` for
/// retention. Read-only.
class ProgressRepository {
  ProgressRepository(this._db);

  final AppDatabase _db;

  /// Each day's revisions and new words, oldest first.
  Future<List<DayCounts>> days() async {
    final rows = await _db
        .customSelect(
          'SELECT day, reviews_done, new_done FROM daily_stats ORDER BY day',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.dailyStats},
        )
        .get();
    return <DayCounts>[
      for (final row in rows)
        (
          day: row.read<String>('day'),
          reviews: row.read<int>('reviews_done'),
          newWords: row.read<int>('new_done'),
        ),
    ];
  }

  /// FR-M2-01's input: the ratings of revisions in the daily session, by the
  /// local day they were given. A revision is a card seen before — `elapsed_days`
  /// over zero; a new word's first rating is not one.
  ///
  /// The day is cut here, from the UTC instant to its local date, not with
  /// `substr` in SQL: that is the UTC date, a day off east of Greenwich
  /// before its midnight (#327).
  Future<Map<PlanDate, List<int>>> revisionRatings() async {
    final rows = await _db
        .customSelect(
          "SELECT reviewed_at, rating FROM review_log "
          "WHERE source = 'daily' AND elapsed_days > 0",
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.reviewLog},
        )
        .get();
    final byDay = <PlanDate, List<int>>{};
    for (final row in rows) {
      final day = planDate(
        DateTime.parse(row.read<String>('reviewed_at')).toLocal(),
      );
      (byDay[day] ??= <int>[]).add(row.read<int>('rating'));
    }
    return byDay;
  }

  Future<ProgressTotals> totals() async {
    final row = await _db
        .customSelect(
          '''
SELECT
  (SELECT COALESCE(SUM(seconds), 0) FROM daily_stats) AS seconds,
  (SELECT COUNT(*) FROM word_state
    WHERE introduced_on IS NOT NULL OR reps > 0)
    AS introduced,
  (SELECT COUNT(*) FROM review_log) AS reviews
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.dailyStats,
            _db.wordState,
            _db.reviewLog,
          },
        )
        .getSingle();
    return (
      seconds: row.read<int>('seconds'),
      introduced: row.read<int>('introduced'),
      reviews: row.read<int>('reviews'),
    );
  }
}
