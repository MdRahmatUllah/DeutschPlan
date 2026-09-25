import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// M2's reads — #145.
void main() {
  late AppDatabase db;
  late ProgressRepository progress;

  setUp(() {
    db = AppDatabase.memory();
    progress = ProgressRepository(db);
  });

  tearDown(() => db.close());

  test('the days, oldest first', () async {
    await db.customStatement('''
INSERT INTO daily_stats (day, new_done, reviews_done, seconds) VALUES
  ('2026-09-24', 6, 20, 900),
  ('2026-09-21', 6, 11, 600)
''');
    expect(await progress.days(), <Object>[
      (day: '2026-09-21', reviews: 11, newWords: 6),
      (day: '2026-09-24', reviews: 20, newWords: 6),
    ]);
  });

  test(
    'FR-M2-01 revision ratings from the daily session, by the local day',
    () async {
      // Local evening and morning, whatever the host's zone.
      String at(DateTime local) => local.toUtc().toIso8601String();
      final evening = at(DateTime(2026, 9, 21, 23, 30));
      final morning = at(DateTime(2026, 9, 22, 0, 30));
      await db.customStatement('''
INSERT INTO review_log (word_uid, reviewed_at, rating, source, elapsed_days)
VALUES
  ('a', '$evening', 3, 'daily', 2),
  ('b', '$morning', 1, 'daily', 5),
  ('c', '$morning', 3, 'daily', 0),
  ('d', '$morning', 3, 'quiz', 4)
''');

      expect(await progress.revisionRatings(), <String, List<int>>{
        '2026-09-21': <int>[3],
        // Not the new word's first rating, nor the quiz's.
        '2026-09-22': <int>[1],
      });
    },
  );

  test('FR-M2-03 the totals: study time, words met, every rating', () async {
    await db.customStatement('''
INSERT INTO daily_stats (day, seconds) VALUES ('2026-09-21', 600), ('2026-09-22', 150);
INSERT INTO word_state (word_uid, status, introduced_on, reps) VALUES
  ('a', 'learning', '2026-09-21', 1), ('b', 'todo', NULL, 0),
  ('c', 'done', '2026-09-01', 4), ('d', 'learning', NULL, 1);
INSERT INTO review_log (word_uid, reviewed_at, rating, source) VALUES
  ('a', '2026-09-21T10:00:00Z', 3, 'daily'), ('c', '2026-09-21T10:00:00Z', 1, 'quiz');
''');
    // d was rated from search: met, with no day it was introduced.
    expect(await progress.totals(), (seconds: 750, introduced: 3, reviews: 2));
  });
}
