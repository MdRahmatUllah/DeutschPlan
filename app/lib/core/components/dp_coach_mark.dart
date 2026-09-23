import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A one-line hint pointing at a control, in the Paper & Ink treatment: a Sun
/// bubble with an ink edge and the hard shadow, and a notch towards what it
/// is about.
///
/// FR-S2-03 puts one on Today's primary button after setup. The bubble floats
/// above [child] in the overlay, so it neither moves the layout nor gets
/// clipped by it; a tap on it dismisses it.
class DpCoachMark extends StatefulWidget {
  const DpCoachMark({
    required this.child,
    required this.message,
    required this.visible,
    required this.onDismissed,
    super.key,
    this.onShown,
  });

  /// What the mark points at.
  final Widget child;
  final String message;
  final bool visible;
  final VoidCallback onDismissed;

  /// Called once, the first frame the mark is on screen — which is when a
  /// one-time mark has been "shown", whether or not it is ever tapped.
  final VoidCallback? onShown;

  @override
  State<DpCoachMark> createState() => _DpCoachMarkState();
}

class _DpCoachMarkState extends State<DpCoachMark> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DpCoachMark old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _sync();
  }

  /// After the frame, because the overlay cannot be shown mid-build.
  void _sync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (widget.visible && !_portal.isShowing) {
      _portal.show();
      if (!_reported) {
        _reported = true;
        widget.onShown?.call();
      }
    } else if (!widget.visible && _portal.isShowing) {
      _portal.hide();
    }
  });

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        // Its bottom centre on the target's top centre, a little above it.
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        offset: const Offset(0, -8),
        child: _Bubble(message: widget.message, onTap: widget.onDismissed),
      ),
    ),
    child: CompositedTransformTarget(link: _link, child: widget.child),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  static const double maxWidth = 280;
  static const double notch = 10;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      // Read as it appears, and dismissable like any other button.
      liveRegion: true,
      button: true,
      label: message,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.color.accent,
                  borderRadius: BorderRadius.circular(tokens.shape.button),
                  border: Border.all(color: tokens.color.ink, width: 2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: tokens.surface.shadow,
                      offset: tokens.surface.shadowOffset,
                      blurRadius: tokens.surface.shadowBlur,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: DpText(
                    message,
                    role: DpTextRole.label,
                    weight: 600,
                    color: tokens.color.onAccent,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(notch * 2, notch),
                painter: _Notch(
                  fill: tokens.color.accent,
                  edge: tokens.color.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The downward notch, drawn over the bubble's bottom edge so the ink line
/// breaks where the notch leaves it.
class _Notch extends CustomPainter {
  const _Notch({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -2);
    canvas
      ..drawPath(path..close(), Paint()..color = fill)
      ..drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0),
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_Notch old) => old.fill != fill || old.edge != edge;
}
