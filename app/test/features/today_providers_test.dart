import 'dart:async';
import 'dart:io';

import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/features/today/today_view.dart';
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
  var voiceReady = false;

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
    voiceReady = false;
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => now),
        // The model files live outside the test; whether they are there is
        // the one thing about them Today asks.
        voiceInstalledProvider.overrideWith((ref) async => voiceReady),
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

  group('#96 all done', () {
    Future<void> finishTheDay() async {
      await db.customUpdate(
        "UPDATE plan_items SET completed_at = '2026-09-21T09:00:00' "
        "WHERE plan_date = '$today' AND completed_at IS NULL AND skipped = 0",
        updates: <TableInfo<Table, Object?>>{db.planItems},
      );
      await pumpEventQueue();
    }

    test('before the day is done there is no Tomorrow', () async {
      final view = await container.read(todayViewProvider.future);
      expect(view.isDone, isFalse);
      expect(view.tomorrow, isNull);
    });

    test('Tomorrow is a dry run of openDay(tomorrow) that writes nothing', () async {
      await finishTheDay();
      final view = await container.read(todayViewProvider.future);

      expect(view.isDone, isTrue);
      // A1.1's two words are both planned, so tomorrow runs out of it and
      // starts A1.2 — whose one word is tomorrow's new word.
      expect(view.tomorrow?.newWords, 1);
      expect(view.tomorrow?.category, 'Wohnen');

      final rows = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM plan_items WHERE plan_date > '$today'",
          )
          .getSingle();
      expect(rows.read<int>('n'), 0, reason: 'nothing planned for real');
      final open = await db
          .customSelect(
            'SELECT sublevel_code FROM enrollments WHERE completed_on IS NULL',
          )
          .get();
      expect(open.single.read<String>('sublevel_code'), 'A1.1');
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        today,
        reason: 'planning did not move on',
      );
    });

    test('BR-PLAN-01 it knows when tomorrow is a rest day', () async {
      // Tomorrow, the 22nd, is a Tuesday: study every day but Tuesday.
      await db.customStatement(
        "UPDATE enrollments SET study_days_mask = 125 WHERE sublevel_code = 'A1.1'",
      );
      await finishTheDay();
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.tomorrow?.restDay, isTrue);
    });

    test('it counts the minutes studied today', () async {
      await db.customStatement(
        "INSERT INTO daily_stats (day, seconds) VALUES ('$today', 750)",
      );
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);
      expect(view.minutes, 12);
    });
  });

  group('#97 a rest day', () {
    setUp(() async {
      // Monday the 21st off, and today not planned yet: the rest day opens
      // from scratch, with three words due by tomorrow.
      await db.customStatement(
        "UPDATE enrollments SET study_days_mask = 126 WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        "DELETE FROM plan_items WHERE plan_date = '$today'",
      );
      await settings.write(
        SettingKeys.lastPlannedDate,
        DateTime.utc(2026, 9, 20),
      );
      // Course words: a plan row takes its step from the course, so a uid
      // the course does not have is never planned.
      await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability, reps, last_review) VALUES
  ('${ContentFixture.haus}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.tuer}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.strasse}', 'learning', '2026-09-10', '2026-09-22', 3, 2, '2026-09-19'),
  ('paused', 'suspended', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19')
''');
      // The outer setUp already started a build, which raced these writes;
      // start again from what they left.
      container
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);
    });

    test('BR-PLAN-01 no new words and no backlog growth', () async {
      final view = await container.read(todayViewProvider.future);

      expect(view.isRestDay, isTrue);
      expect(view.newToday.total, 0);
      expect(view.backlog, 2, reason: 'what was waiting still is, no more');
    });

    test('it knows what revising anyway would take off tomorrow', () async {
      final view = await container.read(todayViewProvider.future);

      expect(view.dueTomorrow, 3, reason: 'a suspended word is not due');
      expect(view.revise.open, 3, reason: 'revisions are still picked');
      expect(view.dueTomorrowIfRevised, 0);
    });
  });

  group('FR-T1-06 the contextual card, from what is stored', () {
    test('without the on-device voice, it is offered', () async {
      await container.read(voiceInstalledProvider.future);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual?.kind, ContextualKind.voice);
    });

    test('with it installed, there is nothing to offer', () async {
      voiceReady = true;
      container.invalidate(voiceInstalledProvider);
      await container.read(voiceInstalledProvider.future);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual, isNull);
    });

    test('Today does not wait for the voice check', () async {
      // A check that never answers: the view still comes, without the card.
      final hanging = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => now),
          voiceInstalledProvider.overrideWith(
            (ref) => Completer<bool>().future,
          ),
        ],
      );
      addTearDown(hanging.dispose);
      hanging.listen(todayViewProvider, (_, _) {});

      final view = await hanging.read(todayViewProvider.future);
      expect(view.date, today);
      expect(view.contextual, isNull);
    });

    test('the voice is not installed until its files are there', () async {
      final support = Directory.systemTemp.createTempSync('deutschplan_voice');
      addTearDown(() => support.deleteSync(recursive: true));
      final models = ProviderContainer(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          modelRepositoryProvider.overrideWithValue(
            ModelRepository(settings, support: support),
          ),
        ],
      );
      addTearDown(models.dispose);

      expect(await models.read(voiceInstalledProvider.future), isFalse);
    });

    test('a dismissal in dismissed_cards is honoured', () async {
      await container.read(voiceInstalledProvider.future);
      await settings.write(SettingKeys.dismissedCards, '["voice"]');
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual, isNull);
    });

    test('a malformed dismissed_cards does not take Today down', () async {
      await container.read(voiceInstalledProvider.future);
      await settings.write(SettingKeys.dismissedCards, '{not json');
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.date, today);
      expect(view.contextual?.kind, ContextualKind.voice);
    });

    test(
      'BR-CONTENT-03 an unseen update comes first, with its counts',
      () async {
        await db.customStatement(
          "INSERT INTO content_updates (version, changed_json, seen) VALUES "
          "('202609201200', '{\"added\":[\"a\",\"b\"],\"removed\":[\"c\"],\"changed\":[]}', 0)",
        );
        container.invalidate(todayViewProvider);
        final view = await container.read(todayViewProvider.future);

        final offer = view.contextual!;
        expect(offer.kind, ContextualKind.contentUpdate);
        expect((offer.added, offer.removed, offer.changed), (2, 1, 0));
        expect(offer.version, '202609201200');
      },
    );
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
