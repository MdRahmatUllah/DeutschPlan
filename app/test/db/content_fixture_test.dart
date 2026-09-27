import 'package:flutter_test/flutter_test.dart';

import 'content_fixture.dart';

/// The fixture's temp folders don't outlive the test file: the config runs
/// [deleteTempDirs] after its last test.
void main() {
  test('#695 deleteTempDirs takes every tempDir and the course copy', () {
    final dir = tempDir('sogda_695');
    final course = realContent();

    deleteTempDirs();

    expect(dir.existsSync(), isFalse);
    expect(course.existsSync(), isFalse);
    expect(realContent().existsSync(), isTrue, reason: 'a fresh copy after');
  });
}
