import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:drift/drift.dart' show DatabaseConnection, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// T1's data, against a real plan — #95.
void main() {
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late DateTime now;
  late ProviderContainer container;

  const today = '2026-09-21';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_today');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();

    // A1.1 since the 1st, after a first step finished in August, and planned
    // through today already, so openDay has nothing to add and the rows below
    // are the whole plan.
    await db.customStatement(
      "INSERT INTO enrollments VALUES ('A0.9', '2026-08-25', 7, 127, "
      "'2026-08-31'), ('A1.1', '2026-09-01', 7, 127, NULL)",
    );
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 9, 21),
    );
    await settings.write(SettingKeys.learnerName, 'Maruf');
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, completed_at, skipped) VALUES
  ('$today', 'r1', 'revise', 'A1.1', '2026-09-21T07:00:00', 0),
  ('$today', 'r2', 'revise', 'A1.1', NULL, 0),
  ('$today', '${ContentFixture.haus}', 'new', 'A1.1', NULL, 0),
  ('$today', '${ContentFixture.tuer}', 'new', 'A1.1', NULL, 1),
  ('2026-09-15', 'b1', 'new', 'A1.1', NULL, 0),
  ('2026-09-16', 'b2', 'new', 'A1.1', NULL, 0)
''');

    now = DateTime(2026, 9, 21, 8);
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    // Held open, as the screen holds it: an auto-dispose provider nobody
    // listens to would be rebuilt from scratch on every read.
    container.listen(todayViewProvider, (_, _) {});
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

  test('FR-T1-01 it renders from the persisted plan', () async {
    final view = await container.read(todayViewProvider.future);

    expect(view.date, today);
    expect(view.step, 'A1.1');
    expect(view.revise.total, 2);
    expect(view.newToday.total, 2);
    expect(view.openRevise, <String>['r2']);
    // A skipped card is not waiting, the way BR-PLAN-10 counts it.
    expect(view.openNew, <String>[ContentFixture.haus]);
  });

  test(
    'FR-T1-02 the ring is done over revise + new + grammar + sentences',
    () async {
      final view = await container.read(todayViewProvider.future);

      // r1 done; tuer skipped; haus and r2 open. g1 is the only grammar topic
      // and has never been practised, so nothing is due.
      expect(view.completed, 2);
      expect(view.total, 4);
      expect(view.left, 2);
    },
  );

  test('BR-PLAN-09 the estimate is for what is left', () async {
    final view = await container.read(todayViewProvider.future);

    // One revision and one new word open: 25 s + 45 s.
    expect(view.estimate, const Duration(seconds: 70));
    expect(view.estimateMinutes, 2);
  });

  test('the ring card and the section cards read the course', () async {
    final view = await container.read(todayViewProvider.future);

    // From the first step's start: a new step does not restart the course.
    expect(view.courseDay, 28, reason: '25 August is day 1');
    expect(view.stepWords.total, 2, reason: "A1.1's two words");
    expect(view.newCategory, 'Wohnen');
    expect(view.backlog, 2);
    expect(view.backlogFrom, '2026-09-15');
    expect(view.backlogTo, '2026-09-16');
    expect(view.grammar?.uid, 'g1');
    expect(view.grammar?.rule, 'The verb is second.');
    expect(view.learnerName, 'Maruf');
    expect(view.hour, 8);
  });

  test('a finished card moves the ring without being asked', () async {
    await container.read(todayViewProvider.future);

    // Through drift, as a rating writes it, so the table's watchers hear.
    await db.customUpdate(
      "UPDATE plan_items SET completed_at = '2026-09-21T08:10:00' "
      "WHERE word_uid = 'r2'",
      updates: <TableInfo<Table, Object?>>{db.planItems},
    );
    await pumpEventQueue();
    final view = await container.read(todayViewProvider.future);

    expect(view.revise.done, 2);
    expect(view.openRevise, isEmpty);
  });

  group('FR-T1-05 midnight', () {
    test('a new date re-plans for it', () async {
      await container.read(todayViewProvider.future);

      now = DateTime(2026, 9, 22, 0, 5);
      container.invalidate(todayProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.date, '2026-09-22');
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        '2026-09-22',
        reason: 'openDay ran for the new day',
      );
    });

    test('the same date plans nothing again', () async {
      var plans = 0;
      container.listen(todayPlanProvider, (_, next) {
        if (next.hasValue && !next.isLoading) plans++;
      });
      await container.read(todayViewProvider.future);
      final before = plans;

      now = DateTime(2026, 9, 21, 23, 55);
      container.invalidate(todayProvider);
      await container.read(todayViewProvider.future);
      await pumpEventQueue();

      expect(plans, before);
    });
  });
}
