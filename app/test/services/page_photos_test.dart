import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1229: what ML Kit's text recognition brings into the app.
///
/// These pin the source files, against someone deleting the lines. The real
/// proof is the release APK's merged manifest, where other libraries add
/// their own: `aapt2 dump xmltree --file AndroidManifest.xml
/// app-release.apk | grep -iE "datatransport|firebase|clearcut|measurement"`
/// (BR-PRIV-01), run in the PR's device check.
void main() {
  test('BR-PRIV-01 ML Kit reads the pages, and its usage metrics have no way '
      'out: DataTransport\'s backend and schedulers are removed', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    for (final component in <String>[
      'com.google.android.datatransport.runtime.backends.TransportBackendDiscovery',
      'com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService',
      'com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver',
    ]) {
      expect(
        manifest,
        contains('android:name="$component" tools:node="remove"'),
        reason: component,
      );
    }
  });

  test('release builds keep what ML Kit finds by name (R8)', () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(rules, contains('-keep class com.google.mlkit.** { *; }'));
    expect(
      rules,
      contains('-keep class com.google.android.gms.internal.mlkit_** { *; }'),
    );
  });
}
