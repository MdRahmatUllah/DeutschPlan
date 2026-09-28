import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/sg_tokens.dart';

/// theming.md: "3–4 radial blobs (400–700 dp) in Lagoon, Sun, Raspberry,
/// Cobalt, rendered once to an image and translated on 18–24 s loops (≈ 20 dp
/// travel)… Drift pauses under reduced motion, when backgrounded, and in
/// fallback mode."
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    bool disableAnimations = false,
    GlassCapability? capability,
    Color? leading,
  }) async {
    await tester.pumpWidget(
      GlassCapabilityScope(
        notifier: capability ?? GlassCapability.always(),
        child: MaterialApp(
          theme: theme ?? AppTheme.glass(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: AuroraBackdrop(
              leading: leading,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Scoped to the backdrop: MaterialApp and Theme use AnimatedBuilder and
  // CustomPaint internally, so an unscoped finder is always true.
  Finder within(Type type) => find.descendant(
    of: find.byType(AuroraBackdrop),
    matching: find.byType(type),
  );

  bool isDrifting(WidgetTester tester) =>
      within(AnimatedBuilder).evaluate().isNotEmpty;

  /// Whether anything asks for a frame within [time]. The test's clock is
  /// fake: `delayed` moves it on and fires the timers due, drawing nothing,
  /// and sleeps not at all.
  Future<bool> asksForFrameIn(WidgetTester tester, Duration time) async {
    await tester.binding.delayed(time);
    return tester.binding.hasScheduledFrame;
  }

  /// Where the leading blob has drifted to.
  Offset lead(WidgetTester tester) {
    final moved = within(Transform);
    if (moved.evaluate().isEmpty) return Offset.zero;
    final shift = tester
        .widget<Transform>(moved.first)
        .transform
        .getTranslation();
    return Offset(shift.x, shift.y);
  }

  group('the blobs match the artboard', () {
    test('there are four, at the documented radii', () {
      expect(AuroraBlob.defaults, hasLength(4));
      expect(AuroraBlob.defaults.map((b) => b.radius), <double>[
        340,
        270,
        310,
        250,
      ]);
    });

    test('every diameter falls in the 400–700 dp range theming.md gives', () {
      // CSS `circle <n>px` is a radius, so the drawn sizes are twice these.
      for (final blob in AuroraBlob.defaults) {
        expect(blob.radius * 2, inInclusiveRange(400, 700));
      }
    });

    test('the four roles are Lagoon, Sun, Raspberry and Cobalt', () {
      expect(AuroraBlob.defaults.map((b) => b.role), <AuroraRole>[
        AuroraRole.lagoon,
        AuroraRole.sun,
        AuroraRole.raspberry,
        AuroraRole.cobalt,
      ]);

      const palette = SgPalette.light;
      expect(AuroraRole.lagoon.from(palette), palette.primary);
      expect(AuroraRole.sun.from(palette), palette.accent);
      expect(AuroraRole.raspberry.from(palette), palette.die);
      expect(AuroraRole.cobalt.from(palette), palette.der);
    });

    test('roles resolve to the dark palette in the dark variant', () {
      // Named by role rather than colour so this substitution is automatic.
      expect(AuroraRole.lagoon.from(SgPalette.dark), SgPalette.dark.primary);
      expect(
        AuroraRole.lagoon.from(SgPalette.dark),
        isNot(AuroraRole.lagoon.from(SgPalette.light)),
      );
    });

    test('the loop periods spread across 18–24 s', () {
      final periods = <Duration>[
        for (var i = 0; i < 4; i++) AuroraBackdrop.periodFor(i, 4),
      ];
      expect(periods.first, AuroraBackdrop.minimumPeriod);
      expect(periods.last, AuroraBackdrop.maximumPeriod);
      expect(
        periods.toSet(),
        hasLength(4),
        reason: 'equal periods would line the blobs up into one visible pulse',
      );
    });

    test('travel is about 20 dp', () {
      expect(AuroraBackdrop.travel, 20);
    });
  });

  group('when it drifts', () {
    testWidgets('it drifts under glass with blur allowed', (tester) async {
      await pump(tester);
      expect(isDrifting(tester), isTrue);
    });

    testWidgets('reduce motion holds it still', (tester) async {
      await pump(tester, disableAnimations: true);
      expect(isDrifting(tester), isFalse);
    });

    testWidgets('the glass fallback holds it still', (tester) async {
      // In fallback the panels are opaque, so a drifting backdrop behind them
      // is motion nobody can see.
      await pump(tester, capability: GlassCapability.never());
      expect(isDrifting(tester), isFalse);
    });

    testWidgets('backgrounding holds it still', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 1));
      final before = lead(tester);

      // In the background the engine draws nothing, so what shows the drift
      // stopped is where the blobs are when the app comes back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(isDrifting(tester), isTrue);
      expect(lead(tester), before, reason: 'it drifted in the background');
    });

    testWidgets('#709: a screen under another holds its drift', (tester) async {
      // A tab in the background or a page pushed over it: a ticker there is
      // muted, and so is the drift.
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: GlassCapability.always(),
          child: MaterialApp(
            theme: AppTheme.glass(),
            home: const TickerMode(
              enabled: false,
              child: AuroraBackdrop(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(await asksForFrameIn(tester, const Duration(seconds: 1)), isFalse);
    });

    testWidgets('a still backdrop still paints its blobs', (tester) async {
      // Stillness is about motion, not about the aurora disappearing.
      await pump(tester, disableAnimations: true);
      expect(within(CustomPaint), findsNWidgets(4));
    });
  });

  testWidgets('the aurora schedules no frames when nothing is moving', (
    tester,
  ) async {
    // Frames asked for a widget that paints nothing are battery for nothing
    // — and light and dark are the modes most people use. In a fresh tree
    // each time, because swapping the theme in place adds the theme
    // transition's own frames.
    Future<bool> asksForFrames(ThemeData theme) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          key: ValueKey(theme.hashCode),
          notifier: GlassCapability.always(),
          child: MaterialApp(
            theme: theme,
            home: const AuroraBackdrop(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return asksForFrameIn(tester, const Duration(seconds: 1));
    }

    expect(
      await asksForFrames(AppTheme.light()),
      isFalse,
      reason: 'light paints no aurora, so it must schedule no aurora frames',
    );
    expect(await asksForFrames(AppTheme.dark()), isFalse);
    expect(
      await asksForFrames(AppTheme.glass()),
      isTrue,
      reason: 'under glass it does drift, so it must schedule frames',
    );
  });

  testWidgets('#709: the drift steps 15 times a second, and asks for no '
      'frame between two steps', (tester) async {
    // Each frame the aurora moves in, every glass panel on screen blurs
    // again. A ticker asked for 60 a second while the learner only reads.
    await pump(tester);
    expect(
      await asksForFrameIn(tester, const Duration(milliseconds: 10)),
      isFalse,
      reason: 'nothing moved, so nothing needs drawing',
    );
    expect(
      await asksForFrameIn(tester, AuroraBackdrop.step),
      isTrue,
      reason: 'a step',
    );

    // A second of frames at 60 fps: the blobs move in 15 of them.
    var moves = 0;
    var last = lead(tester);
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(microseconds: 16667));
      if (lead(tester) != last) moves++;
      last = lead(tester);
    }
    expect(moves, inInclusiveRange(14, 16));
  });

  testWidgets('#709: a drift step repaints the blobs, not the screen', (
    tester,
  ) async {
    final screen = _CountingPainter();
    await tester.pumpWidget(
      GlassCapabilityScope(
        notifier: GlassCapability.always(),
        child: MaterialApp(
          theme: AppTheme.glass(),
          home: AuroraBackdrop(
            child: CustomPaint(painter: screen, size: Size.infinite),
          ),
        ),
      ),
    );
    await tester.pump();
    final painted = screen.paints;
    final start = lead(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(lead(tester), isNot(start), reason: 'it drifted');
    expect(screen.paints, painted);
  });

  testWidgets('#698: the number of blobs can change', (tester) async {
    // It held one controller per blob, made once, so a longer list ran off
    // the end of them.
    Future<void> blobs(List<AuroraBlob> blobs) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: GlassCapability.always(),
          child: MaterialApp(
            theme: AppTheme.glass(),
            home: AuroraBackdrop(blobs: blobs, child: const SizedBox.expand()),
          ),
        ),
      );
      await tester.pump(AuroraBackdrop.step);
    }

    await blobs(AuroraBlob.defaults.take(2).toList());
    await blobs(AuroraBlob.defaults);
    expect(tester.takeException(), isNull);
    expect(within(CustomPaint), findsNWidgets(4));
  });

  group('outside glass', () {
    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('$name draws no aurora and runs no tickers', (tester) async {
        await pump(tester, theme: theme);
        expect(
          within(CustomPaint),
          findsNothing,
          reason: 'the solid modes have paper, not a backdrop',
        );
        expect(isDrifting(tester), isFalse);
      });
    }
  });

  group('the leading blob', () {
    testWidgets('takes the tab colour when one is given', (tester) async {
      // theming.md: Today Lagoon, Learn Sun, Search Raspberry, Me Cobalt, and
      // a study session shifts it toward the noun's gender colour.
      await pump(tester, leading: SgPalette.light.die, disableAnimations: true);

      final painters = tester
          .widgetList<CustomPaint>(within(CustomPaint))
          .toList();

      expect(painters.first.painter.toString(), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to its own role colour', (tester) async {
      await pump(tester, disableAnimations: true);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('each blob is its own repaint boundary, and so is the screen', (
    tester,
  ) async {
    // The gradients are rasterised once and only translated; without the
    // boundary each frame would repaint four large radial shaders.
    await pump(tester);
    expect(within(RepaintBoundary), findsNWidgets(5));
  });
}

class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_CountingPainter old) => false;
}
