import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:material_ui/material_ui.dart';

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
    super.key,
  });

  final VoidCallback? onPressed;

  /// The control's drawn corners, which the ring follows. A circle's or a
  /// pill's is half its height or more.
  final BorderRadius radius;

  final Widget child;

  @override
  State<SgFocusable> createState() => _SgFocusableState();
}

class _SgFocusableState extends State<SgFocusable> {
  bool _ring = false;

  // Enter and Space, and on Android a D-pad's centre and a game pad's A: the
  // app's shortcuts map each to ActivateIntent (only the web's use another).
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onPressed?.call(),
    ),
  };

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onPressed != null,
    includeFocusSemantics: false,
    actions: _actions,
    onShowFocusHighlight: (on) => setState(() => _ring = on),
    // Always present, so the tree under it keeps its shape as the focus comes
    // and goes: a press under way is never dropped (#188).
    child: CustomPaint(
      foregroundPainter: _ring
          ? _Ring(context.tokens.color.link, widget.radius)
          : null,
      child: widget.child,
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
