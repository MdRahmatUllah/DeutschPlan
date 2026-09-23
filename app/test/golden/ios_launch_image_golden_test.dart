import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// The iOS launch image — #238.
///
/// A storyboard cannot run Dart, so the mark it shows has to be a PNG. It is
/// rendered here from [SplashLockup], the column Flutter's first frame
/// centres, straight into the image set: `make update-goldens` regenerates it, and
/// `goldens-verify` fails the moment the widget and the PNG disagree.
///
/// Transparent, because the storyboard paints the field from `SplashField`.
/// The lockup's empty progress slot keeps S1's space under the mark, so the
/// storyboard centres the image the way Flutter centres the column. Light and
/// dark only: a launch screen has no glass.
void main() {
  const imageSet = '../../ios/Runner/Assets.xcassets/LaunchImage.imageset';
  Widget lockup(GoldenMode mode) => Directionality(
    textDirection: TextDirection.ltr,
    child: Theme(
      data: mode.theme,
      child: const Center(child: SplashLockup()),
    ),
  );

  for (final mode in <GoldenMode>[GoldenMode.light, GoldenMode.dark]) {
    for (final scale in <int>[1, 2, 3]) {
      testWidgets(
        'the ${mode.name} launch image at @${scale}x',
        tags: <String>[goldenTag],
        (tester) async {
          // Measured, not written down: the wordmark is as wide as Inter makes
          // it, and a canvas copied by hand would crop it when the font changes.
          await tester.pumpWidget(lockup(mode));
          final size = tester.getSize(find.byType(SplashLockup));
          tester.view.devicePixelRatio = scale.toDouble();
          tester.view.physicalSize =
              Size(size.width.ceilToDouble(), size.height.ceilToDouble()) *
              scale.toDouble();
          addTearDown(tester.view.reset);
          await tester.pumpWidget(lockup(mode));

          final dark = mode == GoldenMode.dark ? '-dark' : '';
          final density = scale == 1 ? '' : '@${scale}x';
          await expectLater(
            find.byType(SplashLockup),
            matchesGoldenFile('$imageSet/LaunchImage$dark$density.png'),
          );
        },
      );
    }
  }
}
