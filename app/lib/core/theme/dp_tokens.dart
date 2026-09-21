import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// Design tokens for one theme mode.
///
/// `docs/01-architecture/theming.md`: three modes share one layout, one
/// component set and one behaviour — only tokens and the surface renderer
/// differ. Widgets read tokens, never hex values:
///
/// ```dart
/// final t = context.tokens;
/// Container(color: t.surface.card, …)  // never Color(0xFFFFFFFF)
/// ```
///
/// Light (Paper & Ink) is the reference mode the artboards were drawn in; every
/// value here matches `Foundations.html` in the android-light canvas.
enum DpMode { light, dark, glass }

@immutable
class DpTokens extends ThemeExtension<DpTokens> {
  const DpTokens({
    required this.mode,
    required this.color,
    required this.surface,
    required this.typography,
    required this.shape,
    required this.spacing,
    required this.motion,
  });

  /// Paper & Ink. Warm cream paper, near-black ink, saturated solid fills with
  /// ink text, hard 3 px offset shadows, no gradients.
  factory DpTokens.light() => const DpTokens(
    mode: DpMode.light,
    color: DpPalette.light,
    surface: DpSurfaceTokens.light,
    typography: DpTypeTokens.defaults,
    shape: DpShapeTokens.defaults,
    spacing: DpSpacingTokens.defaults,
    motion: DpMotionTokens.defaults,
  );

  final DpMode mode;
  final DpPalette color;
  final DpSurfaceTokens surface;
  final DpTypeTokens typography;
  final DpShapeTokens shape;
  final DpSpacingTokens spacing;
  final DpMotionTokens motion;

  @override
  DpTokens copyWith({
    DpMode? mode,
    DpPalette? color,
    DpSurfaceTokens? surface,
    DpTypeTokens? typography,
    DpShapeTokens? shape,
    DpSpacingTokens? spacing,
    DpMotionTokens? motion,
  }) => DpTokens(
    mode: mode ?? this.mode,
    color: color ?? this.color,
    surface: surface ?? this.surface,
    typography: typography ?? this.typography,
    shape: shape ?? this.shape,
    spacing: spacing ?? this.spacing,
    motion: motion ?? this.motion,
  );

  /// Only colours interpolate. Shape, spacing, motion and the type scale are
  /// identical across modes, so a theme change animates colour and nothing else.
  @override
  DpTokens lerp(covariant DpTokens? other, double t) {
    if (other == null) return this;
    return DpTokens(
      mode: t < 0.5 ? mode : other.mode,
      color: color.lerp(other.color, t),
      surface: surface.lerp(other.surface, t),
      typography: t < 0.5 ? typography : other.typography,
      shape: t < 0.5 ? shape : other.shape,
      spacing: t < 0.5 ? spacing : other.spacing,
      motion: t < 0.5 ? motion : other.motion,
    );
  }
}

/// Brand, gender, rating and verdict colours.
@immutable
class DpPalette {
  const DpPalette({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.ink,
    required this.textSecondary,
    required this.link,
    required this.der,
    required this.derText,
    required this.die,
    required this.dieText,
    required this.das,
    required this.dasText,
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
    required this.learning,
    required this.correctText,
    required this.almostText,
    required this.wrongText,
  });

  /// Every value is read off the android-light `Foundations.html`.
  static const DpPalette light = DpPalette(
    primary: Color(0xFF00C2B2), // Lagoon
    onPrimary: Color(0xFF15121F),
    accent: Color(0xFFFFC61A), // Sun
    onAccent: Color(0xFF15121F),
    ink: Color(0xFF15121F),
    textSecondary: Color(0xFF5B5670), // Slate Ink
    link: Color(0xFF007A70),
    der: Color(0xFF3D5AFE), // Cobalt
    derText: Color(0xFF2F46E0),
    die: Color(0xFFFF3D7F), // Raspberry
    dieText: Color(0xFFD6155C),
    das: Color(0xFF00B86B), // Emerald
    dasText: Color(0xFF00804A),
    again: Color(0xFFFF5E4D), // Coral
    hard: Color(0xFFFF9F1C), // Tangerine
    good: Color(0xFF00C2B2), // Lagoon
    easy: Color(0xFFA6E22E), // Lime
    learning: Color(0xFFFFC61A), // Sun
    correctText: Color(0xFF00804A),
    almostText: Color(0xFFB45F00),
    wrongText: Color(0xFFC8341F),
  );

  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;
  final Color ink;
  final Color textSecondary;
  final Color link;

  /// Gender colours. `*Text` is the accessible variant for text on paper; the
  /// plain value is for fills and bars. Never colour alone — the article is
  /// always printed (`accessibility-performance.md`).
  final Color der;
  final Color derText;
  final Color die;
  final Color dieText;
  final Color das;
  final Color dasText;

  /// Rating colours, deliberately distinct from the gender colours.
  final Color again;
  final Color hard;
  final Color good;
  final Color easy;
  final Color learning;

  /// Answer verdicts. Each is paired with an icon and a word, never used alone.
  final Color correctText;
  final Color almostText;
  final Color wrongText;

  /// The gender colour for an article, or null when the word has none.
  Color? forArticle(String? article) => switch (article?.toLowerCase().trim()) {
    'der' => der,
    'die' => die,
    'das' => das,
    _ => null,
  };

  /// The text-safe gender colour for an article, or null when the word has none.
  Color? textForArticle(String? article) =>
      switch (article?.toLowerCase().trim()) {
        'der' => derText,
        'die' => dieText,
        'das' => dasText,
        _ => null,
      };

  DpPalette lerp(DpPalette other, double t) => DpPalette(
    primary: Color.lerp(primary, other.primary, t)!,
    onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    accent: Color.lerp(accent, other.accent, t)!,
    onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    ink: Color.lerp(ink, other.ink, t)!,
    textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    link: Color.lerp(link, other.link, t)!,
    der: Color.lerp(der, other.der, t)!,
    derText: Color.lerp(derText, other.derText, t)!,
    die: Color.lerp(die, other.die, t)!,
    dieText: Color.lerp(dieText, other.dieText, t)!,
    das: Color.lerp(das, other.das, t)!,
    dasText: Color.lerp(dasText, other.dasText, t)!,
    again: Color.lerp(again, other.again, t)!,
    hard: Color.lerp(hard, other.hard, t)!,
    good: Color.lerp(good, other.good, t)!,
    easy: Color.lerp(easy, other.easy, t)!,
    learning: Color.lerp(learning, other.learning, t)!,
    correctText: Color.lerp(correctText, other.correctText, t)!,
    almostText: Color.lerp(almostText, other.almostText, t)!,
    wrongText: Color.lerp(wrongText, other.wrongText, t)!,
  );
}

/// Surface fills and the treatment `DpSurface` draws them with.
///
/// In light and dark that treatment is a 1.5 px outline plus a hard 3 px
/// down-right offset shadow. Glass replaces it with blur (#34).
@immutable
class DpSurfaceTokens {
  const DpSurfaceTokens({
    required this.paper,
    required this.card,
    required this.cardStrong,
    required this.muted,
    required this.outline,
    required this.outlineWidth,
    required this.strongOutlineWidth,
    required this.shadow,
    required this.shadowOffset,
  });

  static const DpSurfaceTokens light = DpSurfaceTokens(
    paper: Color(0xFFFFF8EE),
    card: Color(0xFFFFFFFF),
    cardStrong: Color(0xFFFFFFFF),
    muted: Color(0xFFF3EADB), // Oat
    outline: Color(0x3315121F), // ink at 20 %
    outlineWidth: 1.5,
    // Buttons carry a heavier 2 px ink border in the artboards.
    strongOutlineWidth: 2,
    shadow: Color(0xFF15121F),
    shadowOffset: Offset(3, 3),
  );

  final Color paper;
  final Color card;
  final Color cardStrong;
  final Color muted;
  final Color outline;
  final double outlineWidth;
  final double strongOutlineWidth;

  /// The hard offset shadow: no blur, no spread, pure ink.
  final Color shadow;
  final Offset shadowOffset;

  DpSurfaceTokens lerp(DpSurfaceTokens other, double t) => DpSurfaceTokens(
    paper: Color.lerp(paper, other.paper, t)!,
    card: Color.lerp(card, other.card, t)!,
    cardStrong: Color.lerp(cardStrong, other.cardStrong, t)!,
    muted: Color.lerp(muted, other.muted, t)!,
    outline: Color.lerp(outline, other.outline, t)!,
    outlineWidth: lerpDouble(outlineWidth, other.outlineWidth, t)!,
    strongOutlineWidth: lerpDouble(
      strongOutlineWidth,
      other.strongOutlineWidth,
      t,
    )!,
    shadow: Color.lerp(shadow, other.shadow, t)!,
    shadowOffset: Offset.lerp(shadowOffset, other.shadowOffset, t)!,
  );
}

/// The type scale. Sizes and line heights are identical in all three modes.
///
/// Bangla is set one step larger at the same role — that rule lands with the
/// text theme in #36; these are the Latin values.
@immutable
class DpTypeTokens {
  const DpTypeTokens({
    required this.display,
    required this.headline,
    required this.title,
    required this.bodyLarge,
    required this.body,
    required this.label,
    required this.caption,
  });

  static const DpTypeTokens defaults = DpTypeTokens(
    display: DpTextToken(size: 40, height: 48, weight: 600),
    headline: DpTextToken(size: 28, height: 34, weight: 600),
    title: DpTextToken(size: 20, height: 26, weight: 600),
    bodyLarge: DpTextToken(size: 17, height: 24, weight: 400),
    body: DpTextToken(size: 15, height: 22, weight: 400),
    label: DpTextToken(size: 13, height: 16, weight: 600),
    caption: DpTextToken(size: 12, height: 16, weight: 400),
  );

  final DpTextToken display;
  final DpTextToken headline;
  final DpTextToken title;
  final DpTextToken bodyLarge;
  final DpTextToken body;
  final DpTextToken label;
  final DpTextToken caption;
}

/// One role of the type scale, in the artboards' own units.
@immutable
class DpTextToken {
  const DpTextToken({
    required this.size,
    required this.height,
    required this.weight,
  });

  /// Font size in logical pixels.
  final double size;

  /// Line height in logical pixels, as the artboards state it (40/48).
  final double height;

  /// `wght` axis value for the variable fonts.
  final double weight;

  /// Flutter expresses line height as a multiple of the font size.
  double get heightFactor => height / size;
}

/// Corner radii. Glass uses larger radii throughout (#32).
@immutable
class DpShapeTokens {
  const DpShapeTokens({
    required this.card,
    required this.button,
    required this.chip,
    required this.sheet,
  });

  static const DpShapeTokens defaults = DpShapeTokens(
    card: 16,
    button: 12,
    chip: 8,
    sheet: 24,
  );

  final double card;
  final double button;
  final double chip;
  final double sheet;

  BorderRadius get cardRadius => BorderRadius.circular(card);
  BorderRadius get buttonRadius => BorderRadius.circular(button);
  BorderRadius get chipRadius => BorderRadius.circular(chip);

  /// Sheets are rounded at the top only.
  BorderRadius get sheetRadius =>
      BorderRadius.vertical(top: Radius.circular(sheet));
}

/// The 4/8/12/16/24/32/48 spacing scale.
@immutable
class DpSpacingTokens {
  const DpSpacingTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
  });

  static const DpSpacingTokens defaults = DpSpacingTokens(
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 24,
    xxl: 32,
    xxxl: 48,
  );

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;

  /// Every value on the scale, in order — used by the token tests.
  List<double> get all => <double>[xs, sm, md, lg, xl, xxl, xxxl];
}

/// Motion durations. All motion respects the OS reduce-motion setting (#Y03).
@immutable
class DpMotionTokens {
  const DpMotionTokens({
    required this.instant,
    required this.quick,
    required this.standard,
    required this.deliberate,
    required this.celebrate,
  });

  static const DpMotionTokens defaults = DpMotionTokens(
    instant: Duration(milliseconds: 100),
    quick: Duration(milliseconds: 200),
    standard: Duration(milliseconds: 300),
    deliberate: Duration(milliseconds: 400),
    celebrate: Duration(milliseconds: 1200),
  );

  final Duration instant;
  final Duration quick;
  final Duration standard;
  final Duration deliberate;

  /// Day complete: the ring, the ink check and the confetti.
  final Duration celebrate;
}

/// `context.tokens` — the only way a widget reaches a design value.
extension DpTokensContext on BuildContext {
  DpTokens get tokens {
    final tokens = Theme.of(this).extension<DpTokens>();
    assert(
      tokens != null,
      'No DpTokens in the theme. Build the app with AppTheme.light() (or its '
      'dark/glass counterpart) so the extension is attached.',
    );
    return tokens ?? DpTokens.light();
  }
}
