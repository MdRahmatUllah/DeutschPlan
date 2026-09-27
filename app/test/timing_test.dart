import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'timing.dart';

/// #683: a test that sleeps a fixed time for work to land passes on an idle
/// machine and fails on a busy one. Work in this isolate (an in-memory
/// database) gets `pumpEventQueue`'s turns; real I/O gets `until` from
/// `timing.dart`, which polls with a timeout.
void main() {
  // Sleeps that a busy machine can only make longer, never fail: how many
  // each file has, and why.
  const allowed = <String, (int, String)>{
    'test/timing.dart': (1, "until's own poll"),
    'test/data/model_repository_test.dart': (
      1,
      'the filesystem needs wall time to record a different mtime',
    ),
    'test/db/app_database_open_test.dart': (
      1,
      'holds a transaction open so the other connection has to wait for it',
    ),
    'test/services/tts/supertonic_tts_test.dart': (
      1,
      'a wait for something not to happen: too short only misses a bug',
    ),
  };
  final sleep = RegExp(
    r'\.delayed\(\s*(const\s+)?Duration\(\s*\w+:\s*[1-9]|\bsleep\(',
  );

  test('#683 no test sleeps a fixed time for work to land', () {
    final found = <String>[];
    final counts = <String, int>{};
    for (final file in Directory('test').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      final text = file.readAsStringSync();
      for (final match in sleep.allMatches(text)) {
        counts[path] = (counts[path] ?? 0) + 1;
        if (!allowed.containsKey(path)) {
          final line = '\n'.allMatches(text.substring(0, match.start)).length;
          found.add('$path:${line + 1}');
        }
      }
    }

    expect(found, isEmpty);
    for (final MapEntry(key: path, value: (count, why)) in allowed.entries) {
      expect(counts[path] ?? 0, count, reason: '$path: $why');
    }
  });

  test(
    '#683 fastestOf is the fastest run, not the first or the last',
    () async {
      var run = 0;
      final fastest = await fastestOf(3, () {
        // Busy, not asleep: the first and the last runs take 50 ms.
        final clock = Stopwatch()..start();
        if (run++ != 1) {
          while (clock.elapsedMilliseconds < 50) {}
        }
      });
      expect(fastest, lessThan(const Duration(milliseconds: 50)));
    },
  );

  test(
    '#683 until waits for its condition, and fails at its timeout',
    () async {
      var ready = false;
      unawaited(Future(() => ready = true));
      await until(() => ready);
      expect(ready, isTrue);

      await expectLater(
        until(
          () => false,
          timeout: const Duration(milliseconds: 20),
        ).timeout(const Duration(seconds: 5)),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.duration,
            'duration',
            const Duration(milliseconds: 20),
          ),
        ),
      );
    },
  );
}
