import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/services/background_tasks.dart';
import 'package:deutschplan/services/background_work.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import '../data/reminder_scheduler_test.dart' show FakeReminders, FakeWork;
import 'widget_snapshot_test.dart' show FakeWidgets;
import '../db/content_fixture.dart';
import '../features/today_fixtures.dart';

/// #158: the background tasks of `notifications-widget.md`.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group("reminder_compose's text", () {
    test('the open blocks, and how long they take', () {
      expect(
        reminderText(en, artboardToday(reviseDone: 0, newDone: 0)),
        '10 revisions · 7 new · about 6 min',
      );
    });

    test('a block with nothing open is left out', () {
      expect(
        reminderText(en, artboardToday(reviseDone: 9, newDone: 7)),
        '1 revision · about 6 min',
      );
    });

    test('a grammar topic due: its name on the line below', () {
      expect(
        reminderText(
          en,
          artboardToday(reviseDone: 10, newDone: 7, grammarDue: 1),
          grammar: 'Perfekt',
        ),
        'about 6 min\nGrammar due: Perfekt',
      );
    });

    test('nothing due, or the day done: none', () {
      expect(reminderText(en, artboardDone()), isNull);
      expect(
        reminderText(en, artboardToday(reviseDone: 10, newDone: 7)),
        isNull,
        reason: 'sentences are practice, not due',
      );
    });
  });

  group('plan_pregenerate at 00:05', () {
    test('tonight, or tomorrow night once it has passed', () {
      expect(
        untilPregenerate(DateTime(2026, 9, 21, 23)),
        const Duration(hours: 1, minutes: 5),
      );
      expect(
        untilPregenerate(DateTime(2026, 9, 22, 0, 3)),
        const Duration(minutes: 2),
      );
      expect(
        untilPregenerate(DateTime(2026, 9, 22, 0, 5)),
        const Duration(days: 1),
      );
    });
  });

  group('a task never migrates', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_schema');
      file = File('${directory.path}/user.sqlite');
      final db = AppDatabase(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      await db.close();
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test("a file at this build's schema is opened", () {
      expect(atCurrentSchema(file), isTrue);
    });

    test('an older one is left, untouched, for the app to migrate', () {
      final raw = sqlite3.open(file.path)
        ..userVersion = AppDatabase.latestSchemaVersion - 1;
      raw.close();

      expect(atCurrentSchema(file), isFalse);
      final after = sqlite3.open(file.path);
      addTearDown(after.close);
      expect(after.userVersion, AppDatabase.latestSchemaVersion - 1);
    });

    test('no file: nothing to open', () {
      expect(atCurrentSchema(File('${directory.path}/none.sqlite')), isFalse);
    });
  });

  test('iOS permits and registers every task by its id', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    for (final task in BackgroundTask.values) {
      expect(plist, contains('<string>${task.id}</string>'));
      expect(delegate, contains('withIdentifier: "${task.id}"'));
    }
    expect(plist, contains('<string>fetch</string>'));
    expect(plist, contains('<string>processing</string>'));
  });

  group('the tasks, against a database', () {
    late Directory directory;
    late AppDatabase db;
    late SettingsRepository settings;
    late DateTime now;
    late FakeReminders reminders;
    late FakeWork work;
    late FakeWidgets widgets;
    TodayView? view;

    const today = '2026-09-21';
    // Monday's reminder; the tasks run at 19:20 unless a test moves [now].
    final reminder = DateTime(2026, 9, 21, 19, 30);

    ProviderContainer containerFor() {
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => now),
          if (view case final view?)
            todayViewProvider.overrideWith((ref) async => view),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> run(BackgroundTask task) => runBackgroundTask(
      task,
      containerFor(),
      notifications: reminders,
      work: work,
      widgets: widgets,
    );

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_tasks');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      await db.customStatement(
        "INSERT INTO enrollments VALUES ('A1.1', '$today', 7, 127, NULL)",
      );
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderTime, (hour: 19, minute: 30));
      now = DateTime(2026, 9, 21, 19, 20);
      reminders = FakeReminders();
      work = FakeWork();
      widgets = FakeWidgets();
      view = null;
    });

    tearDown(() async {
      await settings.dispose();
      await db.close();
      directory.deleteSync(recursive: true);
    });

    test("plan_pregenerate opens today's plan", () async {
      now = DateTime(2026, 9, 21, 0, 5);
      await run(BackgroundTask.planPregenerate);

      final planned = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM plan_items WHERE plan_date = '$today'",
          )
          .getSingle();
      expect(planned.read<int>('n'), greaterThan(0));
    });

    test('plan_pregenerate keeps the week of reminders rolling, and queues '
        'itself for tomorrow night', () async {
      now = DateTime(2026, 9, 21, 0, 5);
      await run(BackgroundTask.planPregenerate);

      expect(reminders.scheduled, hasLength(7));
      expect(reminders.scheduled!.first, reminder);
      expect(
        work.queued[BackgroundTask.reminderCompose],
        const Duration(hours: 19, minutes: 15),
      );
      expect(
        work.queued[BackgroundTask.planPregenerate],
        const Duration(days: 1),
      );
    });

    test(
      "reminder_compose writes today's plan into today's reminder",
      () async {
        view = const TodayView(
          date: today,
          hour: 19,
          revise: BlockProgress(done: 0, total: 12),
          newToday: BlockProgress(done: 0, total: 7),
          openRevise: <String>[],
          openNew: <String>[],
          // The fixture's topic, for the grammar line.
          grammarDue: <String>['g1'],
          backlog: 0,
          streak: 1,
          estimate: Duration(minutes: 9),
          courseDay: 1,
          stepWords: (done: 0, learning: 0, todo: 3, total: 3),
        );
        await settings.write(SettingKeys.uiLanguage, UiLanguage.english);

        await run(BackgroundTask.reminderCompose);

        expect(reminders.replaced.keys, <DateTime>[reminder]);
        expect(reminders.replaced[reminder]?.title, 'Time for German');
        expect(
          reminders.replaced[reminder]?.body,
          '12 revisions · 7 new · about 9 min\n'
          'Grammar due: Wortstellung im Hauptsatz',
        );
        // And the next one, Tuesday's, is queued: 19:20 to 19:20.
        expect(
          work.queued[BackgroundTask.reminderCompose],
          const Duration(days: 1),
        );
      },
    );

    test('in the app language', () async {
      view = artboardToday(reviseDone: 0, newDone: 0);
      await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);

      await run(BackgroundTask.reminderCompose);

      final bn = lookupAppLocalizations(const Locale('bn'));
      expect(reminders.replaced[reminder]?.title, bn.reminderTitle);
      expect(
        reminders.replaced[reminder]?.body,
        startsWith(bn.reminderRevisions(10)),
      );
    });

    test('the day done: cancelled', () async {
      view = artboardDone();
      await run(BackgroundTask.reminderCompose);

      expect(reminders.replaced, isEmpty);
      expect(reminders.cancelledDays, <DateTime>[reminder]);
    });

    test(
      'nothing due, and reminder_only_when_due off: the plain one stays',
      () async {
        view = artboardDone();
        await settings.write(SettingKeys.reminderOnlyWhenDue, false);
        await run(BackgroundTask.reminderCompose);

        expect(reminders.replaced, isEmpty);
        expect(reminders.cancelledDays, isEmpty);
      },
    );

    test('a rest day: cancelled, even with revisions to do', () async {
      view = artboardRest();
      await run(BackgroundTask.reminderCompose);

      expect(reminders.replaced, isEmpty);
      expect(reminders.cancelledDays, <DateTime>[reminder]);
    });

    test('once it has rung, or while it is off: nothing', () async {
      view = artboardToday(reviseDone: 0, newDone: 0);
      now = DateTime(2026, 9, 21, 19, 31);
      await run(BackgroundTask.reminderCompose);

      now = DateTime(2026, 9, 21, 19, 20);
      await settings.write(SettingKeys.reminderEnabled, false);
      await run(BackgroundTask.reminderCompose);

      expect(reminders.replaced, isEmpty);
      expect(reminders.cancelledDays, isEmpty);
      expect(
        work.queued,
        isNot(contains(BackgroundTask.reminderCompose)),
        reason: 'off queues no compose',
      );
    });

    test('#159 widget_refresh writes the snapshot, and nothing else', () async {
      view = artboardToday();
      await run(BackgroundTask.widgetRefresh);
      expect(widgets.last['remaining'], 8);
      expect(reminders.scheduled, isNull);
      expect(work.queued, isEmpty);
    });

    test('#159 plan_pregenerate rewrites the widget for the new day', () async {
      now = DateTime(2026, 9, 21, 0, 5);
      view = artboardToday();
      await run(BackgroundTask.planPregenerate);
      expect(widgets.last['date'], today);
    });
  });
}
