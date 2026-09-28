import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, DatabaseConnection, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/progress_stats.dart' show ProgressRange;
import 'package:sogda/features/me/progress_screen.dart';

import '../db/content_fixture.dart';

/// M2's view over a real database: what it reads to draw a range.
void main() {
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late _Ratings ratings;
  late ProviderContainer container;

  setUp(() async {
    directory = tempDir('sogda_progress');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    ratings = _Ratings();
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory().interceptWith(ratings)),
    );
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 20)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
  });

  test('FR-M2-01 #784 Week reads the ratings its bars cover, not two years '
      'of them, and its retention is the same', () async {
    // Two years at 20 revisions a day, one in five Again, up to today noon.
    await db.customStatement('''
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 14599)
INSERT INTO review_log (word_uid, reviewed_at, rating, source, elapsed_days)
SELECT 'w' || i,
       strftime('%Y-%m-%dT%H:%M:%SZ', '2026-09-21 12:00:00',
                '-' || (i / 20) || ' days'),
       CASE WHEN i % 5 = 0 THEN 1 ELSE 3 END, 'daily', 3
FROM n
''');

    final view = await container.read(
      progressViewProvider(ProgressRange.week).future,
    );

    expect(ratings.most, lessThanOrEqualTo(3 * 20), reason: 'a day of slack');
    expect(view.retentionOverall, closeTo(0.8, 1e-9));
  });
}

/// The most rows the revision ratings' read returned (#784).
class _Ratings extends QueryInterceptor {
  int most = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('elapsed_days > 0') && rows.length > most) {
      most = rows.length;
    }
    return rows;
  }
}
