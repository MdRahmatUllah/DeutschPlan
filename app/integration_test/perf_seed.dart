// #818: seeds user.db with a year of study (year_profile.dart) on the device,
// for `tools/perf.py start --profile year`. Built as a release APK of its
// own, installed, run once; then the app's own release APK is installed over
// it: the same id and the same key, so user.db stays. The measured APK is
// the one that ships, untouched.
//
//   flutter build apk --release --target-platform android-x64 \
//       -t integration_test/perf_seed.dart
//
// It says `perf-seed: done` (or `perf-seed: failed`) in logcat, which
// perf.py waits for.

import 'package:flutter/widgets.dart';

import 'year_profile.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await seedInstalledApp();
    // Once closed: perf.py stops the app the moment it reads this.
    debugPrint('perf-seed: done');
  } on Object catch (error) {
    debugPrint('perf-seed: failed: $error');
  }
}
