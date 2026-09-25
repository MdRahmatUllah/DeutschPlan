import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/features/study/study_session.dart';
import 'package:material_ui/material_ui.dart';

/// T2's card motion (`study-session.md`, Motion): a rated card leaves —
/// Again slides left, the other ratings lift up — and the next card rises
/// from 16 px below. Reduced motion cross-fades instead.
///
/// [position] keys the card, so a new place in the session is a new card;
/// [left] is how the card that just went was answered.
class StudyCardMotion extends StatelessWidget {
  const StudyCardMotion({
    required this.position,
    required this.left,
    required this.child,
    super.key,
  });

  final int position;
  final CardOutcome? left;
  final Widget child;

  /// How far the next card rises from.
  static const double rise = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    final current = ValueKey<int>(position);
    return AnimatedSwitcher(
      duration: tokens.motion.quick,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (card, animation) {
        if (still) return FadeTransition(opacity: animation, child: card);
        final incoming = card.key == current;
        return AnimatedBuilder(
          animation: animation,
          child: card,
          builder: (context, card) {
            // In, t runs 0 → 1; out, 1 → 0, so (1 - t) is how far along
            // either movement is.
            final away = 1 - animation.value;
            final offset = incoming
                ? Offset(0, rise * away)
                : left == CardOutcome.again
                ? Offset(-MediaQuery.sizeOf(context).width * 0.6 * away, 0)
                : Offset(0, -rise * 2 * away);
            return Opacity(
              opacity: animation.value,
              child: Transform.translate(offset: offset, child: card),
            );
          },
        );
      },
      child: KeyedSubtree(key: current, child: child),
    );
  }
}

/// FR-T2-08: swipe the turned card left for Again, right for Good — only
/// when `swipe_to_rate` is on, and always beside the rating bar, never in
/// place of it (accessibility-performance.md).
class StudySwipeToRate extends StatefulWidget {
  const StudySwipeToRate({
    required this.enabled,
    required this.onRated,
    required this.child,
    super.key,
  });

  final bool enabled;
  final ValueChanged<Rating> onRated;
  final Widget child;

  /// A quarter of the card's width, or a fling, rates it.
  static const double reach = 0.25;
  static const double fling = 700;

  @override
  State<StudySwipeToRate> createState() => _StudySwipeToRateState();
}

class _StudySwipeToRateState extends State<StudySwipeToRate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0;
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final far = _dx.abs() >= width * StudySwipeToRate.reach;
    final flung = velocity.abs() >= StudySwipeToRate.fling;
    if (far || flung) {
      final left = (far ? _dx : velocity) < 0;
      // It leaves from where the finger let go. No reset: the next card is
      // a new place in the session, with a swipe of its own at 0.
      widget.onRated(left ? Rating.again : Rating.good);
      return;
    }
    // #164: reduce motion puts the card back at once.
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dx = 0);
      return;
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    // One shape whether on or off: a tree that changed at reveal would
    // rebuild the card under it, and replay its headword.
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onHorizontalDragStart: on ? (_) => _back.stop() : null,
        onHorizontalDragUpdate: on
            ? (details) => setState(() => _dx += details.delta.dx)
            : null,
        onHorizontalDragEnd: on
            ? (details) => _end(details, constraints.maxWidth)
            : null,
        child: Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ),
    );
  }
}
