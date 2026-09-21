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
  });

  final String label;

  /// Null disables the button. The all-done state on Today is a disabled Lime
  /// primary, so this has to render, not disappear.
  final VoidCallback? onPressed;

  final DpButtonKind kind;
  final Widget? icon;

  /// Primary buttons are docked full width; a text button hugs its label.
  final bool expand;

  /// Overrides the fill — Today's "All done" primary turns Lime.
  final Color? colour;

  /// Heights from the artboard. All clear the 48 dp minimum except `text`,
  /// which is 44 and is allowed to be: it is a text link, sized to the iOS
  /// minimum of 44 pt.
  static const double primaryHeight = 56;
  static const double secondaryHeight = 48;
  static const double textHeight = 44;

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

    final foreground = switch (kind) {
      DpButtonKind.primary => tokens.color.onPrimary,
      DpButtonKind.secondary => tokens.color.ink,
      DpButtonKind.text => tokens.color.link,
    };

    final role = kind == DpButtonKind.primary
        ? DpTextRole.bodyLarge
        : DpTextRole.body;

    // Only the primary carries the hard offset shadow, and only when it is up.
    final shadowed = kind == DpButtonKind.primary && !_down && _enabled;

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
            color: _enabled ? foreground : tokens.color.textSecondary,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    if (kind != DpButtonKind.text) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: _enabled ? fill : tokens.surface.muted,
          borderRadius: BorderRadius.circular(tokens.shape.button),
          border: tokens.isGlass && kind == DpButtonKind.primary
              // Glass buttons are solid with no outline: the artboard draws
              // `background:#00C2B2; border:none`.
              ? null
              : Border.all(
                  color: _enabled ? tokens.color.ink : tokens.surface.outline,
                  width: tokens.surface.strongOutlineWidth == 0
                      ? 2
                      : tokens.surface.strongOutlineWidth,
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
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          child: Center(child: content),
        ),
      );
    }

    final button = SizedBox(
      height: widget.height,
      width: widget.expand ? double.infinity : null,
      child: content,
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
