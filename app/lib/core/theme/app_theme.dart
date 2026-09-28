import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/app_fonts.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the `ThemeData` for each mode and attaches its [SgTokens].
///
/// `docs/01-architecture/theming.md`: "`AppTheme` exposes one `SgTokens` object
/// (a `ThemeExtension`) per mode." Screens read `context.tokens`; they never
/// reach for a hex value and never construct chrome themselves.
///
/// Material 3 is *not* given a dynamic colour scheme:
/// ADR 12 rules it out so the gender colours stay stable.
abstract final class AppTheme {
  static ThemeData light() => _light;

  static ThemeData dark() => _dark;

  /// [dark] picks the smoked variant; theming.md resolves it from the system
  /// light/dark setting rather than from a separate learner choice.
  static ThemeData glass({bool dark = false}) => dark ? _glassDark : _glass;

  // Each built once: `ColorScheme.fromSeed` works out its tonal palettes, and
  // SogdaApp asks for two themes on every rebuild (#698).
  static final ThemeData _light = _build(SgTokens.light());
  static final ThemeData _dark = _build(SgTokens.dark());
  static final ThemeData _glass = _build(SgTokens.glass());
  static final ThemeData _glassDark = _build(SgTokens.glassDark());

  static ThemeData _build(SgTokens tokens) {
    final dialog = Color.alphaBlend(tokens.surface.card, tokens.surface.paper);
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.color.primary,
      // Derived from the surface, not the mode name: glass has a dark variant
      // that is still SgMode.glass, and Material needs the real brightness for
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
      // A Material widget sets its error text in it (a field's errorText):
      // the text colour, not Coral's fill at 3.0:1 (#698).
      error: tokens.color.wrongText,
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
      // Dialogs and the picker on the card, opaque: `link` is 5.2:1 there
      // and 4.4 on Oat. Under glass the card is 55 % see-through, and the
      // scrim would show through the buttons and digits.
      dialogTheme: DialogThemeData(backgroundColor: dialog),
      timePickerTheme: TimePickerThemeData(backgroundColor: dialog),
      // #164: under reduce motion a page cross-fades; otherwise it moves as
      // the platform's own transition does.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          for (final MapEntry(:key, :value)
              in const PageTransitionsTheme().builders.entries)
            key: StillPageTransitions(value),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }

  /// Maps the seven roles of the scale onto the Material text theme.
  ///
  /// The styles come from [SgText.styleFor] so a role has exactly one
  /// definition. Screens should prefer [SgText], which also applies the Bangla
  /// step-up; this exists for the Material widgets that read the theme.
  static TextTheme textTheme(SgTokens tokens) => TextTheme(
    displayLarge: SgText.styleFor(tokens, SgTextRole.display),
    headlineLarge: SgText.styleFor(tokens, SgTextRole.headline),
    titleLarge: SgText.styleFor(tokens, SgTextRole.title),
    bodyLarge: SgText.styleFor(tokens, SgTextRole.bodyLarge),
    bodyMedium: SgText.styleFor(tokens, SgTextRole.body),
    labelLarge: SgText.styleFor(tokens, SgTextRole.label),
    bodySmall: SgText.styleFor(
      tokens,
      SgTextRole.caption,
      color: tokens.color.textSecondary,
    ),
  );
}

/// A page transition that cross-fades under reduce motion (#164,
/// `accessibility-performance.md`: "cross-fades, no shake…") and is
/// [moving] otherwise, read per build so the OS setting applies live.
///
/// Still, [moving] is built at rest inside the fade: its back gesture (the
/// iOS edge swipe, predictive back) stays and drives the fade. Its timings
/// are [moving]'s either way.
class StillPageTransitions extends PageTransitionsBuilder {
  const StillPageTransitions(this.moving);

  final PageTransitionsBuilder moving;

  @override
  Duration get transitionDuration => moving.transitionDuration;

  @override
  Duration get reverseTransitionDuration => moving.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      moving.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? FadeTransition(
          opacity: animation,
          child: moving.buildTransitions(
            route,
            context,
            kAlwaysCompleteAnimation,
            kAlwaysDismissedAnimation,
            child,
          ),
        )
      : moving.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

/// #164: iOS's Reduce Motion sets `reduceMotion`, not `disableAnimations`
/// (`MediaQueryData.disableAnimations` says so), and every "still" in the app
/// reads the latter: the app root folds the one into the other.
Widget stillOnReduceMotion(BuildContext context, Widget child) =>
    _StillOnReduceMotion(child: child);

/// Live (#686 ST-7): `MediaQueryData` has no `reduceMotion`, so the root
/// MediaQuery doesn't rebuild when only it changes; this hears the change
/// itself. Always a MediaQuery, so the switch keeps the app's state below.
class _StillOnReduceMotion extends StatefulWidget {
  const _StillOnReduceMotion({required this.child});

  final Widget child;

  @override
  State<_StillOnReduceMotion> createState() => _StillOnReduceMotionState();
}

class _StillOnReduceMotionState extends State<_StillOnReduceMotion>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final reduce = View.of(context)
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
    return MediaQuery(
      data: data.copyWith(disableAnimations: data.disableAnimations || reduce),
      child: widget.child,
    );
  }
}
