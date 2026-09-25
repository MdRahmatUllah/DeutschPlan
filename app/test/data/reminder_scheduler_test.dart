import 'dart:async';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/reminder_scheduler.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/background_work.dart';
import 'package:deutschplan/services/reminder_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notifications without a phone: what was scheduled.
class FakeReminders implements ReminderNotifications {
  List<DateTime>? scheduled;
  ReminderCopy? copy;
  int cancelled = 0;
  void Function(String link)? onTap;

  /// The link a tap that started the app carried.
  String? launched;

  @override
  Future<void> init(void Function(String link) onTap) async =>
      this.onTap = onTap;

  @override
  Future<String?> launchedWith() async => launched;

  /// Holds a schedule open, as a slow plugin would.
  Completer<void>? gate;

  @override
  Future<void> schedule(List<DateTime> at, ReminderCopy copy) async {
    await gate?.future;
    scheduled = at;
    this.copy = copy;
  }

  /// `reminder_compose`'s: the days rewritten, and the ones cancelled.
  final Map<DateTime, ReminderCopy> replaced = <DateTime, ReminderCopy>{};
  final List<DateTime> cancelledDays = <DateTime>[];

  @override
  Future<void> replace(DateTime at, ReminderCopy copy) async =>
      replaced[at] = copy;

  @override
  Future<void> cancelDay(DateTime day) async => cancelledDays.add(day);

  @override
  Future<void> cancelAll() async {
    scheduled = null;
    cancelled++;
  }
}

/// The platform's task queue without a phone: what waits, and how long.
class FakeWork implements BackgroundWork {
  bool started = false;
  final Map<BackgroundTask, Duration> queued = <BackgroundTask, Duration>{};
  final Set<BackgroundTask> hourlyTasks = <BackgroundTask>{};

  @override
  Future<void> init() async => started = true;

  @override
  Future<void> after(BackgroundTask task, Duration delay) async =>
      queued[task] = delay;

  @override
  Future<void> hourly(BackgroundTask task) async => hourlyTasks.add(task);

  @override
  Future<void> cancel(BackgroundTask task) async => queued.remove(task);
}

/// #157: the reminders kept to the settings.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeReminders reminders;
  late FakeWork work;
  late ReminderScheduler scheduler;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    reminders = FakeReminders();
    work = FakeWork();
    scheduler = ReminderScheduler(
      settings,
      reminders,
      // Monday 21 September 2026, the morning.
      () => DateTime(2026, 9, 21, 8),
      (language) => (title: language.name, body: 'body', channel: 'channel'),
      work,
    );
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  test('off by default: nothing scheduled', () async {
    await scheduler.sync();
    expect(reminders.scheduled, isNull);
    expect(reminders.cancelled, 1);
  });

  test(
    "on: the week's study days at reminder_time, in the app's language",
    () async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderTime, (hour: 7, minute: 15));
      await settings.write(SettingKeys.studyDaysMask, 1 | 4);
      await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);

      await scheduler.sync();

      expect(reminders.scheduled, <DateTime>[
        DateTime(2026, 9, 23, 7, 15),
        DateTime(2026, 9, 28, 7, 15),
      ]);
      expect(reminders.copy?.title, 'bangla');
    },
  );

  test('followed: a change reschedules, off cancels', () async {
    final following = scheduler.follow();
    addTearDown(following.cancel);
    await pumpEventQueue();
    expect(reminders.scheduled, isNull);

    await settings.write(SettingKeys.reminderEnabled, true);
    await pumpEventQueue();
    expect(reminders.scheduled, hasLength(7));

    await settings.write(SettingKeys.reminderTime, (hour: 21, minute: 0));
    await pumpEventQueue();
    expect(reminders.scheduled!.first, DateTime(2026, 9, 21, 21));

    await settings.write(SettingKeys.reminderEnabled, false);
    await pumpEventQueue();
    expect(reminders.scheduled, isNull);
  });

  test('one sync at a time: on, then off at once, ends off', () async {
    await settings.write(SettingKeys.reminderEnabled, true);
    reminders.gate = Completer<void>();
    final on = scheduler.sync();
    await settings.write(SettingKeys.reminderEnabled, false);
    final off = scheduler.sync();

    reminders.gate!.complete();
    await Future.wait(<Future<void>>[on, off]);
    expect(reminders.scheduled, isNull, reason: 'the off came last');
  });

  group('#158: reminder_compose, ten minutes before', () {
    test('queued before the first reminder', () async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderTime, (hour: 7, minute: 15));
      await settings.write(SettingKeys.studyDaysMask, 1 | 4);

      await scheduler.sync();

      // Monday 08:00 to Wednesday 07:05.
      expect(
        work.queued[BackgroundTask.reminderCompose],
        const Duration(days: 1, hours: 23, minutes: 5),
      );
    });

    test('inside the ten minutes: now', () async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderTime, (hour: 8, minute: 5));

      await scheduler.sync();

      expect(work.queued[BackgroundTask.reminderCompose], Duration.zero);
    });

    test('off, or no study day: not queued', () async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await scheduler.sync();
      expect(work.queued, contains(BackgroundTask.reminderCompose));

      await settings.write(SettingKeys.reminderEnabled, false);
      await scheduler.sync();
      expect(work.queued, isNot(contains(BackgroundTask.reminderCompose)));

      await settings.write(SettingKeys.reminderEnabled, true);
      await scheduler.sync();
      expect(work.queued, contains(BackgroundTask.reminderCompose));

      await settings.write(SettingKeys.studyDaysMask, 0);
      await scheduler.sync();
      expect(
        work.queued,
        isNot(contains(BackgroundTask.reminderCompose)),
        reason: 'no study day: the one queued goes',
      );
    });

    test("after today's: the next study day's", () async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await settings.write(SettingKeys.reminderTime, (hour: 8, minute: 30));
      await settings.write(SettingKeys.studyDaysMask, 1 | 4);

      await scheduler.composeAfter(DateTime(2026, 9, 21, 8, 30));

      // Monday 08:00 to Wednesday 08:20, not today's again.
      expect(
        work.queued[BackgroundTask.reminderCompose],
        const Duration(days: 2, minutes: 20),
      );
    });
  });

  test('a setting that moves no reminder reschedules nothing', () async {
    await settings.write(SettingKeys.reminderEnabled, true);
    final following = scheduler.follow();
    addTearDown(following.cancel);
    await pumpEventQueue();
    reminders.scheduled = null;

    await settings.write(SettingKeys.dailyNew, 12);
    await pumpEventQueue();
    expect(reminders.scheduled, isNull);
  });
}
