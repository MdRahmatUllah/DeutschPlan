import 'package:sogda/features/splash/splash_screen.dart';

import 'golden_harness.dart';

/// S1 · Splash goldens — #85.
///
/// Six files: light, dark and glass on the phone and tablet frames, each to be
/// diffed against its own artboard set. The progress line is off, which is the
/// state the artboards show at rest — the slow-start variant is behaviour and
/// is covered in `test/features/splash_screen_test.dart` rather than by a
/// seventh image nobody would compare against anything.
void main() {
  goldenTest('splash', builder: (context) => const SplashScreen());
  // #686 ST-9: an app update's caption. One image; the text audit is the
  // point, in English and Bangla.
  goldenTest(
    'splash_updating',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) => const SplashScreen(updating: true),
  );
}
