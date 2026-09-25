import 'dart:async';

import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/reminder_times.dart';
import 'package:deutschplan/services/reminder_notifications.dart';

/// Keeps the scheduled reminders what the settings say (#157): the next
/// week's study days at `reminder_time` while `reminder_enabled` is on, and
/// none while it is off.
///
/// ponytail: a week ahead, rescheduled at every launch and every change. A
/// learner who doesn't open the app for a week hears nothing after it until
/// #158's daily task reschedules in the background.
class ReminderScheduler {
  ReminderScheduler(this._settings, this._notifications, this._now, this._copy);

  final SettingsRepository _settings;
  final ReminderNotifications _notifications;
  final DateTime Function() _now;

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

  /// `reminder_only_when_due` doesn't change the schedule: #158's
  /// `reminder_compose` cancels a day's reminder when nothing is due.
  Future<void> _syncNow() async {
    if (!_settings.read(SettingKeys.reminderEnabled)) {
      return _notifications.cancelAll();
    }
    final time = _settings.read(SettingKeys.reminderTime);
    await _notifications.schedule(
      reminderTimes(
        now: _now(),
        hour: time.hour,
        minute: time.minute,
        studyDaysMask: _settings.read(SettingKeys.studyDaysMask),
      ),
      _copy(_settings.read(SettingKeys.uiLanguage)),
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
