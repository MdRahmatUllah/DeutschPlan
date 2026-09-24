import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/main.dart';
import 'package:deutschplan/services/reminder_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'data/reminder_scheduler_test.dart' show FakeReminders;

class _Broken extends FakeReminders {
  @override
  Future<void> init(void Function(String link) onTap) =>
      Future<void>.error(StateError('no plugin'));
}

/// #157: what main wires up for the reminder.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
  });

  test('a tapped reminder opens Today', () async {
    final reminders = FakeReminders();
    final opened = <String>[];
    final following = await startReminders(
      container,
      reminders,
      open: opened.add,
    );
    addTearDown(() => following?.cancel());

    reminders.onTap!(PlatformReminderNotifications.link);
    expect(opened, <String>['/today']);
  });

  test("the schedule follows the settings, in the app's language", () async {
    final reminders = FakeReminders();
    final following = await startReminders(container, reminders, open: (_) {});
    addTearDown(() => following?.cancel());

    await settings.write(SettingKeys.reminderEnabled, true);
    await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
    await pumpEventQueue();

    expect(reminders.scheduled, hasLength(7));
    expect(reminders.copy?.title, isNot(isEmpty));
    expect(reminders.copy?.title, isNot('Time for German'));
  });

  test(
    'a plugin that fails to start costs the reminder, not the app',
    () async {
      final following = await startReminders(
        container,
        _Broken(),
        open: (_) {},
      );
      expect(following, isNull);
    },
  );
}
