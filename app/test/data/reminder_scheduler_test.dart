import 'dart:async';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/reminder_scheduler.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
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

  @override
  Future<void> cancelAll() async {
    scheduled = null;
    cancelled++;
  }
}

/// #157: the reminders kept to the settings.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeReminders reminders;
  late ReminderScheduler scheduler;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    reminders = FakeReminders();
    scheduler = ReminderScheduler(
      settings,
      reminders,
      // Monday 21 September 2026, the morning.
      () => DateTime(2026, 9, 21, 8),
      (language) => (title: language.name, body: 'body', channel: 'channel'),
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
