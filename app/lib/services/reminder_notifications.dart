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

  /// The link of the reminder whose tap started the app, if one did.
  Future<String?> launchedWith();

  /// Replaces every scheduled reminder with one at each of [at].
  Future<void> schedule(List<DateTime> at, ReminderCopy copy);

  /// Replaces the reminder of [at]'s day with one at [at] (#158's
  /// `reminder_compose`).
  Future<void> replace(DateTime at, ReminderCopy copy);

  /// Cancels the reminder of [day]'s date, if one is scheduled.
  Future<void> cancelDay(DateTime day);

  /// Cancels every reminder, scheduled or shown, and nothing else the app
  /// shows: the model downloads' notification shares it (#509).
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

  /// One reminder a day, so the date is its id: `reminder_compose` finds
  /// today's without keeping a list.
  static int idFor(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

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
  Future<String?> launchedWith() async {
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp ?? false
        ? launch?.notificationResponse?.payload ?? link
        : null;
  }

  @override
  Future<void> schedule(List<DateTime> at, ReminderCopy copy) async {
    await cancelAll();
    for (final instant in at) {
      await replace(instant, copy);
    }
  }

  @override
  Future<void> replace(DateTime at, ReminderCopy copy) => _plugin.zonedSchedule(
    id: idFor(at),
    // The instant, in UTC: it is already the local 19:30 of its day.
    scheduledDate: tz.TZDateTime.from(at, tz.UTC),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        copy.channel,
        // Collapsed, the first line: "12 revisions · 7 new · about 9 min".
        styleInformation: BigTextStyleInformation(copy.body),
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: copy.title,
    body: copy.body,
    payload: link,
  );

  @override
  Future<void> cancelDay(DateTime day) => _plugin.cancel(id: idFor(day));

  /// #509: not the plugin's `cancelAll`, which is the platform's, every
  /// notification the app has: a model download's too (#156).
  @override
  Future<void> cancelAll() async {
    // Only the reminder schedules any.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(id: pending.id);
    }
    List<ActiveNotification> active;
    try {
      active = await _plugin.getActiveNotifications();
    } on Object {
      // A platform that can't list them (desktop, a test): none to clear.
      active = const <ActiveNotification>[];
    }
    for (final shown in active) {
      final id = shown.id;
      if (id != null && (shown.channelId == channel || shown.payload == link)) {
        await _plugin.cancel(id: id, tag: shown.tag);
      }
    }
  }
}
