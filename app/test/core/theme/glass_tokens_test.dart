import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Aurora Glass has its own design set — `deutsch-plan-v2-aurora-glass-html`.
/// Its surfaces are rgba fills behind a blur, so the hex-based checks in
/// dp_tokens_test.dart cannot see them at all; these read the rgba()
/// declarations out of the artboard and compare numerically.
void main() {
  // A token's alpha is an 8-bit channel, so the artboard's rgba(…,0.55)
  // round-trips to 0.549. Matching is numeric with a tolerance, never string
  // equality — that difference is invisible on screen and fatal to a `contains`.
  String show(Color c) =>
      'rgba(${(c.r * 255).round()},${(c.g * 255).round()},'
      '${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

  List<(int, int, int, double)> parseRgba(String source) =>
      RegExp(r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)')
          .allMatches(source)
          .map(
            (m) => (
              int.parse(m[1]!),
              int.parse(m[2]!),
              int.parse(m[3]!),
              double.parse(m[4]!),
            ),
          )
          .toList();

  bool paints(List<(int, int, int, double)> declared, Color c) => declared.any(
    (d) =>
        d.$1 == (c.r * 255).round() &&
        d.$2 == (c.g * 255).round() &&
        d.$3 == (c.b * 255).round() &&
        (d.$4 - c.a).abs() < 0.004,
  );

  final canvases = <String, ({String path, DpTokens tokens})>{
    'glass light': (
      path: '../deutsch-plan-v2-aurora-glass-html/android-light/screens/Foundations.html',
      tokens: DpTokens.glass(),
    ),
    'glass dark': (
      path: '../deutsch-plan-v2-aurora-glass-html/android-dark/screens/Foundations.html',
      tokens: DpTokens.glassDark(),
    ),
  };

  canvases.forEach((name, spec) {
    final surface = spec.tokens.surface;

    group('$name surfaces match the Aurora Glass artboard', () {
      late String squashed;
      late String raw;
      late List<(int, int, int, double)> declared;

      setUpAll(() {
        final file = File(spec.path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'the $name Foundations artboard moved — see docs/README.md',
        );
        raw = file.readAsStringSync().toLowerCase();
        squashed = raw.replaceAll(' ', '');
        declared = parseRgba(raw);
      });

      final fills = <String, Color>{
        'card': surface.card,
        'cardStrong': surface.cardStrong,
        'outline': surface.outline,
        'highlight': surface.highlight,
        'sheen': surface.sheen,
        'shadow': surface.shadow,
        'muted': surface.muted,
      };

      fills.forEach((label, colour) {
        test('$label is ${show(colour)}', () {
          expect(
            paints(declared, colour),
            isTrue,
            reason:
                '$label = ${show(colour)} is not painted in the $name artboard',
          );
        });
      });

      test('panels blur 24, strong panels blur 32', () {
        expect(surface.blur, 24);
        expect(surface.strongBlur, 32);
        expect(squashed, contains('blur(24px)'));
        expect(squashed, contains('blur(32px)'));
      });

      test('the drop shadow is 0/8/24, not the hard offset', () {
        expect(surface.shadowOffset, const Offset(0, 8));
        expect(surface.shadowBlur, 24);
        expect(squashed, contains('08px24pxrgba('));
        expect(paints(declared, surface.shadow), isTrue);
      });

      test('radii come off the real elements, not from anywhere in the file', () {
        final shape = spec.tokens.shape;
        expect(
          [shape.card, shape.button, shape.chip, shape.sheet],
          <double>[20, 16, 8, 28],
        );

        // Searching the whole artboard for "border-radius:16px" would match a
        // chip, a swatch or a badge just as happily as a button. Pull the
        // primary call-to-action out by its solid brand fill and measure it.
        final primaryHex =
            'background:'
            '#${(spec.tokens.color.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        final primary = RegExp(r'<button[^>]*style="([^"]*)"')
            .allMatches(raw)
            .map((m) => m[1]!)
            .firstWhere(
              (style) => style.contains(primaryHex),
              orElse: () => '',
            );

        expect(
          primary,
          isNotEmpty,
          reason: 'no solid Lagoon button found in the $name artboard',
        );
        expect(
          primary,
          contains('border-radius:${shape.button.toInt()}px'),
          reason: 'the primary CTA is not drawn at ${shape.button.toInt()} px',
        );
        expect(
          primary.contains('backdrop-filter'),
          isFalse,
          reason:
              'theming.md: buttons stay solid so calls to action never blur',
        );
      });

      test('the backdrop the aurora drifts across is the artboard colour', () {
        // paper is opaque, so it is a hex rather than an rgba fill.
        final hex =
            '#${(surface.paper.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        expect(
          raw,
          contains(hex),
          reason: 'backdrop $hex is not painted in the $name artboard',
        );
      });

      test('the outline is 1 px, and solid buttons draw none', () {
        expect(surface.outlineWidth, 1);
        // theming.md: buttons stay solid under glass, so they carry no outline
        // at all — unlike the 2 px ink border of Paper & Ink / Night Ink.
        expect(surface.strongOutlineWidth, 0);
        expect(squashed, contains('1pxsolidrgba('));
        expect(paints(declared, surface.outline), isTrue);
      });
    });
  });

  test('the aurora dims from 55 % to 35 % in the dark variant', () {
    // theming.md: "Glass has a dark variant (aurora at 35 %…)".
    expect(DpSurfaceTokens.glass.auroraOpacity, 0.55);
    expect(DpSurfaceTokens.glassDark.auroraOpacity, 0.35);
    expect(
      DpSurfaceTokens.light.auroraOpacity,
      0,
      reason: 'no aurora outside glass',
    );
    expect(DpSurfaceTokens.dark.auroraOpacity, 0);
  });

  test('glass surfaces are translucent and the solid modes are not', () {
    for (final s in [DpSurfaceTokens.glass, DpSurfaceTokens.glassDark]) {
      expect(s.card.a, lessThan(1.0));
      expect(s.cardStrong.a, lessThan(1.0));
      expect(
        s.cardStrong.a,
        greaterThan(s.card.a),
        reason: 'cardStrong is the denser fill',
      );
      expect(s.blur, greaterThan(0));
    }
    for (final s in [DpSurfaceTokens.light, DpSurfaceTokens.dark]) {
      expect(s.card.a, 1.0);
      expect(s.blur, 0);
    }
  });

  test('#163 glass keeps the Light and Dark fills; only its text roles move '
      'for contrast over the aurora', () {
    // theming.md: glass has its own text palette (#163), the rest is Light's
    // and Dark's.
    for (final (glass, base) in <(DpPalette, DpPalette)>[
      (DpTokens.glass().color, DpPalette.light),
      (DpTokens.glassDark().color, DpPalette.dark),
    ]) {
      for (final (fill, of) in <(Color, Color)>[
        (glass.primary, base.primary),
        (glass.accent, base.accent),
        (glass.der, base.der),
        (glass.die, base.die),
        (glass.das, base.das),
        (glass.again, base.again),
        (glass.hard, base.hard),
        (glass.good, base.good),
        (glass.easy, base.easy),
        (glass.learning, base.learning),
        (glass.ink, base.ink),
        (glass.onPrimary, base.onPrimary),
        (glass.onAccent, base.onAccent),
      ]) {
        expect(fill, of);
      }
    }
    expect(DpTokens.glass().color, same(DpPalette.glass));
    expect(DpTokens.glassDark().color, same(DpPalette.glassDark));
  });

  testWidgets('AppTheme.glass carries glass tokens and the right brightness', (
    tester,
  ) async {
    for (final (dark, expected) in [
      (false, Brightness.light),
      (true, Brightness.dark),
    ]) {
      late DpTokens seen;
      late Brightness brightness;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(dark),
          theme: AppTheme.glass(dark: dark),
          home: Builder(
            builder: (context) {
              seen = context.tokens;
              brightness = Theme.of(context).colorScheme.brightness;
              return const SizedBox();
            },
          ),
        ),
      );
      // MaterialApp wraps the theme in AnimatedTheme, so immediately after
      // pumpWidget Theme.of() is still interpolating from the previous theme,
      // and ThemeData.lerp keeps the OLD brightness until t = 0.5.
      await tester.pumpAndSettle();

      expect(seen.mode, DpMode.glass);
      expect(seen.isGlass, isTrue);
      expect(
        brightness,
        expected,
        reason:
            'glass ${dark ? 'dark' : 'light'} resolved the wrong brightness — '
            'Material would use the wrong scrim and system icon colours',
      );
    }
  });
}
