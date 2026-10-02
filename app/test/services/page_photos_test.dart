import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/services/page_photos.dart';

import '../db/content_fixture.dart' show tempDir;

/// #1229: what ML Kit's text recognition brings into the app, and #1298:
/// what D1 leaves of image_picker's copies.
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

  test('#1298 BR-DOC-05 a discarded photo takes image_picker\'s copy from '
      'before the resize with it, the camera\'s and the gallery\'s, and '
      'nothing else', () async {
    final cache = tempDir('sg_picker_cache');
    File put(String path) => File('${cache.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync('EXIF Make SQA');
    const folder = 'ee5dc629-0b1e-4c1d-9a5e-2f6d8e7a1b3c';
    const camera = '512d6eb9-7c2a-4e8b-b1d4-0a9c3f5e6d72123456.jpg';
    final gallery = put('$folder/126.jpg');
    final galleryScaled = put('scaled_126.jpg');
    final shot = put(camera);
    final shotScaled = put('scaled_$camera');
    // Never resized: the copy is what D1 holds.
    final small = put('0f1e2d3c-4b5a-4968-8776-655443322110/small.png');
    // Not ours to drop: another photo still in D1, another plugin's file.
    final pending = put('9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d/127.jpg');
    final other = put('file_picker/letter.pdf');

    await PlatformPagePhotos().discard(<String>[
      galleryScaled.path,
      shotScaled.path,
      small.path,
    ]);
    for (final gone in <File>[gallery, galleryScaled, shot, shotScaled]) {
      expect(gone.existsSync(), isFalse, reason: gone.path);
    }
    expect(Directory('${cache.path}/$folder').existsSync(), isFalse);
    expect(small.parent.existsSync(), isFalse);
    expect(pending.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
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
