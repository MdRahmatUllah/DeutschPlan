// #994: the first open after a month away, planned as the app plans it (on
// drift's background isolate), keeps every UI-isolate slice under a frame.
// It holds the budget, not where the work runs: the catch-up stayed under
// 16 ms a slice even with SQLite on the UI isolate (#1006's review).

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
  /// A learner who planned last on 27 Aug, at 50 new words a day, opening
  /// the app on 27 Sep: the day's plan, and the longest the UI isolate went
  /// without running a 1 ms timer meanwhile (a frame's worth of work shows
  /// as a late tick).
  Future<(DailyPlan, Duration)> catchUp() async {
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
    return (plan, longest);
  }

  test('#994 BR-PLAN-05 thirty missed days at 50 new words a day: all '
      'planned, and no slice of the UI isolate longer than a frame', () async {
    // The best of three (#683): one run measures whatever else the machine
    // was doing, and work that blocks the isolate is late in every run.
    var best = const Duration(days: 1);
    for (var run = 0; run < 3; run++) {
      final (plan, longest) = await catchUp();
      expect(plan.newToday, hasLength(50));
      expect(plan.backlog, hasLength(30 * 50), reason: 'the 30 days missed');
      if (longest < best) best = longest;
    }
    expect(best, lessThan(const Duration(milliseconds: 16)));
  });
}
