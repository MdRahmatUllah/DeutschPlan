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

  /// Night Ink. Deep violet-black paper, light ink, the same fills lifted one
  /// step; the hard offset shadow becomes white at 30 %.
  factory DpTokens.dark() => const DpTokens(
    mode: DpMode.dark,
    color: DpPalette.dark,
    surface: DpSurfaceTokens.dark,
    typography: DpTypeTokens.defaults,
    shape: DpShapeTokens.defaults,
    spacing: DpSpacingTokens.defaults,
    motion: DpMotionTokens.defaults,
  );

  /// Aurora Glass. Buttons stay solid so calls to action never blur; the
  /// palette is the Light one, and only the surfaces change.
  factory DpTokens.glass() => const DpTokens(
    mode: DpMode.glass,
    color: DpPalette.glass,
    surface: DpSurfaceTokens.glass,
    typography: DpTypeTokens.defaults,
    shape: DpShapeTokens.glass,
    spacing: DpSpacingTokens.defaults,
    motion: DpMotionTokens.defaults,
  );

  /// The glass dark variant, chosen automatically when the system is dark.
  factory DpTokens.glassDark() => const DpTokens(
    mode: DpMode.glass,
    color: DpPalette.glassDark,
    surface: DpSurfaceTokens.glassDark,
    typography: DpTypeTokens.defaults,
    shape: DpShapeTokens.glass,
    spacing: DpSpacingTokens.defaults,
    motion: DpMotionTokens.defaults,
  );

  /// True when this mode renders frosted translucent surfaces.
  bool get isGlass => mode == DpMode.glass;

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
  ///
  /// `mode` flips at the midpoint rather than interpolating, and that is
  /// deliberate: it is an enum, and a widget that branches on it — `DpSurface`
  /// (#33), `GlassPanel` (#34) — must pick one treatment or the other. Expect a
  /// single switch halfway through a theme animation, not a gradual blend; it
  /// is not a bug in those widgets.
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
    required this.onAccentMark,
    required this.ink,
    required this.textSecondary,
    required this.link,
    required this.inverseLink,
    required this.der,
    required this.onDer,
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
    onAccentMark: Color(0xFFFFFFFF),
    ink: Color(0xFF15121F),
    textSecondary: Color(0xFF5B5670), // Slate Ink
    link: Color(0xFF007A70),
    inverseLink: Color(0xFF00C2B2), // Lagoon, on the ink snackbar
    der: Color(0xFF3D5AFE), // Cobalt
    onDer: Color(0xFFFFFFFF), // Foundations writes its Cobalt swatch in white
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
    almostText: Color(0xFFAE5C01), // 4.6:1 on paper (#163)
    wrongText: Color(0xFFC8341F),
  );

  /// Every value is read off the android-dark `Foundations.html`.
  ///
  /// Dark needs no separate `*Text` gender variants: the light set darkens the
  /// gender colours so they stay legible on cream paper, whereas on Night Ink
  /// the lifted colour is already the readable one, and the artboard uses a
  /// single value for each gender.
  static const DpPalette dark = DpPalette(
    primary: Color(0xFF2EE6D6), // Lagoon, lifted
    onPrimary: Color(0xFF15121F), // dark ink on a bright fill
    accent: Color(0xFFFFD54A), // Sun, lifted
    onAccent: Color(0xFF15121F),
    onAccentMark: Color(0xFFFFFFFF),
    ink: Color(0xFFF4F1FF),
    textSecondary: Color(0xFFB7B1CC),
    link: Color(0xFF2EE6D6),
    inverseLink: Color(0xFF007A70), // deep Lagoon, on the light snackbar
    der: Color(0xFF8C9DFF),
    onDer: Color(0xFF15121F), // the lifted Cobalt is light enough for ink
    derText: Color(0xFF8C9DFF),
    die: Color(0xFFFF8AB2),
    dieText: Color(0xFFFF8AB2),
    das: Color(0xFF4FE3A0),
    dasText: Color(0xFF4FE3A0),
    again: Color(0xFFFF8A7D),
    hard: Color(0xFFFFBE5C),
    good: Color(0xFF2EE6D6),
    easy: Color(0xFFC4F266),
    learning: Color(0xFFFFD54A),
    correctText: Color(0xFF4FE3A0),
    almostText: Color(0xFFFFBE5C),
    wrongText: Color(0xFFFF8A7D),
  );

  /// Aurora Glass, light (#163): the light palette with its text roles
  /// darkened toward ink until each reaches 4.6:1 on a card over the darkest
  /// aurora blob it can overlay (Cobalt at the backdrop's peak opacity), and
  /// the secondary text on the bare backdrop too. theming.md: "Glass text is
  /// checked against the brightest blob it can overlay"; the fills and the
  /// gender colours are the light palette's.
  static const DpPalette glass = DpPalette(
    primary: Color(0xFF00C2B2), // Lagoon
    onPrimary: Color(0xFF15121F),
    accent: Color(0xFFFFC61A), // Sun
    onAccent: Color(0xFF15121F),
    onAccentMark: Color(0xFFFFFFFF),
    ink: Color(0xFF15121F),
    textSecondary: Color(0xFF3B374C),
    link: Color(0xFF046761),
    inverseLink: Color(0xFF00C2B2), // Lagoon, on the ink snackbar
    der: Color(0xFF3D5AFE), // Cobalt
    onDer: Color(0xFFFFFFFF), // Foundations writes its Cobalt swatch in white
    derText: Color(0xFF2F46E0),
    die: Color(0xFFFF3D7F), // Raspberry
    dieText: Color(0xFFB11450),
    das: Color(0xFF00B86B), // Emerald
    dasText: Color(0xFF046941),
    again: Color(0xFFFF5E4D), // Coral
    hard: Color(0xFFFF9F1C), // Tangerine
    good: Color(0xFF00C2B2), // Lagoon
    easy: Color(0xFFA6E22E), // Lime
    learning: Color(0xFFFFC61A), // Sun
    correctText: Color(0xFF046941),
    almostText: Color(0xFF8B4B08),
    wrongText: Color(0xFFAA2E1F),
  );

  /// Aurora Glass, dark (#163): the dark palette, with the secondary text
  /// lifted toward white until it reaches 4.6:1 over the brightest blob (Sun)
  /// on the smoked backdrop and its muted chips. Hierarchy under it comes
  /// from size and weight more than colour.
  static const DpPalette glassDark = DpPalette(
    primary: Color(0xFF2EE6D6), // Lagoon, lifted
    onPrimary: Color(0xFF15121F), // dark ink on a bright fill
    accent: Color(0xFFFFD54A), // Sun, lifted
    onAccent: Color(0xFF15121F),
    onAccentMark: Color(0xFFFFFFFF),
    ink: Color(0xFFF4F1FF),
    textSecondary: Color(0xFFE6E4ED),
    link: Color(0xFF2EE6D6),
    inverseLink: Color(0xFF007A70), // deep Lagoon, on the light snackbar
    der: Color(0xFF8C9DFF),
    onDer: Color(0xFF15121F), // the lifted Cobalt is light enough for ink
    derText: Color(0xFF8C9DFF),
    die: Color(0xFFFF8AB2),
    dieText: Color(0xFFFF8AB2),
    das: Color(0xFF4FE3A0),
    dasText: Color(0xFF4FE3A0),
    again: Color(0xFFFF8A7D),
    hard: Color(0xFFFFBE5C),
    good: Color(0xFF2EE6D6),
    easy: Color(0xFFC4F266),
    learning: Color(0xFFFFD54A),
    correctText: Color(0xFF4FE3A0),
    almostText: Color(0xFFFFBE5C),
    wrongText: Color(0xFFFF8A7D),
  );

  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;

  /// White on a Sun field, in dark mode too: the Learning share of L1's
  /// course bar, beside the ink Done share.
  final Color onAccentMark;
  final Color ink;
  final Color textSecondary;
  final Color link;

  /// A link on an inverse surface — ink in light mode, near-white in dark —
  /// which is where the undo snackbar's *Undo* sits (StudyNew artboard).
  final Color inverseLink;

  /// Gender colours. `*Text` is the accessible variant for text on paper; the
  /// plain value is for fills and bars. Never colour alone — the article is
  /// always printed (`accessibility-performance.md`).
  final Color der;

  /// Text on a Cobalt fill. The one gender colour dark enough in light mode
  /// to need white; Raspberry and Emerald take ink in both.
  final Color onDer;
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
    onAccentMark: Color.lerp(onAccentMark, other.onAccentMark, t)!,
    ink: Color.lerp(ink, other.ink, t)!,
    textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    link: Color.lerp(link, other.link, t)!,
    inverseLink: Color.lerp(inverseLink, other.inverseLink, t)!,
    der: Color.lerp(der, other.der, t)!,
    onDer: Color.lerp(onDer, other.onDer, t)!,
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
    this.blur = 0,
    this.strongBlur = 0,
    this.shadowBlur = 0,
    this.highlight = const Color(0x00FFFFFF),
    this.sheen = const Color(0x00FFFFFF),
    this.auroraOpacity = 0,
    this.scrim = const Color(0x5215121F),
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

  /// theming.md describes the dark treatment as "3 px lines at 30 % white"; the
  /// artboard keeps the same 3 px offset shadow and simply recolours it, which
  /// is what is implemented here.
  static const DpSurfaceTokens dark = DpSurfaceTokens(
    paper: Color(0xFF13111D),
    card: Color(0xFF1E1B2C),
    cardStrong: Color(0xFF1E1B2C),
    muted: Color(0xFF29253A),
    outline: Color(0x38F4F1FF), // ink at 22 %
    outlineWidth: 1.5,
    strongOutlineWidth: 2,
    shadow: Color(0x4DFFFFFF), // white at 30 %
    shadowOffset: Offset(3, 3),
  );

  /// Aurora Glass, light. Frosted translucent panels over a drifting backdrop;
  /// values from the `deutsch-plan-v2-aurora-glass-html` android-light canvas.
  static const DpSurfaceTokens glass = DpSurfaceTokens(
    paper: Color(0xFFF6F3FF), // backdrop under the aurora
    card: Color(0x8CFFFFFF), // white at 55 %
    cardStrong: Color(0xB8FFFFFF), // white at 72 %
    muted: Color(0x59FFFFFF), // white at 35 %
    outline: Color(0xA6FFFFFF), // white at 65 %
    outlineWidth: 1,
    // Buttons stay solid under glass so calls to action never blur; the
    // artboard's primary CTA is `background:#00C2B2; border:none`.
    strongOutlineWidth: 0,
    shadow: Color(0x1A15121F), // ink at 10 %
    shadowOffset: Offset(0, 8),
    shadowBlur: 24,
    blur: 24,
    strongBlur: 32,
    highlight: Color(0xE6FFFFFF), // white at 90 %
    sheen: Color(0x59FFFFFF), // white at 35 %
    auroraOpacity: 0.55,
  );

  /// Aurora Glass, dark — chosen automatically when the system is in dark mode.
  /// Smoked glass over a near-black backdrop, aurora dimmed to 35 %.
  static const DpSurfaceTokens glassDark = DpSurfaceTokens(
    paper: Color(0xFF0E0C16),
    card: Color(0x8C1E1B2C), // rgba(30,27,44,0.55)
    cardStrong: Color(0xB81E1B2C), // rgba(30,27,44,0.72)
    muted: Color(0x1AFFFFFF),
    outline: Color(0x24FFFFFF), // white at 14 %
    outlineWidth: 1,
    strongOutlineWidth: 0, // solid buttons, as in glass light
    shadow: Color(0x59000000), // black at 35 %
    shadowOffset: Offset(0, 8),
    shadowBlur: 24,
    blur: 24,
    strongBlur: 32,
    highlight: Color(0x40FFFFFF), // white at 25 %
    sheen: Color(0x1AFFFFFF), // white at 10 %
    auroraOpacity: 0.35,
  );

  final Color paper;
  final Color card;
  final Color cardStrong;
  final Color muted;
  final Color outline;

  /// Behind a sheet laid over a screen: the Summary artboards' ink at 32 %,
  /// the same in every mode.
  final Color scrim;
  final double outlineWidth;
  final double strongOutlineWidth;

  /// The shadow. Light and dark use a hard offset with no blur; glass uses a
  /// soft 0/8/24 drop.
  final Color shadow;
  final Offset shadowOffset;
  final double shadowBlur;

  /// Backdrop blur behind a `card` and a `cardStrong`. Zero outside glass.
  final double blur;
  final double strongBlur;

  /// The 1 px inset line along the top edge of a glass panel.
  final Color highlight;

  /// The top-to-transparent sheen painted over a glass fill.
  final Color sheen;

  /// Peak opacity of an `AuroraBackdrop` blob (#35). Zero outside glass.
  final double auroraOpacity;

  DpSurfaceTokens lerp(DpSurfaceTokens other, double t) => DpSurfaceTokens(
    paper: Color.lerp(paper, other.paper, t)!,
    scrim: Color.lerp(scrim, other.scrim, t)!,
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
    shadowBlur: lerpDouble(shadowBlur, other.shadowBlur, t)!,
    blur: lerpDouble(blur, other.blur, t)!,
    strongBlur: lerpDouble(strongBlur, other.strongBlur, t)!,
    highlight: Color.lerp(highlight, other.highlight, t)!,
    sheen: Color.lerp(sheen, other.sheen, t)!,
    auroraOpacity: lerpDouble(auroraOpacity, other.auroraOpacity, t)!,
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

  /// Glass rounds everything more, per theming.md and the Aurora Glass
  /// artboards: the primary CTA is drawn at 16 and sheet tops at 28.
  static const DpShapeTokens glass = DpShapeTokens(
    card: 20,
    button: 16,
    chip: 8,
    sheet: 28,
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
    if (tokens == null) {
      // Falling back to Light here would be worse than throwing: the screen
      // would render *almost* right, and under the glass theme that reads as a
      // rendering glitch rather than as a missing theme.
      throw FlutterError(
        'No DpTokens in the theme. Build this subtree with AppTheme.light() '
        '(or its dark/glass counterpart) so the extension is attached — a '
        'route pushed on the root navigator does not inherit a nested Theme.',
      );
    }
    return tokens;
  }
}
