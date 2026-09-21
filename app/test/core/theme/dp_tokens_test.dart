import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Light token set is the reference mode: the artboards were drawn in it,
/// so every value must match `Foundations.html` in the android-light canvas.
/// These tests read that file rather than trusting a transcription.
void main() {
  final foundations = File(
    '../deutsch-plan-design-html/android-light/screens/Foundations.html',
  );

  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  group('Light palette matches the artboard', () {
    late String artboard;

    setUpAll(() {
      expect(
        foundations.existsSync(),
        isTrue,
        reason:
            'the Foundations artboard moved — see the design-set table in '
            'docs/README.md',
      );
      artboard = foundations.readAsStringSync().toUpperCase();
    });

    const palette = DpPalette.light;
    const surface = DpSurfaceTokens.light;

    // Name -> value, exactly as docs/01-architecture/theming.md lists them.
    final tokens = <String, Color>{
      'primary (Lagoon)': palette.primary,
      'accent (Sun)': palette.accent,
      'ink': palette.ink,
      'textSecondary (Slate Ink)': palette.textSecondary,
      'link': palette.link,
      'der (Cobalt)': palette.der,
      'die (Raspberry)': palette.die,
      'das (Emerald)': palette.das,
      'dieText': palette.dieText,
      'dasText': palette.dasText,
      'again (Coral)': palette.again,
      'hard (Tangerine)': palette.hard,
      'good (Lagoon)': palette.good,
      'easy (Lime)': palette.easy,
      'learning (Sun)': palette.learning,
      'correctText': palette.correctText,
      'almostText': palette.almostText,
      'wrongText': palette.wrongText,
      'paper': surface.paper,
      'card': surface.card,
      'muted (Oat)': surface.muted,
    };

    tokens.forEach((name, colour) {
      test('$name is ${hex(colour)} in Foundations.html', () {
        expect(
          artboard.contains(hex(colour)),
          isTrue,
          reason: '$name = ${hex(colour)} does not appear in the artboard',
        );
      });
    });

    test('the outline is ink at 20 %', () {
      expect(surface.outline.a, closeTo(0.2, 0.005));
      expect(hex(surface.outline), hex(palette.ink));
      // The artboard writes it as rgba(21,18,31,0.2).
      expect(artboard.toLowerCase(), contains('rgba(21,18,31,0.2)'));
    });

    test('the hard shadow is pure ink offset 3 px down-right, no blur', () {
      expect(surface.shadow, palette.ink);
      expect(surface.shadowOffset, const Offset(3, 3));
      expect(artboard.toLowerCase(), contains('3px 3px 0 #15121f'));
    });
  });

  group('scales match theming.md', () {
    const t = DpTypeTokens.defaults;

    test(
      'the type scale is 40/48 · 28/34 · 20/26 · 17/24 · 15/22 · 13/16 · 12/16',
      () {
        expect([t.display.size, t.display.height], [40, 48]);
        expect([t.headline.size, t.headline.height], [28, 34]);
        expect([t.title.size, t.title.height], [20, 26]);
        expect([t.bodyLarge.size, t.bodyLarge.height], [17, 24]);
        expect([t.body.size, t.body.height], [15, 22]);
        expect([t.label.size, t.label.height], [13, 16]);
        expect([t.caption.size, t.caption.height], [12, 16]);
      },
    );

    test('heightFactor converts the artboard line height for Flutter', () {
      expect(t.display.heightFactor, closeTo(48 / 40, 1e-9));
      expect(t.body.heightFactor, closeTo(22 / 15, 1e-9));
    });

    test('the spacing scale is 4/8/12/16/24/32/48', () {
      expect(DpSpacingTokens.defaults.all, <double>[4, 8, 12, 16, 24, 32, 48]);
    });

    test('radii are cards 16, buttons 12, chips 8, sheets 24', () {
      const s = DpShapeTokens.defaults;
      expect([s.card, s.button, s.chip, s.sheet], <double>[16, 12, 8, 24]);
      expect(
        s.sheetRadius.bottomLeft,
        Radius.zero,
        reason: 'sheets round at the top only',
      );
    });

    test('motion is 100 / 200 / 300 / 400 / 1200 ms', () {
      const m = DpMotionTokens.defaults;
      expect(
        [
          m.instant,
          m.quick,
          m.standard,
          m.deliberate,
          m.celebrate,
        ].map((d) => d.inMilliseconds),
        [100, 200, 300, 400, 1200],
      );
    });
  });

  group('gender colours', () {
    test('resolve from the article, case and padding insensitively', () {
      const p = DpPalette.light;
      expect(p.forArticle('der'), p.der);
      expect(p.forArticle('DIE'), p.die);
      expect(p.forArticle(' das '), p.das);
      expect(p.textForArticle('die'), p.dieText);
    });

    test('a word without an article has no gender colour', () {
      const p = DpPalette.light;
      expect(p.forArticle(null), isNull);
      expect(p.forArticle(''), isNull);
      expect(p.forArticle('the'), isNull);
    });

    test('are distinct from the rating colours', () {
      const p = DpPalette.light;
      final gender = {p.der, p.die, p.das};
      final ratings = {p.again, p.hard, p.easy};
      expect(gender.intersection(ratings), isEmpty);
    });
  });

  group('the theme carries the tokens', () {
    testWidgets('context.tokens returns the light set', (tester) async {
      late DpTokens seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              seen = context.tokens;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen.mode, DpMode.light);
      expect(seen.surface.card, DpSurfaceTokens.light.card);
      expect(seen.color.primary, DpPalette.light.primary);
    });

    testWidgets('the scaffold background is paper, not white', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.scaffoldBackgroundColor, DpSurfaceTokens.light.paper);
    });

    test('lerp moves colours but never the scale', () {
      final a = DpTokens.light();
      final b = DpTokens.light().copyWith(
        color: DpPalette.light.lerp(DpPalette.light, 1),
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.spacing.all, a.spacing.all);
      expect(mid.shape.card, a.shape.card);
      expect(mid.motion.quick, a.motion.quick);
    });
  });
}
