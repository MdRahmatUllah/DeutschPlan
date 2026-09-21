import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The golden harness.
///
/// `docs/05-dev-guide/testing.md`: "Goldens — every screen × light/dark/glass ×
/// phone/tablet, stored under `test/golden/`."
///
/// A screen test declares its cases and nothing else:
///
/// ```dart
/// void main() => goldenTest('today', builder: (_) => const TodayScreen());
/// ```
///
/// which emits `test/golden/today_<mode>_<device>.png` for all six combinations.

/// The two frames `testing.md` names.
enum GoldenDevice {
  /// The reference phone the artboards were drawn at.
  phone(Size(390, 844), 3),

  /// The tablet frame, for the documented two-pane layouts.
  tablet(Size(1024, 768), 2);

  const GoldenDevice(this.size, this.pixelRatio);

  final Size size;
  final double pixelRatio;
}

/// The three modes. Glass renders with blur allowed, so a golden shows the
/// frosted treatment rather than its fallback — the fallback has its own tests
/// in `glass_capability_test.dart`.
enum GoldenMode {
  light,
  dark,
  glass;

  ThemeData get theme => switch (this) {
    GoldenMode.light => AppTheme.light(),
    GoldenMode.dark => AppTheme.dark(),
    GoldenMode.glass => AppTheme.glass(),
  };
}

/// Wraps [child] in everything a screen needs: theme, tokens, localisations,
/// glass capability and the platform chrome for the device.
Widget goldenApp({
  required Widget child,
  required GoldenMode mode,
  required GoldenDevice device,
  AdaptiveChrome? chrome,
}) {
  return GlassCapabilityScope(
    notifier: GlassCapability.always(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: mode.theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      home: AdaptiveChromeScope(
        chrome: chrome ?? AdaptiveChrome.material,
        child: child,
      ),
    ),
  );
}

/// Declares the six goldens for one screen.
///
/// [name] becomes the file stem, so it should match the screen's artboard name
/// in lower case — `today`, `study_front`, `exam_results`.
void goldenTest(
  String name, {
  required WidgetBuilder builder,
  List<GoldenMode> modes = GoldenMode.values,
  List<GoldenDevice> devices = GoldenDevice.values,
  AdaptiveChrome? chrome,
}) {
  for (final mode in modes) {
    for (final device in devices) {
      testWidgets('$name · ${mode.name} · ${device.name}', (tester) async {
        await tester.pumpGolden(
          builder: builder,
          mode: mode,
          device: device,
          chrome: chrome,
        );

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}_${device.name}.png'),
        );
      });
    }
  }
}

extension GoldenTester on WidgetTester {
  /// Sizes the surface to [device] and pumps the widget under the full app
  /// scaffolding, settling animations before the frame is captured.
  Future<void> pumpGolden({
    required WidgetBuilder builder,
    required GoldenMode mode,
    required GoldenDevice device,
    AdaptiveChrome? chrome,
  }) async {
    view
      ..physicalSize = device.size * device.pixelRatio
      ..devicePixelRatio = device.pixelRatio;
    addTearDown(() {
      view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await pumpWidget(
      goldenApp(
        mode: mode,
        device: device,
        chrome: chrome,
        child: Builder(builder: builder),
      ),
    );

    // Settle the theme animation and any entrance motion, so two runs of the
    // same screen produce the same pixels.
    await pumpAndSettle();
  }
}
