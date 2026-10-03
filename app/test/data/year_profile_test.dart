// #818: perf.py's year profile, checked on the host: the device run only
// measures it.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/plan_engine.dart';

import '../../integration_test/year_profile.dart';
import '../db/content_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
    );
  });
  tearDown(() => db.close());

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  test('#818 a year of study: about 14,000 ratings, each with its plan row, '
      'and a day of stats for each day', () async {
    final today = DateTime(2026, 9, 27);
    await seedYear(db, today: today);

    expect(await count('SELECT COUNT(*) AS n FROM review_log'), 13475);
    expect(
      await count(
        'SELECT COUNT(DISTINCT date(reviewed_at)) AS n FROM review_log',
      ),
      yearDays,
    );
    expect(await count('SELECT COUNT(*) AS n FROM daily_stats'), yearDays);
    expect(
      await count(
        "SELECT COUNT(*) AS n FROM plan_items WHERE completed_at IS NULL",
      ),
      0,
      reason: 'no backlog: every planned card was rated',
    );
    expect(
      await count("SELECT COUNT(*) AS n FROM plan_items WHERE kind = 'new'"),
      yearDays * 7,
    );
    expect(await count('SELECT COUNT(*) AS n FROM word_state'), yearDays * 7);
    expect(
      await count("SELECT MAX(day) = '2026-09-26' AS n FROM daily_stats"),
      1,
      reason: 'the year ends yesterday',
    );

    // In teaching order: one step at a time, each started once the one
    // before it was done, as `idx_one_active_enrollment` has it.
    final steps = await db
        .customSelect(
          'SELECT e.sublevel_code AS code, e.started_on AS started, '
          'e.completed_on AS completed FROM enrollments e '
          'JOIN c.sublevels s ON s.code = e.sublevel_code ORDER BY s.ord',
        )
        .get();
    expect(
      [for (final step in steps) step.read<String>('code')],
      // B1.2 until #1257 added 73 words, 2,611 up to B1.2 for 2,555 a year.
      <String>['A1.1', 'A1.2', 'A2.1', 'A2.2', 'B1.1'],
    );
    for (var i = 1; i < steps.length; i++) {
      expect(
        steps[i]
            .read<String>('started')
            .compareTo(steps[i - 1].read<String>('completed')),
        greaterThanOrEqualTo(0),
        reason:
            '${steps[i].read<String>('code')} began before the step '
            'before it was done',
      );
    }
  });

  test('#818 the year leaves an ordinary day: an open step with words to '
      'learn, and Today plans its 7 new and 30 revisions', () async {
    final today = DateTime(2026, 9, 27);
    await seedYear(db, today: today);
    final settings = SettingsRepository(db);
    await settings.load();

    final engine = PlanEngine(
      store: DriftPlanStore(db, settings),
      reviseCount: settings.read(SettingKeys.reviseCount),
      backlogCatchupDays: settings.read(SettingKeys.backlogCatchupDays),
    );
    final plan = await engine.openDay(planDate(today));

    expect(plan.activeStep, 'B1.1');
    expect(plan.isStudyDay, isTrue);
    expect(plan.newToday, hasLength(7));
    expect(plan.revise, hasLength(yearReviseCount));
    expect(plan.backlog, isEmpty);
  });
}
