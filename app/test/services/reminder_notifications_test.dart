import 'dart:io';

import 'package:sogda/router/deep_links.dart';
import 'package:sogda/services/reminder_notifications.dart';
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
            'initialize' => true,
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

  test('#602 its small icon is the tiles drawable the app ships, white on '
      'transparent, and kept in a shrunk release build', () async {
    await PlatformReminderNotifications().init((_) {});

    final init = calls.singleWhere((call) => call.method == 'initialize');
    final icon =
        (init.arguments as Map<Object?, Object?>)['defaultIcon'] as String?;
    expect(icon, PlatformReminderNotifications.smallIcon);
    // A drawable: the launcher's mipmap is a colour square, which the status
    // bar draws as a white blob.
    final name = RegExp(r'^@drawable/(\w+)$').firstMatch(icon!)?.group(1);
    expect(name, isNotNull, reason: icon);
    final file = File('android/app/src/main/res/drawable/$name.xml');
    expect(file.existsSync(), isTrue, reason: file.path);
    final xml = file.readAsStringSync();
    expect(xml, contains('<vector'));
    // Named only from Dart, so the release build's resource shrinking would
    // strip it without this.
    final keep = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final kept = RegExp(r'tools:keep="([^"]*)"').firstMatch(keep)?.group(1);
    expect(kept?.split(','), contains('@drawable/$name'));
    expect(
      RegExp(r'(?:fill|stroke)Color="([^"]+)"')
          .allMatches(xml)
          .map((match) => match.group(1))
          .toSet(),
      <String>{'#FFFFFFFF'},
    );
  });

  test("#601 a tapped reminder opens Today through the app's own scheme", () {
    // A link in an older name's scheme would fall through to the fallback.
    final link = Uri.parse(PlatformReminderNotifications.link);
    expect(link.scheme, deepLinkScheme);
    expect(resolveDeepLink(link), '/today');
  });
}
