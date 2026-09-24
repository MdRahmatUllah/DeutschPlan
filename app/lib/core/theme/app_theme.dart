import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the `ThemeData` for each mode and attaches its [DpTokens].
///
/// `docs/01-architecture/theming.md`: "`AppTheme` exposes one `DpTokens` object
/// (a `ThemeExtension`) per mode." Screens read `context.tokens`; they never
/// reach for a hex value and never construct chrome themselves.
///
/// Material 3 is *not* given a dynamic colour scheme:
/// ADR 12 rules it out so the gender colours stay stable.
abstract final class AppTheme {
  static ThemeData light() => _build(DpTokens.light());

  static ThemeData dark() => _build(DpTokens.dark());

  /// [dark] picks the smoked variant; theming.md resolves it from the system
  /// light/dark setting rather than from a separate learner choice.
  static ThemeData glass({bool dark = false}) =>
      _build(dark ? DpTokens.glassDark() : DpTokens.glass());

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
      // Under glass this is the backdrop the aurora blobs drift across (#35).
      scaffoldBackgroundColor: tokens.surface.paper,
      fontFamily: AppFonts.latin,
      fontFamilyFallback: AppFonts.fallback,
      textTheme: textTheme(tokens),
      // Lagoon is a fill, and as text it is 2.2:1 on a dialog (#318). A
      // dialog's or picker's text buttons take `link`, Lagoon's text colour.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: tokens.color.link),
      ),
      // The picker on the dialog's card: `link` is 5.2:1 there, 4.4 on Oat.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: tokens.surface.card,
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }

  /// Maps the seven roles of the scale onto the Material text theme.
  ///
  /// The styles come from [DpText.styleFor] so a role has exactly one
  /// definition. Screens should prefer [DpText], which also applies the Bangla
  /// step-up; this exists for the Material widgets that read the theme.
  static TextTheme textTheme(DpTokens tokens) => TextTheme(
    displayLarge: DpText.styleFor(tokens, DpTextRole.display),
    headlineLarge: DpText.styleFor(tokens, DpTextRole.headline),
    titleLarge: DpText.styleFor(tokens, DpTextRole.title),
    bodyLarge: DpText.styleFor(tokens, DpTextRole.bodyLarge),
    bodyMedium: DpText.styleFor(tokens, DpTextRole.body),
    labelLarge: DpText.styleFor(tokens, DpTextRole.label),
    bodySmall: DpText.styleFor(
      tokens,
      DpTextRole.caption,
      color: tokens.color.textSecondary,
    ),
  );
}
