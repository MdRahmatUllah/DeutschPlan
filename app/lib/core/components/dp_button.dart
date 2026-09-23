import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// The three button weights the Foundations artboard defines.
enum DpButtonKind {
  /// The one call to action on a screen. 56 dp, brand fill, ink border, hard
  /// offset shadow. "Start today · 20 cards".
  primary,

  /// 48 dp, Oat fill, ink border, no shadow. "Review backlog · 14".
  secondary,

  /// 44 dp, no fill, no border, link colour. "Done for now".
  text,
}

/// A button in the Paper & Ink treatment.
///
/// The hard offset shadow and the 2 px ink border are what make this the
/// project's button rather than a Material one, so screens never reach for
/// `FilledButton` — the architecture test enforces that.
///
/// Under glass the fill stays solid: `theming.md` says "Buttons stay solid so
/// calls to action never blur".
class DpButton extends StatefulWidget {
  const DpButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.kind = DpButtonKind.primary,
    this.icon,
    this.expand = true,
    this.colour,
    this.onColour,
  });

  final String label;

  /// Null disables the button. The all-done state on Today is a disabled Lime
  /// primary, so this has to render, not disappear.
  final VoidCallback? onPressed;

  final DpButtonKind kind;
  final Widget? icon;

  /// Primary buttons are docked full width; a text button hugs its label.
  final bool expand;

  /// Overrides the fill — Today's "All done" primary turns Lime. A text
  /// button has no fill, so on one this is the label: S2's *Skip* is ink on
  /// the coloured header, where the link colour would all but vanish.
  final Color? colour;

  /// The label on a [colour] fill, when the kind's own would not read on it —
  /// dark ink on dark mode's Sun, where the page ink is the light one.
  final Color? onColour;

  /// Visual heights from the artboard. These are the drawn sizes; the hit area
  /// is padded to [minimumTapTarget] where the drawing is smaller, because
  /// accessibility-performance.md asks for ">= 48 dp / 44 pt" and 44 is the iOS
  /// number, not the Android one.
  static const double primaryHeight = 56;
  static const double secondaryHeight = 48;
  static const double textHeight = 44;

  /// Android's minimum. iOS is satisfied by 44.
  static const double minimumTapTarget = 48;

  double get height => switch (kind) {
    DpButtonKind.primary => primaryHeight,
    DpButtonKind.secondary => secondaryHeight,
    DpButtonKind.text => textHeight,
  };

  @override
  State<DpButton> createState() => _DpButtonState();
}

class _DpButtonState extends State<DpButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final kind = widget.kind;

    final fill = switch (kind) {
      DpButtonKind.primary => widget.colour ?? tokens.color.primary,
      DpButtonKind.secondary => widget.colour ?? tokens.surface.muted,
      DpButtonKind.text => null,
    };

    final foreground =
        widget.onColour ??
        switch (kind) {
          DpButtonKind.primary => tokens.color.onPrimary,
          DpButtonKind.secondary => tokens.color.ink,
          DpButtonKind.text => widget.colour ?? tokens.color.link,
        };

    final role = kind == DpButtonKind.primary
        ? DpTextRole.bodyLarge
        : DpTextRole.body;

    // Only the primary carries the hard offset shadow, and only when it is up.
    final shadowed = kind == DpButtonKind.primary && !_down && _enabled;
    final borderless = tokens.isGlass && kind == DpButtonKind.primary;

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          widget.icon!,
          SizedBox(width: tokens.spacing.sm),
        ],
        Flexible(
          child: DpText(
            widget.label,
            role: role,
            weight: 600,
            // A caller that chose the ink keeps it when disabled: Today's
            // "All done" is ink on Lime, not grey.
            color: _enabled || widget.onColour != null
                ? foreground
                : tokens.color.textSecondary,
            // No maxLines: at 200 % a long label needs a second line, and
            // clipping it is worse than a taller button. The button grows with
            // it — its artboard height is a floor, not a fixed size.
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    // A disabled button greys out — unless the caller chose its colour, which
    // is a disabled state designed on purpose: Today's Lime "All done".
    final live = _enabled || widget.colour != null;

    if (kind != DpButtonKind.text) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: live ? fill : tokens.surface.muted,
          borderRadius: BorderRadius.circular(tokens.shape.button),
          // The glass PRIMARY is the borderless one — the artboard draws
          // `background:#00C2B2; border:none`. Branch on the kind rather than
          // reading `strongOutlineWidth == 0` as a sentinel, which would leave
          // the token saying one thing and the button doing another.
          border: borderless
              ? null
              : Border.all(
                  color: live ? tokens.color.ink : tokens.surface.outline,
                  width: 2,
                ),
          boxShadow: shadowed
              ? <BoxShadow>[
                  BoxShadow(
                    color: tokens.surface.shadow,
                    offset: tokens.surface.shadowOffset,
                    blurRadius: tokens.surface.shadowBlur,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        // No Center here: it would expand to the parent's full height and the
        // minHeight below would stop being a floor.
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.lg,
            vertical: tokens.spacing.sm,
          ),
          child: content,
        ),
      );
    }

    // The artboard height is a floor, not a fixed size: at 200 % the label
    // needs a second line and the button grows to hold it.
    final button = Align(
      alignment: Alignment.center,
      widthFactor: widget.expand ? null : 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: kind == DpButtonKind.text
              ? (context.isCupertino
                    ? widget.height
                    : DpButton.minimumTapTarget)
              : widget.height,
          minWidth: widget.expand ? double.infinity : 0,
        ),
        child: content,
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        behavior: HitTestBehavior.opaque,
        // Always present so the tree shape does not change on press, which
        // would drop the gesture — the same trap DpSurface hit in #188.
        child: Transform.translate(
          offset: _down && _enabled && !context.tokens.isGlass
              ? tokens.surface.shadowOffset
              : Offset.zero,
          child: ExcludeSemantics(child: button),
        ),
      ),
    );
  }
}
