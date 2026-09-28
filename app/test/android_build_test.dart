import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android build's own supply chain.
void main() {
  test("#705 the Gradle wrapper pins its distribution's SHA-256", () {
    final wrapper = File('android/gradle/wrapper/gradle-wrapper.properties')
        .readAsStringSync();
    // Gradle refuses a download that doesn't match it; without the line it
    // runs whatever the URL serves.
    expect(
      RegExp(
        r'^distributionSha256Sum=[0-9a-f]{64}\s*$',
        multiLine: true,
      ).hasMatch(wrapper),
      isTrue,
    );
  });

  test('#705 a release build without key.properties fails unless it opts in '
      'to the debug key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    bool has(String pattern) => RegExp(pattern).hasMatch(gradle);
    // Once the task graph is known, before any task runs: `flutter build apk
    // --release` runs assembleRelease, `flutter build appbundle` bundleRelease.
    expect(
      has(
        r'gradle\.taskGraph\.whenReady \{\s*'
        r'val release = listOf\("assembleRelease", "bundleRelease"\)\s*'
        r'\.any \{ hasTask\("\$\{project\.path\}:\$it"\) \}',
      ),
      isTrue,
    );
    expect(
      has(
        r'if \(release && keyProperties\.isEmpty && !allowDebugSigning\) \{'
        r'\s*throw GradleException\(',
      ),
      isTrue,
    );
    // -P allowDebugSigning=true (flutter's -P, --android-project-arg) or
    // ORG_GRADLE_PROJECT_allowDebugSigning: both are Gradle properties, and
    // =false doesn't opt in.
    expect(
      has(
        r'val allowDebugSigning = providers\.gradleProperty\("allowDebugSigning"\)'
        r'\.orNull\s*\.let \{ it != null && it != "false" \}',
      ),
      isTrue,
    );
  });
}
