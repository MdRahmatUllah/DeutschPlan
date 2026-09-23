import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/setup_repository.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../db/content_fixture.dart';

/// S2's finish and restart setup — #92. Against SQLite with the course
/// attached, because "one transaction" and "day 1 planned" are claims about
/// the database, and a fake would only be checking itself.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const today = '2026-09-21'; // a Monday

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer container;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_setup');
    final content = ContentFixture.write('${directory.path}/content.db').file;

    // The fixture has three words; a seven-a-day first day needs more.
    final raw = sqlite.sqlite3.open(content.path);
    try {
      for (var i = 1; i <= 20; i++) {
        raw.execute(
          '''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, english, search_key, search_key_alt)
VALUES (?, ?, 'A1', ?, ?, ?, ?, ?, ?)
''',
          <Object>[
            's$i',
            i.isEven ? 'A1.2' : 'A1.1',
            100 + i,
            100 + i,
            'Wort$i',
            'word$i',
            'wort$i',
            'wort$i',
          ],
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

    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        todayProvider.overrideWithValue(today),
      ],
    );
    // A listener, as the pages give it: the flow auto-disposes otherwise.
    container.listen(setupFlowProvider, (_, _) {});
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

  OnboardingNotifier draft() => container.read(onboardingProvider.notifier);
  SetupFlow flow() => container.read(setupFlowProvider.notifier);

  Future<List<Map<String, Object?>>> enrollments() async => [
    for (final row
        in await db
            .customSelect(
              'SELECT sublevel_code, started_on, daily_new, study_days_mask, '
              'completed_on FROM enrollments ORDER BY rowid',
            )
            .get())
      row.data,
  ];

  Future<int> plannedToday(String kind) async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM plan_items '
                'WHERE plan_date = ? AND kind = ?',
                variables: <Variable<Object>>[
                  Variable<String>(today),
                  Variable<String>(kind),
                ],
              )
              .getSingle())
          .read<int>('n');

  group('FR-S2-03 finishing', () {
    test('enrolls in the chosen step at the chosen pace', () async {
      draft()
        ..chooseStep('A1.2')
        ..setDailyNew(5)
        ..toggleStudyDay(DateTime.sunday);

      expect(await flow().finish(), isTrue);

      expect(await enrollments(), <Map<String, Object?>>[
        <String, Object?>{
          'sublevel_code': 'A1.2',
          'started_on': today,
          'daily_new': 5,
          'study_days_mask': 127 & ~(1 << 6),
          'completed_on': null,
        },
      ]);
    });

    test('and writes the pace and the reminder to settings', () async {
      draft()
        ..setDailyNew(12)
        ..setReviseCount(25)
        ..toggleStudyDay(DateTime.saturday)
        ..setReminderTime((hour: 7, minute: 15));

      await flow().finish();

      // Read back from a fresh repository, so this is the disk and not the
      // in-memory cache the first one keeps.
      final disk = SettingsRepository(db);
      await disk.load();
      addTearDown(disk.dispose);
      expect(disk.read(SettingKeys.dailyNew), 12);
      expect(disk.read(SettingKeys.reviseCount), 25);
      expect(disk.read(SettingKeys.studyDaysMask), 127 & ~(1 << 5));
      expect(disk.read(SettingKeys.reminderTime), (hour: 7, minute: 15));
      expect(disk.read(SettingKeys.reminderEnabled), isFalse);
    });

    test('opens Today with day 1 already planned', () async {
      // "…and open Today with the first day planned" — so the plan is there
      // before Today asks for it.
      draft().setDailyNew(7);

      await flow().finish();

      expect(await plannedToday('new'), 7);
    });

    test('and leaves the draft for the route to clear', () async {
      // Cleared here, the page still on screen would redraw with the
      // defaults for a frame before Today arrived (route_guards_test holds
      // the clearing).
      draft()
        ..chooseStep('A1.2')
        ..setDailyNew(20);

      await flow().finish();

      final left = container.read(onboardingProvider);
      expect((left.step, left.dailyNew), ('A1.2', 20));
    });

    test('in one transaction: a failure leaves nothing half-written', () async {
      // The enrollment is written after the settings. Make it fail, and the
      // settings written before it must not survive — on disk or in memory.
      await db.customStatement(
        "CREATE TEMP TRIGGER refuse BEFORE INSERT ON enrollments "
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      draft().setDailyNew(19);

      expect(await flow().finish(), isFalse);

      expect(container.read(setupFlowProvider), SetupStatus.failed);
      expect(await enrollments(), isEmpty);
      final disk = SettingsRepository(db);
      await disk.load();
      addTearDown(disk.dispose);
      expect(disk.read(SettingKeys.dailyNew), 7, reason: 'rolled back');
      expect(settings.read(SettingKeys.dailyNew), 7, reason: 'cache re-read');
      expect(
        container.read(onboardingProvider).dailyNew,
        19,
        reason: 'the draft survives to try again',
      );
    });

    test('and a second tap while finishing starts nothing', () async {
      final first = flow().finish();
      final second = flow().finish();

      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(await enrollments(), hasLength(1));
    });
  });

  group('FR-S2-01 Skip', () {
    void choose() => draft()
      ..chooseStep('A1.2')
      ..setDailyNew(20)
      ..setReviseCount(40)
      ..toggleStudyDay(DateTime.monday)
      ..setReminderTime((hour: 6, minute: 0));

    test('from page 3 takes the defaults for pages 3, 4 and 5', () async {
      choose();

      await flow().finish(skippingFrom: OnboardingPage.startingPoint);

      final row = (await enrollments()).single;
      expect(
        (row['sublevel_code'], row['daily_new'], row['study_days_mask']),
        ('A1.1', 7, 127),
      );
      expect(settings.read(SettingKeys.reviseCount), 10);
      expect(settings.read(SettingKeys.reminderTime), (hour: 19, minute: 30));
    });

    test('from page 4 keeps the step and defaults the rest', () async {
      choose();

      await flow().finish(skippingFrom: OnboardingPage.dailyPace);

      final row = (await enrollments()).single;
      expect((row['sublevel_code'], row['daily_new']), ('A1.2', 7));
      expect(settings.read(SettingKeys.reviseCount), 10);
    });

    test('from page 5 keeps the pace and defaults the reminder', () async {
      choose();

      await flow().finish(skippingFrom: OnboardingPage.reminderAndVoice);

      final row = (await enrollments()).single;
      expect((row['daily_new'], row['study_days_mask']), (20, 127 & ~1));
      expect(settings.read(SettingKeys.reviseCount), 40);
      expect(settings.read(SettingKeys.reminderTime), (hour: 19, minute: 30));
    });

    test('and finishes, as FR-S2-01 says', () async {
      await flow().finish(skippingFrom: OnboardingPage.startingPoint);

      expect(await enrollments(), hasLength(1));
      expect(await plannedToday('new'), 7);
    });
  });

  group('restart setup', () {
    Future<void> firstRun({String step = 'A1.1'}) async {
      draft()
        ..chooseStep(step)
        ..setDailyNew(7);
      await flow().finish();
      container.invalidate(onboardingProvider);
    }

    test('Skip keeps the values the pages opened on', () async {
      // Restart setup opens on the learner's own values. Skip taking the
      // first-run defaults instead would move them back to A1.1 and close
      // the step they are in.
      await firstRun(step: 'A1.2');
      await settings.write(SettingKeys.dailyNew, 12);

      await flow().beginRestart();
      await flow().finish(skippingFrom: OnboardingPage.startingPoint);

      final rows = await enrollments();
      expect(rows, hasLength(1), reason: 'the step was not switched');
      expect(
        (rows.single['sublevel_code'], rows.single['daily_new']),
        ('A1.2', 12),
      );
    });

    test('pre-fills every page with what the learner has now', () async {
      await firstRun(step: 'A1.2');
      await settings.write(SettingKeys.reviseCount, 33);
      await settings.write(SettingKeys.reminderEnabled, true);

      await flow().beginRestart();

      final prefilled = container.read(onboardingProvider);
      expect(prefilled.restart, isTrue);
      expect(
        (prefilled.step, prefilled.reviseCount, prefilled.reminderOn),
        ('A1.2', 33, true),
      );
    });

    test('a new pace for the same step keeps its start', () async {
      // Started three weeks ago: re-enrolling would move the start to today
      // and plan the step as if it had just begun.
      await firstRun();
      await db.customStatement(
        "UPDATE enrollments SET started_on = '2026-09-01'",
      );

      await flow().beginRestart();
      draft().setDailyNew(12);
      await flow().finish();

      final rows = await enrollments();
      expect(rows, hasLength(1));
      expect(
        (rows.single['started_on'], rows.single['daily_new']),
        ('2026-09-01', 12),
      );
    });

    test('a different step closes the old one — one active, always', () async {
      // `idx_one_active_enrollment` would refuse a second open row; closing
      // the first is what keeps the insert from failing.
      await firstRun();

      await flow().beginRestart();
      draft().chooseStep('A1.2');
      expect(await flow().finish(), isTrue);

      final rows = await enrollments();
      expect(
        rows.map((r) => (r['sublevel_code'], r['completed_on'])),
        <(Object?, Object?)>[('A1.1', today), ('A1.2', null)],
      );
    });

    test('and the history is not touched', () async {
      // "keeps progress; only plan settings change".
      await firstRun();
      await db.customStatement(
        "INSERT INTO word_state (word_uid, status, stability, difficulty, "
        "reps, lapses, due, last_review) "
        "VALUES ('s1', 'learning', 2.5, 5.0, 1, 0, '2026-09-22', '$today')",
      );
      Future<int> count(String table) async =>
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n');
      final before = (await count('word_state'), await count('plan_items'));

      await flow().beginRestart();
      draft().chooseStep('A1.2');
      await flow().finish();

      expect(await count('word_state'), before.$1);
      expect(await count('plan_items'), greaterThanOrEqualTo(before.$2));
    });
  });

  test('SetupRepository reads the active step for restart setup', () async {
    final repository = SetupRepository(db, settings);
    expect(await repository.activeStep(), isNull, reason: 'before setup');

    await flow().finish();

    expect(await repository.activeStep(), 'A1.1');
  });
}
