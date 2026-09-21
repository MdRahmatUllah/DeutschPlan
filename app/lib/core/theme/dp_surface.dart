import 'dart:ui' show ImageFilter;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// What a [DpSurface] is being drawn as.
///
/// `docs/01-architecture/theming.md`: "Every card, sheet, header and tab bar is
/// drawn by one widget, `DpSurface`, with a `kind`."
sealed class DpSurfaceKind {
  const DpSurfaceKind();

  /// The ordinary panel: `surface.card`, blurred 24 under glass.
  static const DpSurfaceKind card = _Card();

  /// The denser panel used for sheets and the study card: `surface.cardStrong`,
  /// blurred 32 under glass.
  static const DpSurfaceKind cardStrong = _CardStrong();

  /// A header, tab bar or banner. Same treatment as [card] but without the
  /// drop shadow, since bars sit flush against the screen edge.
  static const DpSurfaceKind bar = _Bar();

  /// A panel tinted toward [colour] — the Lagoon Today header, the Raspberry
  /// sentences band, a gender-tinted study card.
  const factory DpSurfaceKind.tint(Color colour, {double opacity}) = _Tint;
}

final class _Card extends DpSurfaceKind {
  const _Card();
}

final class _CardStrong extends DpSurfaceKind {
  const _CardStrong();
}

final class _Bar extends DpSurfaceKind {
  const _Bar();
}

final class _Tint extends DpSurfaceKind {
  const _Tint(this.colour, {this.opacity = 0.22});

  final Color colour;
  final double opacity;
}

/// The single renderer for every card, sheet, header and tab bar.
///
/// Light and dark draw a token fill with a 1.5 px outline and the hard 3 px
/// down-right offset shadow. Glass draws `ClipRRect` → `BackdropFilter` → fill
/// → 1 px border → top highlight, with a soft 0/8/24 shadow.
///
/// Screens use only this widget, which is why adding the glass mode did not
/// change a single screen file. Keep it that way: a screen that reaches for
/// `BoxDecoration` itself is a screen that will need editing for the next mode.
class DpSurface extends StatelessWidget {
  const DpSurface({
    required this.child,
    super.key,
    this.kind = DpSurfaceKind.card,
    this.padding,
    this.radius,
    this.pressed = false,
    this.onTap,
  });

  final Widget child;
  final DpSurfaceKind kind;
  final EdgeInsetsGeometry? padding;

  /// Defaults to the card radius of the active mode.
  final double? radius;

  /// Collapses the hard shadow and translates the panel by the same offset, so
  /// the surface appears pushed into the paper. Ignored under glass, which has
  /// no offset to collapse.
  final bool pressed;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final corner = radius ?? tokens.shape.card;
    final borderRadius = BorderRadius.circular(corner);

    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    final surface = tokens.isGlass
        ? _glass(tokens, borderRadius, body)
        : _solid(tokens, borderRadius, body);

    final tappable = onTap == null
        ? surface
        : GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: surface,
          );

    if (tokens.isGlass || !pressed) return tappable;

    // Pressed: the panel moves into the space its shadow occupied.
    return Transform.translate(
      offset: tokens.surface.shadowOffset,
      child: tappable,
    );
  }

  Color _fill(DpTokens tokens) => switch (kind) {
    _Card() || _Bar() => tokens.surface.card,
    _CardStrong() => tokens.surface.cardStrong,
    _Tint(:final colour, :final opacity) => colour.withValues(alpha: opacity),
  };

  double _blur(DpTokens tokens) => switch (kind) {
    _CardStrong() => tokens.surface.strongBlur,
    _ => tokens.surface.blur,
  };

  /// Bars sit flush against a screen edge, so they carry no drop shadow.
  bool get _hasShadow => kind is! _Bar;

  Widget _solid(DpTokens tokens, BorderRadius borderRadius, Widget body) {
    final surface = tokens.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _fill(tokens),
        borderRadius: borderRadius,
        border: Border.all(color: surface.outline, width: surface.outlineWidth),
        boxShadow: _hasShadow && !pressed
            ? <BoxShadow>[
                BoxShadow(
                  color: surface.shadow,
                  offset: surface.shadowOffset,
                  blurRadius: surface.shadowBlur,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: body,
    );
  }

  Widget _glass(DpTokens tokens, BorderRadius borderRadius, Widget body) {
    final surface = tokens.surface;
    final blur = _blur(tokens);

    return DecoratedBox(
      // The drop shadow sits outside the clip, or it would be clipped away.
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: _hasShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: surface.shadow,
                  offset: surface.shadowOffset,
                  blurRadius: surface.shadowBlur,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          // The artboard writes this as two stacked layers:
          //   background: linear-gradient(…0.35 → transparent 40%),
          //               rgba(255,255,255,0.55);
          // They must stay two DecoratedBoxes. A BoxDecoration with both `color`
          // and `gradient` paints only the gradient — the fill would vanish and
          // the panel would read as a faint wash instead of frosted glass.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _fill(tokens),
              borderRadius: borderRadius,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: surface.outline,
                  width: surface.outlineWidth,
                ),
                // The sheen: a light wash over the top 40 % of the panel.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.4],
                  colors: <Color>[
                    surface.sheen,
                    surface.sheen.withValues(alpha: 0),
                  ],
                ),
              ),
              child: _TopHighlight(
                colour: surface.highlight,
                radius: borderRadius,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 1 px inset line along the top edge of a glass panel.
class _TopHighlight extends StatelessWidget {
  const _TopHighlight({
    required this.colour,
    required this.radius,
    required this.child,
  });

  final Color colour;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: radius.topLeft.x,
          right: radius.topRight.x,
          child: SizedBox(height: 1, child: ColoredBox(color: colour)),
        ),
      ],
    );
  }
}
