import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/me_screen.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../db/content_fixture.dart';

/// M1's data, against a real database — #144.
void main() {
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer container;

  const today = '2026-09-21';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_me');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    // Last week's b1, b2 and c1 below must be in the course, or they are a
    // content update's removed words and not counted (BR-CONTENT-02).
    final raw = sqlite.sqlite3.open(content.path);
    try {
      for (final (i, uid) in <String>['b1', 'b2', 'c1'].indexed) {
        raw.execute(
          '''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, english, search_key, search_key_alt)
VALUES (?, 'A0.9', 'A1', ?, ?, ?, ?, ?, ?)
''',
          <Object>[uid, 90 + i, i + 1, uid, uid, uid, uid],
        );
      }
    } finally {
      raw.close();
    }
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();

    // A1.1 since the 1st, at 7 a day. Two new words from last week still
    // open — one of them skipped — one done, and today's two not started.
    await db.customStatement(
      "INSERT INTO enrollments VALUES ('A1.1', '2026-09-01', 7, 127, NULL)",
    );
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 9, 21),
    );
    // Not the defaults, so the view is seen to read them.
    await settings.write(SettingKeys.doneStabilityDays, 10);
    await settings.write(SettingKeys.examUnlockPercent, 80);
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, completed_at, skipped) VALUES
  ('2026-09-15', 'b1', 'new', 'A1.1', NULL, 0),
  ('2026-09-16', 'b2', 'new', 'A1.1', NULL, 1),
  ('2026-09-17', 'c1', 'new', 'A1.1', '2026-09-17T08:00:00', 0),
  ('$today', '${ContentFixture.haus}', 'new', 'A1.1', NULL, 0),
  ('$today', '${ContentFixture.tuer}', 'new', 'A1.1', NULL, 0)
''');
    // Practice on the 19th (grammar only), the 20th and today; the 18th has
    // a row with nothing in it.
    await db.customStatement('''
INSERT INTO daily_stats (day, new_done, reviews_done, grammar_done, sentences_done) VALUES
  ('2026-09-18', 0, 0, 0, 0),
  ('2026-09-19', 0, 0, 2, 0),
  ('2026-09-20', 3, 5, 0, 1),
  ('$today', 0, 1, 0, 0)
''');

    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8)),
        voiceInstalledProvider.overrideWith((ref) async => true),
      ],
    );
    // Held open, as the screen holds it.
    container.listen(meViewProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  test(
    'FR-M1-02 every kind of item counts, and empty days are left out',
    () async {
      final view = await container.read(meViewProvider.future);

      expect(view.activity, <String, int>{
        '2026-09-19': 2,
        '2026-09-20': 9,
        today: 1,
      });
    },
  );

  test(
    'the header: the streak, since when, and the settings it shows',
    () async {
      final view = await container.read(meViewProvider.future);

      expect(view.streak, 3);
      expect(view.since, '2026-09-01');
      expect(view.doneDays, 10);
      expect(view.unlockPercent, 80);
      expect(view.today, today);
    },
  );

  test('FR-M1-03 the schedule is measured through yesterday', () async {
    final view = await container.read(meViewProvider.future);

    // b1 and the skipped b2 are behind; c1 is done; today's two are today's.
    expect(view.schedule.planned, 3);
    expect(view.schedule.introduced, 1);
    expect(view.schedule.behind, 2);
    expect(view.schedule.dailyNew, 7);
  });

  test('a day of practice moves M1 without asking', () async {
    await container.read(meViewProvider.future);

    await db
        .into(db.dailyStats)
        .insertOnConflictUpdate(
          const DailyStatsCompanion(
            day: Value('2026-09-18'),
            reviewsDone: Value(12),
          ),
        );
    await pumpEventQueue();

    final view = await container.read(meViewProvider.future);
    expect(view.activity['2026-09-18'], 12);
    expect(view.streak, 4);
  });

  test('a word caught up moves the schedule without asking', () async {
    await container.read(meViewProvider.future);

    await (db.update(db.planItems)..where((t) => t.wordUid.equals('b1'))).write(
      const PlanItemsCompanion(completedAt: Value('2026-09-21T08:30:00')),
    );
    await pumpEventQueue();

    expect((await container.read(meViewProvider.future)).schedule.behind, 1);
  });

  test('a rename is trimmed, saved, and reaches Today', () async {
    container.listen(todayViewProvider, (_, _) {});
    // Today settled first, as a kept-alive tab is: only watching the name
    // can bring the rename to it.
    expect(
      (await container.read(todayViewProvider.future)).learnerName,
      isNull,
    );
    await pumpEventQueue();
    final names = container.read(learnerNameProvider.notifier);

    await names.rename('  Rahmat ');
    expect(container.read(learnerNameProvider), 'Rahmat');
    expect(settings.read(SettingKeys.learnerName), 'Rahmat');
    expect(
      (await container.read(todayViewProvider.future)).learnerName,
      'Rahmat',
    );

    await names.rename('   ');
    expect(container.read(learnerNameProvider), isNull);
    expect(settings.read(SettingKeys.learnerName), isNull);
  });

  test('a name written anywhere else reaches M1 and Today', () async {
    container
      ..listen(todayViewProvider, (_, _) {})
      ..listen(learnerNameProvider, (_, _) {});
    expect(
      (await container.read(todayViewProvider.future)).learnerName,
      isNull,
    );
    await pumpEventQueue();

    // As Settings, import or reset would: straight to the repository.
    await settings.write(SettingKeys.learnerName, ' Maruf ');
    await pumpEventQueue();

    expect(container.read(learnerNameProvider), 'Maruf');
    expect(
      (await container.read(todayViewProvider.future)).learnerName,
      'Maruf',
    );
  });
}
