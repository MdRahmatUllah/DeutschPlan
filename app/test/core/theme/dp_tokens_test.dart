import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Light token set is the reference mode: the artboards were drawn in it,
/// so every value must match `Foundations.html` in the android-light canvas.
/// These tests read that file rather than trusting a transcription.
void main() {
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  // Each mode is checked against its own canvas. Glass joins this table in #32.
  final canvases = <DpMode, String>{
    DpMode.light:
        '../deutsch-plan-design-html/android-light/screens/Foundations.html',
    DpMode.dark:
        '../deutsch-plan-design-html/android-dark/screens/Foundations.html',
  };

  // Colours that appear in an artboard but are not app tokens.
  final outOfScope = <DpMode, Set<String>>{
    // The canvas the device frame is pasted onto.
    DpMode.light: {'#E9E4DA'},
    DpMode.dark: {'#0B0A10'},
  };

  // Tokens theming.md defines that the artboard never actually paints.
  final specOnly = <DpMode, Set<String>>{
    DpMode.light: {'#2F46E0'}, // derText
    DpMode.dark: <String>{},
  };

  /// Artboard colours a token deliberately moved off for WCAG AA (#163):
  /// the artboard's value, by token. The token must still differ only for
  /// the reason given, so its artboard value is accounted for here and the
  /// token's own value is checked by `contrast_test.dart`.
  final adjustedForContrast = <DpMode, Map<String, String>>{
    DpMode.light: {'almostText': '#B45F00'}, // 4.35:1 on paper -> #AE5C01
    DpMode.dark: <String, String>{},
  };

  canvases.forEach((mode, path) {
    final name = mode.name;
    final tokens = mode == DpMode.light ? DpTokens.light() : DpTokens.dark();
    final palette = tokens.color;
    final surface = tokens.surface;

    group('$name palette matches its artboard', () {
      late String artboard;

      setUpAll(() {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'the $name Foundations artboard moved — see the design-set '
              'table in docs/README.md',
        );
        artboard = file.readAsStringSync().toUpperCase();
      });

      final named = <String, Color>{
        'primary': palette.primary,
        'accent': palette.accent,
        'ink': palette.ink,
        'textSecondary': palette.textSecondary,
        'link': palette.link,
        'der': palette.der,
        'die': palette.die,
        'das': palette.das,
        'dieText': palette.dieText,
        'dasText': palette.dasText,
        'again': palette.again,
        'hard': palette.hard,
        'good': palette.good,
        'easy': palette.easy,
        'learning': palette.learning,
        'correctText': palette.correctText,
        'almostText': palette.almostText,
        'wrongText': palette.wrongText,
        'paper': surface.paper,
        'card': surface.card,
        'muted': surface.muted,
        'onPrimary': palette.onPrimary,
      };

      // A typo net, not proof of mapping: several tokens share a value, so
      // swapping a pair would still pass. The reverse check below is what
      // catches a colour that was missed altogether.
      named.forEach((label, colour) {
        final drawn = adjustedForContrast[mode]![label] ?? hex(colour);
        test('$label is $drawn in the artboard', () {
          expect(
            artboard.contains(drawn),
            isTrue,
            reason:
                '$label = ${hex(colour)} does not appear in the $name artboard',
          );
        });
      });

      test(
        'every colour in the artboard is a token or explicitly out of scope',
        () {
          final accountedFor = <String>{
            ...named.values.map(hex),
            ...outOfScope[mode]!,
            ...specOnly[mode]!,
            ...adjustedForContrast[mode]!.values,
            hex(palette.onAccent),
            hex(palette.derText),
            hex(surface.cardStrong),
          };

          final inArtboard = RegExp(r'#[0-9A-F]{6}')
              .allMatches(artboard)
              .map((m) => m[0]!)
              .toSet();

          expect(
            inArtboard.difference(accountedFor),
            isEmpty,
            reason:
                'the $name artboard uses a colour no token covers — add it to '
                'DpPalette/DpSurfaceTokens, or list it as out of scope here',
          );
        },
      );

      test('the outline is ink at the opacity the artboard uses', () {
        expect(hex(surface.outline), hex(palette.ink));
        // Read the opacity out of the artboard instead of restating it here, so
        // the test cannot agree with itself while the design moves underneath.
        final alphas =
            RegExp(r'rgba\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*([\d.]+)\s*\)')
                .allMatches(artboard.toLowerCase())
                .map((m) => double.parse(m[1]!))
                .toSet();

        expect(
          alphas.any((a) => (a - surface.outline.a).abs() < 0.005),
          isTrue,
          reason:
              'outline alpha ${surface.outline.a.toStringAsFixed(2)} matches no '
              'rgba() in the $name artboard (found: ${alphas.toList()..sort()})',
        );
      });

      test('the hard shadow matches the artboard exactly, colour included', () {
        expect(surface.shadowOffset, const Offset(3, 3));

        // The colour is the half this used to miss: `shadow` is not in `named`,
        // and the reverse scan only sees #RRGGBB, so an rgba() shadow was
        // unchecked in both modes.
        final rendered = mode == DpMode.light
            ? '3px 3px 0 ${hex(surface.shadow).toLowerCase()}'
            : '3px 3px 0 rgba(255,255,255,'
                  '${_trimZero(surface.shadow.a)})';

        expect(
          artboard.toLowerCase().replaceAll(' 0 rgba( ', ' 0 rgba('),
          contains(rendered),
          reason: 'the $name artboard does not draw "$rendered"',
        );
      });
    });
  });

  test('dark lifts every brand and rating colour away from light', () {
    const l = DpPalette.light;
    const d = DpPalette.dark;
    // Night Ink is not light with a swapped background: the fills are lifted a
    // step so they stay readable on a dark surface.
    for (final pair in <List<Color>>[
      [l.primary, d.primary],
      [l.accent, d.accent],
      [l.der, d.der],
      [l.die, d.die],
      [l.das, d.das],
      [l.again, d.again],
      [l.hard, d.hard],
      [l.easy, d.easy],
    ]) {
      expect(
        pair[1].computeLuminance(),
        greaterThan(pair[0].computeLuminance()),
        reason: '${hex(pair[1])} is not lighter than ${hex(pair[0])}',
      );
    }
  });

  test('ink and paper invert between the two modes', () {
    expect(
      DpPalette.dark.ink.computeLuminance(),
      greaterThan(DpPalette.light.ink.computeLuminance()),
    );
    expect(
      DpSurfaceTokens.dark.paper.computeLuminance(),
      lessThan(DpSurfaceTokens.light.paper.computeLuminance()),
    );
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

/// `0.30` -> `0.3`, matching how the artboard writes an rgba alpha.
String _trimZero(double v) {
  final text = v.toStringAsFixed(2);
  return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
}
