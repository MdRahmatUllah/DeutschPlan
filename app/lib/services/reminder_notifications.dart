import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// What a reminder says, in the learner's language.
typedef ReminderCopy = ({String title, String body, String channel});

/// The daily reminder's notifications (`notifications-widget.md`, #157).
///
/// An interface so the schedule can be tested without a phone, as
/// `NotificationPermission` is. Asking for the permission is that class's
/// job, and only when the learner switches the reminder on (FR-S2-05,
/// FR-M5-02); this one never asks.
abstract interface class ReminderNotifications {
  /// Sets the plugin up. [onTap] gets the link a tapped reminder carries.
  Future<void> init(void Function(String link) onTap);

  /// Replaces every scheduled reminder with one at each of [at].
  Future<void> schedule(List<DateTime> at, ReminderCopy copy);

  Future<void> cancelAll();
}

/// [ReminderNotifications] on `flutter_local_notifications`: an inexact
/// alarm on Android (no exact-alarm permission to ask for), a
/// UNUserNotificationCenter request on iOS.
class PlatformReminderNotifications implements ReminderNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Where a tapped reminder goes (`navigation.md`).
  static const String link = 'deutschplan://today';

  static const String channel = 'reminder';

  @override
  Future<void> init(void Function(String link) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Not here: the permission is asked when the reminder goes on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTap(response.payload ?? link),
    );
  }

  @override
  Future<void> schedule(List<DateTime> at, ReminderCopy copy) async {
    await _plugin.cancelAll();
    for (final (id, instant) in at.indexed) {
      await _plugin.zonedSchedule(
        id: id,
        // The instant, in UTC: it is already the local 19:30 of its day.
        scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channel, copy.channel),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: copy.title,
        body: copy.body,
        payload: link,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
