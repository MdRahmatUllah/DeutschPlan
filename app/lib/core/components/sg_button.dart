import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_focusable.dart';

/// The three button weights the Foundations artboard defines.
enum SgButtonKind {
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
class SgButton extends StatefulWidget {
  const SgButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.kind = SgButtonKind.primary,
    this.icon,
    this.expand = true,
    this.colour,
    this.onColour,
    this.compact = false,
    this.drawnHeight,
  });

  final String label;

  /// Null disables the button. The all-done state on Today is a disabled Lime
  /// primary, so this has to render, not disappear.
  final VoidCallback? onPressed;

  final SgButtonKind kind;
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

  /// The artboards' inline primary: 40 dp and the body text, beside the
  /// line it acts on — L1's *Study*. Its hit area is still
  /// [minimumTapTarget] tall.
  final bool compact;

  /// The drawn height where an artboard draws a primary between the two
  /// sizes: 48 on L2's Grammar tab and on Export. The label stays the
  /// primary's; the hit area is never under [minimumTapTarget].
  final double? drawnHeight;

  /// Visual heights from the artboard. These are the drawn sizes; the hit area
  /// is padded to [minimumTapTarget] where the drawing is smaller, because
  /// accessibility-performance.md asks for ">= 48 dp / 44 pt" and 44 is the iOS
  /// number, not the Android one.
  static const double primaryHeight = 56;
  static const double secondaryHeight = 48;
  static const double textHeight = 44;
  static const double compactHeight = 40;

  /// Android's minimum. iOS is satisfied by 44.
  static const double minimumTapTarget = 48;

  double get height => switch (kind) {
    _ when drawnHeight != null => drawnHeight!,
    _ when compact => compactHeight,
    SgButtonKind.primary => primaryHeight,
    SgButtonKind.secondary => secondaryHeight,
    SgButtonKind.text => textHeight,
  };

  @override
  State<SgButton> createState() => _SgButtonState();
}

class _SgButtonState extends State<SgButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  /// A button disabled mid-press is raised here: it came back enabled still
  /// down, without its shadow. Its gesture goes with the callback, and
  /// cancels only once the tree is locked, too late for a setState (#686
  /// ST-10).
  @override
  void didUpdateWidget(SgButton old) {
    super.didUpdateWidget(old);
    if (!_enabled) _down = false;
  }

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final kind = widget.kind;

    final fill = switch (kind) {
      SgButtonKind.primary => widget.colour ?? tokens.color.primary,
      SgButtonKind.secondary => widget.colour ?? tokens.surface.muted,
      SgButtonKind.text => null,
    };

    final foreground =
        widget.onColour ??
        switch (kind) {
          SgButtonKind.primary => tokens.color.onPrimary,
          SgButtonKind.secondary => tokens.color.ink,
          SgButtonKind.text => widget.colour ?? tokens.color.link,
        };

    final role = kind == SgButtonKind.primary && !widget.compact
        ? SgTextRole.bodyLarge
        : SgTextRole.body;

    // Only the primary carries the hard offset shadow, and only when it is up.
    final shadowed = kind == SgButtonKind.primary && !_down && _enabled;
    final borderless = tokens.isGlass && kind == SgButtonKind.primary;

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          widget.icon!,
          SizedBox(width: tokens.spacing.sm),
        ],
        Flexible(
          child: SgText(
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

    if (kind != SgButtonKind.text) {
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
            horizontal: widget.compact ? 18 : tokens.spacing.lg,
            vertical: tokens.spacing.sm,
          ),
          child: content,
        ),
      );
    }

    // The artboard height is a floor, not a fixed size: at 200 % the label
    // needs a second line and the button grows to hold it.
    Widget button = Align(
      alignment: Alignment.center,
      widthFactor: widget.expand ? null : 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: kind == SgButtonKind.text
              ? (context.isCupertino
                    ? widget.height
                    : SgButton.minimumTapTarget)
              : widget.height,
          minWidth: widget.expand ? double.infinity : 0,
        ),
        child: content,
      ),
    );
    if (widget.compact) {
      // Drawn at 40, touched at 48: the Align above centres the drawing in
      // the taller box.
      button = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SgButton.minimumTapTarget),
        child: button,
      );
    }

    return AdaptiveTapTarget(
      child: Semantics(
        button: true,
        enabled: _enabled,
        attributedLabel: SgScript.attributedLabel(widget.label),
        child: SgFocusable(
          onPressed: widget.onPressed,
          radius: BorderRadius.circular(tokens.shape.button),
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: _enabled ? (_) => _press(true) : null,
            onTapUp: _enabled ? (_) => _press(false) : null,
            onTapCancel: _enabled ? () => _press(false) : null,
            behavior: HitTestBehavior.opaque,
            // Always present so the tree shape does not change on press, which
            // would drop the gesture — the same trap SgSurface hit in #188.
            child: Transform.translate(
              offset: _down && _enabled && !context.tokens.isGlass
                  ? tokens.surface.shadowOffset
                  : Offset.zero,
              child: ExcludeSemantics(child: button),
            ),
          ),
        ),
      ),
    );
  }
}
