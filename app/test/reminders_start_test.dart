import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/main.dart';
import 'package:sogda/services/background_work.dart';
import 'package:sogda/services/reminder_notifications.dart';

import 'data/reminder_scheduler_test.dart' show FakeReminders, FakeWork;
import 'services/widget_snapshot_test.dart' show FakeWidgets;

class _Broken extends FakeReminders {
  @override
  Future<void> init(void Function(String link) onTap) =>
      Future<void>.error(StateError('no plugin'));
}

/// #157, #158: what main wires up for the reminder and the background tasks.
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
      FakeWork(),
      widgets: FakeWidgets(),
      open: opened.add,
    );
    addTearDown(() => following?.cancel());

    reminders.onTap!(PlatformReminderNotifications.link);
    expect(opened, <String>[PlatformReminderNotifications.link]);
  });

  test('FR-S1-04 a tap that started the app opens what it links to', () async {
    final reminders = FakeReminders()
      ..launched = PlatformReminderNotifications.link;
    final opened = <String>[];
    final following = await startReminders(
      container,
      reminders,
      FakeWork(),
      widgets: FakeWidgets(),
      open: opened.add,
    );
    addTearDown(() => following?.cancel());
    expect(opened, <String>[PlatformReminderNotifications.link]);
  });

  test('an ordinary start opens nothing', () async {
    final opened = <String>[];
    final following = await startReminders(
      container,
      FakeReminders(),
      FakeWork(),
      widgets: FakeWidgets(),
      open: opened.add,
    );
    addTearDown(() => following?.cancel());
    expect(opened, isEmpty);
  });

  test("the schedule follows the settings, in the app's language", () async {
    final reminders = FakeReminders();
    final work = FakeWork();
    final following = await startReminders(
      container,
      reminders,
      work,
      widgets: FakeWidgets(),
      open: (_) {},
    );
    addTearDown(() => following?.cancel());

    await settings.write(SettingKeys.reminderEnabled, true);
    await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
    await pumpEventQueue();

    expect(reminders.scheduled, hasLength(7));
    expect(reminders.copy?.title, isNot(isEmpty));
    expect(reminders.copy?.title, isNot('Time for German'));
    expect(work.queued, contains(BackgroundTask.reminderCompose));
  });

  test("#158 #711: tonight's plan_pregenerate, and with a widget placed the "
      'hourly widget', () async {
    final work = FakeWork();
    final following = await startReminders(
      container,
      FakeReminders(),
      work,
      widgets: FakeWidgets(),
      open: (_) {},
    );
    addTearDown(() => following?.cancel());

    expect(work.started, isTrue);
    // 08:00 to 00:05 tomorrow.
    expect(
      work.queued[BackgroundTask.planPregenerate],
      const Duration(hours: 16, minutes: 5),
    );
    expect(work.hourlyTasks, <BackgroundTask>{BackgroundTask.widgetRefresh});
  });

  test('#711 no widget placed: no hourly widget_refresh, and the one an '
      'older start queued is cancelled', () async {
    final work = FakeWork()..hourlyTasks.add(BackgroundTask.widgetRefresh);
    final following = await startReminders(
      container,
      FakeReminders(),
      work,
      widgets: FakeWidgets()..onHome = false,
      open: (_) {},
    );
    addTearDown(() => following?.cancel());

    expect(work.hourlyTasks, isEmpty);
    expect(work.queued, contains(BackgroundTask.planPregenerate));
  });

  test('#625 a notifications plugin that fails to start still queues the '
      "widget and tonight's plan_pregenerate", () async {
    final work = FakeWork();
    final following = await startReminders(
      container,
      _Broken(),
      work,
      widgets: FakeWidgets(),
      open: (_) {},
    );
    await pumpEventQueue();

    expect(following, isNull);
    expect(work.started, isTrue);
    expect(
      work.queued[BackgroundTask.planPregenerate],
      const Duration(hours: 16, minutes: 5),
    );
    expect(work.hourlyTasks, <BackgroundTask>{BackgroundTask.widgetRefresh});
  });

  test(
    'a plugin that fails to start costs the reminder, not the app',
    () async {
      final following = await startReminders(
        container,
        _Broken(),
        FakeWork(),
        widgets: FakeWidgets(),
        open: (_) {},
      );
      expect(following, isNull);
    },
  );
}
