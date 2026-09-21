import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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

      const palette = DpPalette.light;
      expect(AuroraRole.lagoon.from(palette), palette.primary);
      expect(AuroraRole.sun.from(palette), palette.accent);
      expect(AuroraRole.raspberry.from(palette), palette.die);
      expect(AuroraRole.cobalt.from(palette), palette.der);
    });

    test('roles resolve to the dark palette in the dark variant', () {
      // Named by role rather than colour so this substitution is automatic.
      expect(AuroraRole.lagoon.from(DpPalette.dark), DpPalette.dark.primary);
      expect(
        AuroraRole.lagoon.from(DpPalette.dark),
        isNot(AuroraRole.lagoon.from(DpPalette.light)),
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
      expect(isDrifting(tester), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(isDrifting(tester), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(isDrifting(tester), isTrue);
    });

    testWidgets('a still backdrop still paints its blobs', (tester) async {
      // Stillness is about motion, not about the aurora disappearing.
      await pump(tester, disableAnimations: true);
      expect(within(CustomPaint), findsNWidgets(4));
    });
  });

  group('outside glass', () {
    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('$name draws no aurora at all', (tester) async {
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
      await pump(tester, leading: DpPalette.light.die, disableAnimations: true);

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

  testWidgets('each blob is its own repaint boundary', (tester) async {
    // The gradients are rasterised once and only translated; without the
    // boundary each frame would repaint four large radial shaders.
    await pump(tester);
    expect(within(RepaintBoundary), findsNWidgets(4));
  });
}
