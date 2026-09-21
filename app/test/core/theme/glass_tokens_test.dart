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
      late List<(int, int, int, double)> declared;

      setUpAll(() {
        final file = File(spec.path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'the $name Foundations artboard moved — see docs/README.md',
        );
        final raw = file.readAsStringSync().toLowerCase();
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

      test('radii are cards 20, buttons 14, chips 8, sheets 26', () {
        final shape = spec.tokens.shape;
        expect(
          [shape.card, shape.button, shape.chip, shape.sheet],
          <double>[20, 14, 8, 26],
        );
        expect(squashed, contains('border-radius:20px'));
        expect(squashed, contains('border-radius:14px'));
      });

      test('the outline is 1 px, not the 1.5/2 px of the solid modes', () {
        expect(surface.outlineWidth, 1);
        expect(surface.strongOutlineWidth, 1);
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

  test('glass keeps the Light and Dark palettes untouched', () {
    // theming.md: only tokens and the surface renderer differ between modes.
    expect(DpTokens.glass().color, same(DpPalette.light));
    expect(DpTokens.glassDark().color, same(DpPalette.dark));
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
