// #818: a year of study, the profile `tools/perf.py --profile year`
// measures start and frames on. #708 showed Today's cost growing with the
// learner's history, which a fresh install can't show.
//
// S2's commit with its defaults (bar 30 revisions a day, as #708's simulated
// learner did), dated a year back, then the year itself in SQL: seven new
// words a day in teaching order and 30 revisions, each rated with its plan
// row, and a daily_stats row a day. About 13,500 ratings; the learner is in
// B1.2, with words still to learn. Today itself is left unplanned, as after
// any night: the app plans it on start.

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/setup_repository.dart';
import 'package:sogda/domain/plan_engine.dart' show planDate;
import 'package:sogda/features/onboarding/onboarding_notifier.dart';

/// The days studied, every one of them.
const int yearDays = 365;

/// `revise_count`: the cards revised a day, on top of `daily_new`'s seven.
const int yearReviseCount = 30;

/// Fills [db], which has the course attached as `c` and nothing studied, with
/// a year of study ending the day before [today].
Future<void> seedYear(AppDatabase db, {required DateTime today}) async {
  final start = planDate(
    DateTime(today.year, today.month, today.day - yearDays),
  );
  final settings = SettingsRepository(db);
  await settings.load();
  final choice = OnboardingDraft(reviseCount: yearReviseCount).choice;
  await SetupRepository(db, settings).commit(choice, today: start);

  // ?1 to ?4. SQLite takes exactly as many values as a statement's highest.
  final perDay = <Object>[start, yearDays, choice.dailyNew, yearReviseCount];
  await db.transaction(() async {
    // Every word taught, in teaching order: n / daily_new is its day.
    await db.customStatement('''
CREATE TEMP TABLE seed_words AS
SELECT uid, step, n FROM (
  SELECT w.uid AS uid, w.sublevel_code AS step,
         ROW_NUMBER() OVER (ORDER BY s.ord, w.seq_in_sublevel) - 1 AS n
  FROM c.words w JOIN c.sublevels s ON s.code = w.sublevel_code
  WHERE w.kind = 'vocab')
WHERE n < ?2 * ?3
''', perDay.sublist(0, 3));
    // Day d, slot k: the day's new words first, then its revisions, spread
    // over what was taught before, 20 seconds apart from 11:00Z (the same
    // local date from UTC-11 to UTC+12). Mostly Good, some Easy and Again.
    await db.customStatement('''
CREATE TEMP TABLE seed_ratings AS
WITH RECURSIVE
  days(d) AS (SELECT 0 UNION ALL SELECT d + 1 FROM days WHERE d < ?2 - 1),
  slots(k) AS (SELECT 0 UNION ALL SELECT k + 1 FROM slots WHERE k < ?3 + ?4 - 1),
  picks(d, k, n) AS (
    SELECT d, k, CASE WHEN k < ?3 THEN d * ?3 + k
                      ELSE ((d * ?4 + k - ?3) * 7919) % (d * ?3) END
    FROM days, slots WHERE k < ?3 OR d > 0)
SELECT p.d AS d, p.k AS k, w.uid AS uid, w.step AS step, w.n AS n,
       date(?1, '+' || p.d || ' days') AS day,
       strftime('%Y-%m-%dT%H:%M:%fZ', ?1 || ' 11:00:00',
                '+' || p.d || ' days', '+' || (p.k * 20) || ' seconds') AS at,
       CASE WHEN (p.d * 37 + p.k) % 13 = 0 THEN 1
            WHEN (p.d * 37 + p.k) % 5 = 0 THEN 4 ELSE 3 END AS rating
FROM picks p JOIN seed_words w ON w.n = p.n
''', perDay);
    await db.customStatement(
      "INSERT INTO review_log (word_uid, reviewed_at, rating, source) "
      "SELECT uid, at, rating, 'daily' FROM seed_ratings ORDER BY d, k",
    );
    await db.customStatement('''
INSERT OR IGNORE INTO plan_items
  (plan_date, word_uid, kind, sublevel_code, completed_at)
SELECT day, uid, CASE WHEN k < ?3 THEN 'new' ELSE 'revise' END, step, at
FROM seed_ratings
''', perDay.sublist(0, 3));
    await db.customStatement('''
INSERT INTO daily_stats (day, new_done, reviews_done, seconds, completed_shown)
SELECT day, SUM(k < ?3), SUM(k >= ?3), COUNT(*) * 20, 1
FROM seed_ratings GROUP BY day
''', perDay.sublist(0, 3));
    // Older words are steadier: stability grows with the days since the
    // word was taught, so Today finds some due and most not.
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability,
  difficulty, reps, lapses, fsrs_state, last_review)
SELECT uid, 'learning', date(?1, '+' || (n / ?3) || ' days'),
       date(?1, '+' || (MAX(d) + 1 + (MAX(d) - n / ?3) / 2) || ' days'),
       1 + (MAX(d) - n / ?3) / 2.0, 5.0, COUNT(*), SUM(rating = 1), 2, MAX(at)
FROM seed_ratings GROUP BY uid
''', perDay.sublist(0, 3));
    // Each step from the day its first word was taught; all but the last
    // done the day its last one was.
    await db.customStatement('DELETE FROM enrollments');
    await db.customStatement(
      '''
INSERT INTO enrollments
  (sublevel_code, started_on, daily_new, study_days_mask, completed_on)
SELECT step, date(?1, '+' || (MIN(n) / ?3) || ' days'), ?3, ?5,
       CASE WHEN MAX(n) = ?2 * ?3 - 1 THEN NULL
            ELSE date(?1, '+' || (MAX(n) / ?3) || ' days') END
FROM seed_words GROUP BY step
''',
      <Object>[...perDay, choice.studyDaysMask],
    );
    await db.customStatement('DROP TABLE seed_ratings');
    await db.customStatement('DROP TABLE seed_words');
  });
}

/// The app's own user.db on this device, seeded: what perf_seed.dart runs,
/// and perf_test.dart before it launches the app. Not shared: the app opens
/// it again once this is closed.
Future<void> seedInstalledApp() async {
  final db = AppDatabase.open(shared: false);
  try {
    await ContentDao(db).attach();
    await seedYear(db, today: DateTime.now());
  } finally {
    await db.close();
  }
}
