import 'dart:ui' show ImageFilter;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
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
///
/// **Blur budget.** Under glass every `card` and `cardStrong` is its own
/// `BackdropFilter`. `accessibility-performance.md` caps this at three blur
/// layers on screen — header, one panel, tab bar — and asks for 60 fps with one
/// `BackdropFilter` per list panel. A long list of glass cards (Backlog, Learn,
/// the grammar library, search results) will blow that on a mid-range phone.
/// Rows in a scrolling list should use [DpSurfaceKind.bar], which skips the
/// drop shadow, or wait for the shared-backdrop mechanism in #34.
class DpSurface extends StatefulWidget {
  const DpSurface({
    required this.child,
    super.key,
    this.kind = DpSurfaceKind.card,
    this.padding,
    this.radius,
    this.pressed = false,
    this.selected = false,
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

  /// Drawn as the chosen one of a set: a 2 px border in ink — Lagoon under
  /// glass — and the drop shadow even on a [DpSurfaceKind.bar]. The S2 choice
  /// cards are a bar each until one is picked; the artboards draw exactly
  /// that pair.
  final bool selected;

  final VoidCallback? onTap;

  @override
  State<DpSurface> createState() => _DpSurfaceState();
}

class _DpSurfaceState extends State<DpSurface> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final corner = widget.radius ?? tokens.shape.card;
    final borderRadius = BorderRadius.circular(corner);

    final body = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);

    // Glass without blur is not glass: on a device that will not composite a
    // BackdropFilter, a translucent fill over a live backdrop is unreadable
    // rather than merely plainer. The fallback is opaque, not transparent.
    final surface = tokens.isGlass && GlassCapabilityScope.blurAllowed(context)
        ? _glass(tokens, borderRadius, body)
        : _solid(tokens, borderRadius, body);

    final tappable = widget.onTap == null
        ? surface
        : GestureDetector(
            onTap: widget.onTap,
            // Driven here rather than left to the caller: a panel that takes an
            // onTap and never collapses its shadow is the affordance quietly
            // missing, and every tappable panel would re-implement this.
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            behavior: HitTestBehavior.opaque,
            child: surface,
          );

    // The Transform is always present, with a zero offset when idle. Adding or
    // removing it on press changes the shape of the tree under the
    // GestureDetector, which drops the gesture mid-press: the panel collapses
    // and then never releases, and onTap never fires.
    return Transform.translate(
      offset: tokens.isGlass || !_pressed
          ? Offset.zero
          : tokens.surface.shadowOffset,
      child: tappable,
    );
  }

  /// The caller's explicit state, or a live press on our own gesture.
  bool get _pressed => widget.pressed || _down;

  Color _fill(DpTokens tokens, {required bool degraded}) {
    final base = switch (widget.kind) {
      _Card() || _Bar() => tokens.surface.card,
      _CardStrong() => tokens.surface.cardStrong,
      _Tint(:final colour, :final opacity) => colour.withValues(alpha: opacity),
    };

    // theming.md: glass "degrades to a 92 %-opaque tinted surface". A tint keeps
    // its own weight — it is a colour wash, not a panel.
    if (!degraded || widget.kind is _Tint) return base;
    return base.withValues(alpha: _opaqueFallbackAlpha);
  }

  /// The opacity a glass panel falls back to, per theming.md.
  static const double _opaqueFallbackAlpha = 0.92;

  double _blur(DpTokens tokens) => switch (widget.kind) {
    _CardStrong() => tokens.surface.strongBlur,
    _ => tokens.surface.blur,
  };

  /// Bars sit flush against a screen edge, so they carry no drop shadow —
  /// unless selected, when the shadow is half of what says so.
  bool get _hasShadow => widget.kind is! _Bar || widget.selected;

  static const double _selectedOutlineWidth = 2;

  Widget _solid(DpTokens tokens, BorderRadius borderRadius, Widget body) {
    final surface = tokens.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _fill(tokens, degraded: tokens.isGlass),
        borderRadius: borderRadius,
        border: widget.selected
            ? Border.all(color: tokens.color.ink, width: _selectedOutlineWidth)
            : Border.all(color: surface.outline, width: surface.outlineWidth),
        boxShadow: _hasShadow && !_pressed
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
              color: _fill(tokens, degraded: false),
              borderRadius: borderRadius,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: widget.selected
                    ? Border.all(
                        color: tokens.color.primary,
                        width: _selectedOutlineWidth,
                      )
                    : Border.all(
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
