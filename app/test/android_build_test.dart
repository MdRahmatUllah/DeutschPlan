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
}
