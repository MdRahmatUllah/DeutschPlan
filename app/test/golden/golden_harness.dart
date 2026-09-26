import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';

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

/// The text sizes every golden screen is also checked at (#165).
const List<double> textAuditScales = <double>[1.5, 2];

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
  bool still = true,
  List<Override>? overrides,
}) {
  final app = GlassCapabilityScope(
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
          data: MediaQuery.of(context).copyWith(
            disableAnimations: still,
            // Large text as an Android phone scales it, not as Flutter's
            // test scaler does (linear): a box sized from a font size then
            // shows it doesn't grow (#165). iOS keeps the linear one.
            textScaler: chrome == AdaptiveChrome.cupertino
                ? null
                : _phone(MediaQuery.textScalerOf(context)),
          ),
          child: AdaptiveChromeScope(
            chrome: chrome ?? AdaptiveChrome.material,
            child: child,
          ),
        ),
      ),
    ),
  );
  // Over the whole app, as `main.dart` has it, for a screen that shows a
  // sheet: a route pushed on the app's navigator sits above `home`, so a
  // scope inside the screen would not reach it.
  return overrides == null
      ? app
      : ProviderScope(overrides: overrides, child: app);
}

/// Declares the six goldens for one screen.
///
/// [name] becomes the file stem, so it should match the screen's artboard name
/// in lower case — `today`, `study_front`, `exam_results`.
///
/// [act] drives the screen into the state its artboard shows — an answer
/// typed and checked — before the frame is taken.
///
/// [overrides] puts a `ProviderScope` over the whole app, for a screen that
/// opens a sheet or pane (W1): the route sits above `home`, out of reach of a
/// scope inside the screen.
///
/// [still] false lets a one-off animation play — T6's confetti, which the
/// artboard draws at rest. Only for modes without a drifting aurora: it
/// never settles.
void goldenTest(
  String name, {
  required WidgetBuilder builder,
  List<GoldenMode> modes = GoldenMode.values,
  List<GoldenDevice> devices = GoldenDevice.values,
  AdaptiveChrome? chrome,
  Future<void> Function(WidgetTester tester)? act,
  bool still = true,
  List<Override>? overrides,
  bool textAudit = true,
  double? textScale,
}) {
  // #165: the same screen at 150 % and 200 % text, on the phone in light:
  // nothing cut, no word broken mid-word, no layout error. The text size is
  // the axis here, not the theme; one golden per screen and chrome carries
  // it, so a variant that only restages a state can opt out.
  if (textAudit) {
    for (final scale in textAuditScales) {
      testWidgets('$name · text ${(scale * 100).round()} %', (tester) async {
        textAt(tester, scale);
        await tester.pumpGolden(
          builder: builder,
          mode: GoldenMode.light,
          device: GoldenDevice.phone,
          chrome: chrome,
          still: still,
          overrides: overrides,
        );
        if (act != null) {
          await act(tester);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            settleTimeout,
          );
        }
        expect(tester.takeException(), isNull);
        expectNothingClipped(tester);
        expectNoWordBroken(tester);
      });
    }
  }
  for (final mode in modes) {
    for (final device in devices) {
      testWidgets(
        '$name · ${mode.name} · ${device.name}',
        tags: <String>[goldenTag],
        (tester) async {
          // #165: a golden at a learner's larger text size.
          if (textScale != null) textAt(tester, textScale);
          await tester.pumpGolden(
            builder: builder,
            mode: mode,
            device: device,
            chrome: chrome,
            still: still,
            overrides: overrides,
          );
          if (act != null) {
            await act(tester);
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              settleTimeout,
            );
          }

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
  // #162: every control a screen reader can press has a name, checked on
  // every case once (phone, light), after its act.
  testWidgets('$name · labels', tags: <String>[goldenTag], (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpGolden(
      builder: builder,
      mode: GoldenMode.light,
      device: GoldenDevice.phone,
      chrome: chrome,
      still: still,
      overrides: overrides,
    );
    if (act != null) {
      await act(tester);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        settleTimeout,
      );
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// [linear] as Android 14+ gives it, when text is scaled at all.
TextScaler _phone(TextScaler linear) {
  final factor = linear.scale(1);
  return factor == 1 ? linear : AndroidTextScaler(factor);
}

extension GoldenTester on WidgetTester {
  /// Sizes the surface to [device] and pumps the widget under the full app
  /// scaffolding, settling animations before the frame is captured.
  Future<void> pumpGolden({
    required WidgetBuilder builder,
    required GoldenMode mode,
    required GoldenDevice device,
    AdaptiveChrome? chrome,
    bool still = true,
    List<Override>? overrides,
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
        still: still,
        overrides: overrides,
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
