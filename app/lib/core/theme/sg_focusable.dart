import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
///
/// #1039: a long press is no finger's alone either. The context-menu key, or
/// Shift+F10, does what [onLongPress] does, as a desktop's context menu opens.
class SgFocusable extends StatefulWidget {
  const SgFocusable({
    required this.onPressed,
    required this.radius,
    required this.child,
    this.keys = const <ShortcutActivator, VoidCallback>{},
    this.onLongPress,
    super.key,
  }) : around = false,
       size = null;

  /// #1049: the ring around a control that takes the focus itself, a
  /// Material or Cupertino switch: no Tab stop or keys of this one's own,
  /// only the ring while the control inside has the focus. [size] is the
  /// drawn part (the switch's track), centred in the tap target.
  const SgFocusable.around({
    required this.radius,
    required this.child,
    this.size,
    super.key,
  }) : onPressed = null,
       onLongPress = null,
       keys = const <ShortcutActivator, VoidCallback>{},
       around = true;

  final VoidCallback? onPressed;

  /// What a long press on the control does, which the context-menu key and
  /// Shift+F10 do too (#1039).
  final VoidCallback? onLongPress;

  /// The keys that stand for a long press.
  static const List<ShortcutActivator> longPressKeys = <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.contextMenu),
    SingleActivator(LogicalKeyboardKey.f10, shift: true),
  ];

  /// The control inside takes the focus: this one only shows the ring.
  final bool around;

  /// The drawn part the ring surrounds, centred; null, the whole child.
  final Size? size;

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
      onInvoke: (intent) => _keys[intent.activator]?.call(),
    ),
  };

  Map<ShortcutActivator, VoidCallback> get _keys =>
      <ShortcutActivator, VoidCallback>{
        ...widget.keys,
        if (widget.onLongPress case final longPress?)
          for (final activator in SgFocusable.longPressKeys)
            activator: longPress,
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
    final keys = _keys;
    final Widget focus = Actions(
      actions: _actions,
      child: Focus(
        canRequestFocus:
            !widget.around &&
            (widget.onPressed != null || keys.isNotEmpty),
        includeSemantics: false,
        onFocusChange: _focus,
        // Always present, so the tree under it keeps its shape as the focus
        // comes and goes: a press under way is never dropped (#188).
        child: CustomPaint(
          foregroundPainter: _ring
              ? _Ring(context.tokens.color.link, widget.radius, widget.size)
              : null,
          child: widget.child,
        ),
      ),
    );
    if (keys.isEmpty) return focus;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final activator in keys.keys) activator: _Key(activator),
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

  /// A finger's, and the context-menu key's or Shift+F10's (#1039).
  final VoidCallback? onLongPress;

  /// The drawn corners, which the focus ring follows.
  final BorderRadius radius;

  /// The site's own `Semantics` already carries the tap.
  final bool excludeFromSemantics;

  final Widget child;

  @override
  Widget build(BuildContext context) => SgFocusable(
    onPressed: onTap,
    onLongPress: onLongPress,
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
  _Ring(this.colour, this.radius, [this.drawn]);

  final Color colour;
  final BorderRadius radius;

  /// The drawn part, centred; null, the whole of what is painted.
  final Size? drawn;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    radius
        .toRRect(
          drawn == null
              ? Offset.zero & size
              : Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: drawn!.width,
                  height: drawn!.height,
                ),
        )
        .inflate(3),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colour,
  );

  @override
  bool shouldRepaint(_Ring old) =>
      old.colour != colour || old.radius != radius || old.drawn != drawn;
}

/// One of [SgFocusable.keys], pressed.
class _Key extends Intent {
  const _Key(this.activator);

  final ShortcutActivator activator;
}
