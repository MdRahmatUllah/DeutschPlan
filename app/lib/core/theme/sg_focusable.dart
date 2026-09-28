import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_tokens.dart';

/// #745: a custom control a keyboard or a D-pad reaches and presses, as a
/// Material button is (WCAG 2.1.1). Tab focuses it; Enter or Space presses
/// it, and on Android a D-pad's centre or a game pad's A too; and
/// while keys are in use a ring in the link colour, 3 dp outside [radius],
/// shows where the focus is. Touch never focuses it, and a disabled control
/// ([onPressed] null) is skipped.
///
/// The control's own `Semantics` is left as authored, with no focusable or
/// focused flags merged into it: a screen reader moves its own focus, and
/// presses through that node's tap action.
class SgFocusable extends StatefulWidget {
  const SgFocusable({
    required this.onPressed,
    required this.radius,
    required this.child,
    this.keys = const <ShortcutActivator, VoidCallback>{},
    super.key,
  });

  final VoidCallback? onPressed;

  /// Keys of the control's own while it has the focus, as a slider's arrows
  /// (#1007). With these, a control nobody presses is still a Tab stop.
  final Map<ShortcutActivator, VoidCallback> keys;

  /// The control's drawn corners, which the ring follows. A circle's or a
  /// pill's is half its height or more.
  final BorderRadius radius;

  final Widget child;

  @override
  State<SgFocusable> createState() => _SgFocusableState();
}

class _SgFocusableState extends State<SgFocusable> {
  bool _focused = false;
  bool _ring = false;

  // Enter and Space, and on Android a D-pad's centre and a game pad's A: the
  // app's shortcuts map each to ActivateIntent (only the web's use another).
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onPressed?.call(),
    ),
    _Key: CallbackAction<_Key>(
      onInvoke: (intent) => widget.keys[intent.activator]?.call(),
    ),
  };

  // #1021: a `FocusableActionDetector`'s parts, less its MouseRegion and its
  // always-on highlight listener. Only the focused control hears the input
  // change, so a list of rows keeps one listener rather than one a row.
  void _focus(bool focused) {
    _focused = focused;
    final manager = FocusManager.instance;
    if (focused) {
      manager.addHighlightModeListener(_show);
    } else {
      manager.removeHighlightModeListener(_show);
    }
    _show(manager.highlightMode);
  }

  /// The ring while keys are in use: a touch hides it again.
  void _show(FocusHighlightMode mode) {
    final ring = _focused && mode == FocusHighlightMode.traditional;
    if (ring != _ring && mounted) setState(() => _ring = ring);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget focus = Actions(
      actions: _actions,
      child: Focus(
        canRequestFocus: widget.onPressed != null || widget.keys.isNotEmpty,
        includeSemantics: false,
        onFocusChange: _focus,
        // Always present, so the tree under it keeps its shape as the focus
        // comes and goes: a press under way is never dropped (#188).
        child: CustomPaint(
          foregroundPainter: _ring
              ? _Ring(context.tokens.color.link, widget.radius)
              : null,
          child: widget.child,
        ),
      ),
    );
    if (widget.keys.isEmpty) return focus;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final activator in widget.keys.keys) activator: _Key(activator),
      },
      child: focus,
    );
  }
}

/// #1021: a screen's own tap target — a row, a link, an icon — pressed by a
/// finger, and reached and pressed by a keyboard or a D-pad as [SgFocusable]
/// lets them. The one way a screen builds one: `architecture_test` keeps a
/// bare `GestureDetector(onTap:` out of `lib/features/`. The site keeps its
/// own `Semantics` and its own size (48 dp, or `AdaptiveTapTarget`).
class SgTappable extends StatelessWidget {
  const SgTappable({
    required this.onTap,
    required this.child,
    this.radius = BorderRadius.zero,
    this.onLongPress,
    this.excludeFromSemantics = false,
    super.key,
  });

  /// Null: neither pressed nor a Tab stop.
  final VoidCallback? onTap;

  /// A finger's alone: no key presses it.
  final VoidCallback? onLongPress;

  /// The drawn corners, which the focus ring follows.
  final BorderRadius radius;

  /// The site's own `Semantics` already carries the tap.
  final bool excludeFromSemantics;

  final Widget child;

  @override
  Widget build(BuildContext context) => SgFocusable(
    onPressed: onTap,
    radius: radius,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeFromSemantics: excludeFromSemantics,
      child: child,
    ),
  );
}

class _Ring extends CustomPainter {
  _Ring(this.colour, this.radius);

  final Color colour;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    radius.toRRect(Offset.zero & size).inflate(3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colour,
  );

  @override
  bool shouldRepaint(_Ring old) => old.colour != colour || old.radius != radius;
}

/// One of [SgFocusable.keys], pressed.
class _Key extends Intent {
  const _Key(this.activator);

  final ShortcutActivator activator;
}
