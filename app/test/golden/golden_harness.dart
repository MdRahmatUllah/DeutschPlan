import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
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

/// How long [GoldenTester.pumpGolden] waits for animations before giving up.
const Duration settleTimeout = Duration(seconds: 10);

/// Marks every golden test, so `make test` can leave them out.
///
/// Golden files are pixel comparisons and text rendering is not identical
/// across platforms — hinting, subpixel positioning and antialiasing all
/// differ. These are generated and verified on ONE platform; running them
/// elsewhere produces diffs that are about the renderer, not the design.
const String goldenTag = 'golden';

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
///
/// Chrome defaults to Material because `testing.md` sizes the matrix as
/// light/dark/glass × phone/tablet, with no platform axis. Pass [chrome] to
/// render the Cupertino path — the design sets do ship ios-light and ios-dark,
/// and #37 built that path — but whether iOS gets the full matrix, a phone-only
/// pass, or only the screens whose chrome differs is a decision for #151, not
/// something this default has already made.
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
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          // Goldens are still. Repeating animations — AuroraBackdrop drifts on
          // 18-24 s loops — would otherwise burn the settle budget and capture
          // a different frame every run. The backdrop already holds still
          // under reduce-motion (#Y03), so the golden reuses that rather than
          // needing a test-only switch.
          //
          // `copyWith`, not a fresh `MediaQueryData`: a const one carries
          // `size: Size.zero`, and anything that measures the screen — a
          // `Scaffold` reading insets, a layout builder — then lays out
          // against nothing. It renders, so it looks like a screen with a
          // layout bug rather than a harness with one.
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AdaptiveChromeScope(
            chrome: chrome ?? AdaptiveChrome.material,
            child: child,
          ),
        ),
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
      testWidgets(
        '$name · ${mode.name} · ${device.name}',
        tags: <String>[goldenTag],
        (tester) async {
          await tester.pumpGolden(
            builder: builder,
            mode: mode,
            device: device,
            chrome: chrome,
          );

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/${name}_${mode.name}_${device.name}.png',
            ),
          );
        },
      );
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
    // same screen produce the same pixels — but bounded. A repeating animation
    // never settles, and an unbounded wait turns that into a stalled suite
    // rather than a failure. AuroraBackdrop (#35) drifts on 18-24 s loops and
    // must expose the same stillness it already needs for reduce-motion.
    await pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      settleTimeout,
    );
  }
}
