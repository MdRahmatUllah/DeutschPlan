import 'dart:async';

/// Waits for real work (disk I/O, another isolate) by polling until [done]
/// holds, for at most [timeout] (#683), then throws a [TimeoutException]: a
/// wait that gave up is the failure, not whatever the test asserts next. In a
/// widget test, call it inside `tester.runAsync`.
///
/// A fixed sleep long enough for a loaded machine wastes that on every run,
/// and one short enough to be quick flakes. Work that stays in this isolate,
/// as an in-memory database's does, needs no clock at all: `pumpEventQueue`
/// gives it event-loop turns, which a busy machine doesn't change.
Future<void> until(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed >= timeout) {
      throw TimeoutException('until: the condition never held', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// The fastest of [runs] runs of [body] (#683). One sample measures whatever
/// else the machine was doing; the fastest is the one that measures the code,
/// and a real slowdown moves every sample.
Future<Duration> fastestOf(int runs, FutureOr<void> Function() body) async {
  var best = const Duration(days: 1);
  for (var i = 0; i < runs; i++) {
    final clock = Stopwatch()..start();
    await body();
    if (clock.elapsed < best) best = clock.elapsed;
  }
  return best;
}
