import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the `ThemeData` for each mode and attaches its [DpTokens].
///
/// `docs/01-architecture/theming.md`: "`AppTheme` exposes one `DpTokens` object
/// (a `ThemeExtension`) per mode." Screens read `context.tokens`; they never
/// reach for a hex value and never construct chrome themselves.
///
/// Glass is #32. Material 3 is *not* given a dynamic colour scheme:
/// ADR 12 rules it out so the gender colours stay stable.
abstract final class AppTheme {
  static ThemeData light() => _build(DpTokens.light());

  static ThemeData dark() => _build(DpTokens.dark());

  static ThemeData _build(DpTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.color.primary,
      // Derived from the surface, not the mode name: glass has a dark variant
      // that is still DpMode.glass, and Material needs the real brightness for
      // scrims, system icons and default ripples.
      brightness: tokens.surface.paper.computeLuminance() < 0.5
          ? Brightness.dark
          : Brightness.light,
      primary: tokens.color.primary,
      onPrimary: tokens.color.onPrimary,
      secondary: tokens.color.accent,
      onSecondary: tokens.color.onAccent,
      surface: tokens.surface.card,
      onSurface: tokens.color.ink,
      error: tokens.color.again,
      // fromSeed derives the rest, and its derivations are cold greys that do
      // not belong in Paper & Ink. Every field a Material widget actually
      // reaches for is pinned to a token instead.
      outline: tokens.surface.outline,
      outlineVariant: tokens.surface.outline,
      surfaceContainerLowest: tokens.surface.card,
      surfaceContainerLow: tokens.surface.card,
      surfaceContainer: tokens.surface.muted,
      surfaceContainerHigh: tokens.surface.muted,
      surfaceContainerHighest: tokens.surface.muted,
      onSurfaceVariant: tokens.color.textSecondary,
      tertiary: tokens.color.accent,
      onTertiary: tokens.color.onAccent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.surface.paper,
      fontFamily: AppFonts.latin,
      fontFamilyFallback: AppFonts.fallback,
      textTheme: textTheme(tokens),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }

  /// Maps the seven roles of the scale onto the Material text theme.
  ///
  /// Only the roles the artboards actually use are populated; anything else
  /// would be a value nobody chose.
  static TextTheme textTheme(DpTokens tokens) {
    final type = tokens.typography;
    TextStyle style(DpTextToken token, {Color? color}) => TextStyle(
      fontSize: token.size,
      height: token.heightFactor,
      fontVariations: AppFonts.weight(token.weight),
      fontWeight: _weightOf(token.weight),
      color: color ?? tokens.color.ink,
    );

    return TextTheme(
      displayLarge: style(type.display),
      headlineLarge: style(type.headline),
      titleLarge: style(type.title),
      bodyLarge: style(type.bodyLarge),
      bodyMedium: style(type.body),
      labelLarge: style(type.label),
      bodySmall: style(type.caption, color: tokens.color.textSecondary),
    );
  }

  /// The variable fonts carry the real weight through `fontVariations`; this
  /// keeps `fontWeight` consistent for anything that inspects it.
  static FontWeight _weightOf(double wght) => FontWeight.values.firstWhere(
    (w) => w.value >= wght,
    orElse: () => FontWeight.w900,
  );
}
