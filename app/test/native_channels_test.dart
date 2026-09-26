import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The method channels Dart calls and the ones the native side answers are
/// the same names (#601): a rename on one side alone fails silently at run
/// time, and the Dart tests mock the channel, so only this sees it.
void main() {
  final activity = File(
    'android/app/src/main/kotlin/de/sogda/app/MainActivity.kt',
  ).readAsStringSync();
  final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  for (final (dart, channel, ios) in <(String, String, bool)>[
    ('lib/core/theme/glass_capability.dart', 'sogda/glass', true),
    ('lib/services/device_storage.dart', 'sogda/storage', true),
    // ponytail: iOS has no start report (the fully-drawn call is Android's).
    ('lib/services/start_report.dart', 'sogda/start', false),
  ]) {
    test('#601 $channel is the name Dart, MainActivity'
        '${ios ? ' and AppDelegate' : ''} share', () {
      expect(
        File(dart).readAsStringSync(),
        contains("MethodChannel('$channel')"),
      );
      expect(activity, contains('"$channel"'));
      if (ios) expect(delegate, contains('"$channel"'));
    });
  }
}
