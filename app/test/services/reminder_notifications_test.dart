import 'package:deutschplan/services/reminder_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reminder's notifications on the plugin itself, through its channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(plugin, (call) async {
          calls.add(call);
          return switch (call.method) {
            'pendingNotificationRequests' => <Map<String, Object?>>[
              <String, Object?>{
                'id': 20260927,
                'title': 'Time for German',
                'body': '12 revisions',
                'payload': PlatformReminderNotifications.link,
              },
            ],
            'getActiveNotifications' => <Map<String, Object?>>[
              // background_downloader's group notification (#506's id).
              <String, Object?>{
                'id': 1009911796,
                'channelId': 'background_downloader',
                'title': 'Model download',
              },
              <String, Object?>{
                'id': 20260926,
                'channelId': PlatformReminderNotifications.channel,
                'payload': PlatformReminderNotifications.link,
              },
            ],
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(plugin, null),
  );

  List<Object?> cancelled() => <Object?>[
    for (final call in calls)
      if (call.method == 'cancel')
        (call.arguments as Map<Object?, Object?>)['id'],
  ];

  test('#509 turning the reminder off cancels its own, scheduled and shown, '
      "and leaves a model download's notification", () async {
    await PlatformReminderNotifications().cancelAll();
    expect(calls.map((call) => call.method), isNot(contains('cancelAll')));
    expect(cancelled(), unorderedEquals(<int>[20260927, 20260926]));
  });

  test(
    '#509 and scheduling it again does the same before it schedules',
    () async {
      await PlatformReminderNotifications().schedule(const <DateTime>[], (
        title: 'Time for German',
        body: '',
        channel: 'Reminder',
      ));
      expect(calls.map((call) => call.method), isNot(contains('cancelAll')));
      expect(cancelled(), isNot(contains(1009911796)));
    },
  );
}
