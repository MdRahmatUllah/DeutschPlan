import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter/semantics.dart' show SemanticsNode;
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
    // #478: and each is big enough to press, as its platform asks.
    await expectLater(
      tester,
      meetsGuideline(
        chrome == AdaptiveChrome.cupertino
            ? const _IosTapTargets()
            : const _AndroidTapTargets(),
      ),
    );
    if (chrome != AdaptiveChrome.cupertino) expectIconButtonsTipped(tester);
    expectTargetsApart(tester);
    handle.dispose();
  });
}

/// iOS's 44 pt, less a sliding segmented control's segments. Flutter's
/// control draws them 28 pt, and UIKit's own (32 pt) isn't held to 44 either
/// (#478).
/// ponytail: growing the control to 44 is the owner's call; drop this then.
class _IosTapTargets extends MinimumTapTargetGuideline {
  const _IosTapTargets()
    : super(
        size: const Size(44, 44),
        link: 'https://developer.apple.com/design/human-interface-guidelines/accessibility',
      );

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      _AndroidTapTargets.dense(node) || super.shouldSkipNode(node);
}

/// Android's 48 dp, less a node in a control too dense to grow, which says
/// so with a `dense:` semantics identifier on itself or an ancestor (Me's
/// step badges, iOS's segmented control, #478).
class _AndroidTapTargets extends MinimumTapTargetGuideline {
  const _AndroidTapTargets()
    : super(
        size: const Size(48, 48),
        link: 'https://support.google.com/accessibility/android/answer/7101858',
      );

  static bool dense(SemanticsNode node) {
    for (SemanticsNode? at = node; at != null; at = at.parent) {
      if (at.getSemanticsData().identifier.startsWith('dense:')) return true;
    }
    return false;
  }

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      dense(node) || super.shouldSkipNode(node);
}

/// #478: a grown target claims the space around its control, so it must
/// never reach another target's drawn box, or it takes that one's taps.
/// Only the targets a tap can reach: a screen under a sheet's scrim isn't.
void expectTargetsApart(WidgetTester tester) {
  final targets = <(RenderBox, Rect, Rect)>[
    for (final element
        in find.byType(AdaptiveTapTarget).hitTestable().evaluate())
      if (element.renderObject case final RenderBox box)
        (
          box,
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            box.semanticBounds,
          ),
          box.localToGlobal(Offset.zero) & box.size,
        ),
  ];
  final overlaps = <String>[];
  bool within(RenderObject inner, RenderObject outer) {
    for (RenderObject? at = inner.parent; at != null; at = at.parent) {
      if (at == outer) return true;
    }
    return false;
  }

  for (final (i, (a, grown, _)) in targets.indexed) {
    for (final (j, (b, _, drawn)) in targets.indexed) {
      // Itself, or a target inside another (a chip in a bar): no neighbour.
      if (i == j || within(a, b) || within(b, a)) continue;
      // Up to 2 dp is let be: a 44 dp row (T3's list) or a chip run can't
      // hold a 48 dp target otherwise. Me's badges reached 8 dp in.
      final both = grown.intersect(drawn);
      if (both.width > 2 && both.height > 2) {
        overlaps.add('target $i at $grown over target $j at $drawn');
      }
    }
  }
  expect(
    overlaps,
    isEmpty,
    reason: "a grown target takes its neighbour's taps",
  );
}

/// [linear] as Android 14+ gives it, when text is scaled at all.
TextScaler _phone(TextScaler linear) {
  final factor = linear.scale(1);
  return factor == 1 ? linear : AndroidTextScaler(factor);
}

/// #162: under Material chrome every icon-only control — something tappable
/// that shows an icon and no text — names itself on a long press, as a
/// Material icon button does ([AdaptiveTooltip]).
void expectIconButtonsTipped(WidgetTester tester) {
  final untipped = <String>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                (widget is GestureDetector && widget.onTap != null) ||
                (widget is InkResponse && widget.onTap != null),
          )
          .hitTestable()
          .evaluate()) {
    final tappable = find.byElementPredicate((e) => e == element);
    final icons = find.descendant(of: tappable, matching: find.byType(Icon));
    // Text, not RichText: an Icon draws its glyph with a RichText.
    final text = find.descendant(of: tappable, matching: find.byType(Text));
    if (icons.evaluate().isEmpty || text.evaluate().isNotEmpty) continue;
    final tip = find.ancestor(of: tappable, matching: find.byType(Tooltip));
    if (tip.evaluate().isEmpty) {
      untipped.add(
        '${(icons.evaluate().first.widget as Icon).icon} in '
        '${element.widget.runtimeType} at ${tester.getRect(tappable)}',
      );
    }
  }
  expect(untipped, isEmpty, reason: 'icon-only controls without a tooltip');
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
