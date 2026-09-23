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
}

class PlatformNotificationPermission implements NotificationPermission {
  const PlatformNotificationPermission();

  @override
  Future<bool> request() async =>
      (await Permission.notification.request()).isGranted;
}
