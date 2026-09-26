import 'package:permission_handler/permission_handler.dart';

/// Whether the app may post a notification — and the question that asks.
///
/// #157 builds the notification service around this; S2 page 5 needs only
/// the question, and FR-S2-05 says when to ask it: when the reminder switch
/// is turned on, never before.
abstract interface class NotificationPermission {
  /// Asks, if the platform has not been answered yet, and says whether the
  /// app may post. A learner who has already refused gets the answer without
  /// the dialog — the platform does not ask twice.
  Future<bool> request();

  /// The phone's settings for this app: where a learner who said no can
  /// allow notifications after all (FR-M5-02). False when they can't open.
  Future<bool> openSettings();
}

class PlatformNotificationPermission implements NotificationPermission {
  const PlatformNotificationPermission();

  @override
  Future<bool> request() async =>
      (await Permission.notification.request()).isGranted;

  @override
  Future<bool> openSettings() => openAppSettings();
}

/// #501 (the owner's decision): a model download the learner starts asks
/// to post its progress (Android 13+, iOS), a line on screen saying why
/// (`modelsNotifyWhy`). The reminder asks only when switched on (FR-S2-05);
/// this is the only other asker. A refusal, or no plugin, still downloads:
/// it just goes without a notification.
Future<void> askToNotifyDownload(NotificationPermission permission) async {
  try {
    await permission.request();
  } on Object {
    // No notification, not no download.
  }
}
