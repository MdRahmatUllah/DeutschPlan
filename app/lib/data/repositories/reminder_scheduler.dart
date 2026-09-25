import 'dart:async';

import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/reminder_times.dart';
import 'package:deutschplan/services/background_work.dart';
import 'package:deutschplan/services/reminder_notifications.dart';

/// Keeps the scheduled reminders what the settings say (#157): the next
/// week's study days at `reminder_time` while `reminder_enabled` is on, and
/// none while it is off. A week ahead, rescheduled at every launch, every
/// change and every night's `plan_pregenerate` (#158); each sync also queues
/// `reminder_compose` ten minutes before the next one.
class ReminderScheduler {
  ReminderScheduler(
    this._settings,
    this._notifications,
    this._now,
    this._copy,
    this._work,
  );

  final SettingsRepository _settings;
  final ReminderNotifications _notifications;
  final DateTime Function() _now;
  final BackgroundWork _work;

  /// How long before a reminder `reminder_compose` writes its text.
  static const Duration composeLead = Duration(minutes: 10);

  /// The words, in the learner's app language.
  final ReminderCopy Function(UiLanguage language) _copy;

  /// The settings that move a reminder.
  static const Set<SettingKey<Object?>> keys = <SettingKey<Object?>>{
    SettingKeys.reminderEnabled,
    SettingKeys.reminderTime,
    SettingKeys.studyDaysMask,
    SettingKeys.uiLanguage,
  };

  Future<void> _last = Future<void>.value();

  /// One at a time. The settings arrive together (restart setup writes three),
  /// and a sync still scheduling "on" while the next one cancels for "off"
  /// would schedule after the cancel, leaving reminders the learner turned
  /// off.
  Future<void> sync() =>
      _last = _last.catchError((Object _) {}).then((_) => _syncNow());

  /// `reminder_only_when_due` doesn't change the schedule: `reminder_compose`
  /// cancels a day's reminder when nothing is due.
  Future<void> _syncNow() async {
    if (!_settings.read(SettingKeys.reminderEnabled)) {
      await _work.cancel(BackgroundTask.reminderCompose);
      return _notifications.cancelAll();
    }
    final times = _times(_now());
    await _notifications.schedule(
      times,
      _copy(_settings.read(SettingKeys.uiLanguage)),
    );
    await _composeBefore(times);
  }

  /// Queues `reminder_compose` for the first reminder after [from]: what the
  /// task does once it has written [from]'s.
  Future<void> composeAfter(DateTime from) =>
      _settings.read(SettingKeys.reminderEnabled)
      ? _composeBefore(_times(from))
      : _work.cancel(BackgroundTask.reminderCompose);

  List<DateTime> _times(DateTime from) {
    final time = _settings.read(SettingKeys.reminderTime);
    return reminderTimes(
      now: from,
      hour: time.hour,
      minute: time.minute,
      studyDaysMask: _settings.read(SettingKeys.studyDaysMask),
    );
  }

  /// Ten minutes before the first of [times], or now inside those ten: a
  /// sync at 19:25 has just put back the plain 19:30 text.
  Future<void> _composeBefore(List<DateTime> times) async {
    if (times.isEmpty) return _work.cancel(BackgroundTask.reminderCompose);
    final wait = times.first.subtract(composeLead).difference(_now());
    await _work.after(
      BackgroundTask.reminderCompose,
      wait.isNegative ? Duration.zero : wait,
    );
  }

  /// Syncs now, and again whenever one of [keys] changes.
  StreamSubscription<SettingKey<Object?>> follow() {
    unawaited(sync());
    return _settings.changes
        .where(keys.contains)
        .listen((_) => unawaited(sync()));
  }
}
