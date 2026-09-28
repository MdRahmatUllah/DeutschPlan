// #994: the first open after a month away, planned as the app plans it: on
// drift's background isolate, with the UI isolate only awaiting.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/plan_engine.dart';

import '../db/content_fixture.dart';

void main() {
  test('#994 BR-PLAN-05 thirty missed days at 50 new words a day: all '
      'planned, and no slice of the UI isolate longer than a frame', () async {
    final db = AppDatabase(
      NativeDatabase.createInBackground(
        File('${tempDir('sogda_catch_up').path}/user.db'),
        setup: configureConnection,
      ),
    );
    addTearDown(db.close);
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
    );
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    // Planned last on 27 Aug, and opened again on 27 Sep.
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 8, 27),
    );
    await db.customStatement(
      'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
      "study_days_mask) VALUES ('A1.1', '2026-08-01', 50, 127)",
    );
    final engine = PlanEngine(
      store: DriftPlanStore(db, settings),
      reviseCount: 10,
      backlogCatchupDays: settings.read(SettingKeys.backlogCatchupDays),
    );

    // A frame's worth of work the UI isolate can't do shows as a late tick.
    final clock = Stopwatch()..start();
    var last = Duration.zero;
    var longest = Duration.zero;
    final ticks = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = clock.elapsed;
      if (now - last > longest) longest = now - last;
      last = now;
    });
    final plan = await engine.openDay('2026-09-27');
    ticks.cancel();

    expect(plan.newToday, hasLength(50));
    expect(plan.backlog, hasLength(30 * 50), reason: 'the 30 days missed');
    expect(longest, lessThan(const Duration(milliseconds: 16)));
  });
}
