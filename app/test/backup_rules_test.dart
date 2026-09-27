import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BR-PRIV-02 (#607): nothing of the learner's leaves the phone through
/// Android's backup or a device-to-device copy.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  final application = RegExp(r'<application\b[^>]*>')
      .firstMatch(manifest)!
      .group(0)!;

  test('BR-PRIV-02 the application opts out of Auto Backup', () {
    expect(application, contains('android:allowBackup="false"'));
    expect(application, contains('android:fullBackupContent="false"'));
  });

  test('BR-PRIV-02 Android 12+ copies nothing to a backup or a new phone', () {
    final match = RegExp(r'android:dataExtractionRules="@xml/(\w+)"')
        .firstMatch(application);
    expect(match, isNotNull);
    final rules = File('android/app/src/main/res/xml/${match!.group(1)}.xml')
        .readAsStringSync();
    const domains = <String>[
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ];
    for (final section in <String>['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(rules)?.group(1);
      expect(body, isNotNull, reason: section);
      expect(body, isNot(contains('<include')), reason: section);
      for (final domain in domains) {
        expect(
          body,
          contains('<exclude domain="$domain" />'),
          reason: '$section keeps $domain',
        );
      }
    }
  });
}
