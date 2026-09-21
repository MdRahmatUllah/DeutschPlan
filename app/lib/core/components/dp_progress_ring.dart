import 'dart:math' as math;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// The progress ring on Today, the session summary and the widget.
///
/// From the Foundations artboard: a 120 unit box, radius 54, stroke 12, an Oat
/// track under a Lagoon arc with a round cap, starting at twelve o'clock.
/// Today draws it at 132 dp; the geometry scales with [size].
class DpProgressRing extends StatelessWidget {
  const DpProgressRing({
    required this.completed,
    required this.total,
    super.key,
    this.size = 120,
    this.caption,
    this.colour,
    this.semanticLabel,
  });

  final int completed;
  final int total;
  final double size;

  /// The line under the count — "≈ 6 min left".
  final String? caption;

  /// Defaults to Lagoon. Today's all-done state passes Lime.
  final Color? colour;

  /// Defaults to "completed of total". Pass one where the ring means something
  /// other than cards, so a screen reader says what it is counting.
  final String? semanticLabel;

  /// Fractions of the artboard's 120 unit box, so any [size] keeps the
  /// proportions the design was drawn at.
  static const double _radiusFraction = 54 / 120;
  static const double _strokeFraction = 12 / 120;

  /// 0 when nothing is planned — an empty ring, never a divide by zero.
  double get progress => total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      label: semanticLabel ?? '$completed of $total',
      value: '${(progress * 100).round()}%',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: progress,
              track: tokens.surface.muted,
              arc: colour ?? tokens.color.primary,
              stroke: size * _strokeFraction,
              radiusFraction: _radiusFraction,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DpText(
                    '$completed / $total',
                    role: DpTextRole.title,
                    weight: 600,
                  ),
                  if (caption != null)
                    DpText(
                      caption!,
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.arc,
    required this.stroke,
    required this.radiusFraction,
  });

  final double progress;
  final Color track;
  final Color arc;
  final double stroke;
  final double radiusFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width * radiusFraction;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(centre, radius, trackPaint);

    if (progress <= 0) return;

    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      // The artboard uses stroke-linecap: round.
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // The artboard rotates -90°, so the arc starts at twelve o'clock.
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.arc != arc ||
      old.stroke != stroke;
}

/// The Done / Learning / To do bar under a step tile or on the Me card.
///
/// From the artboard: 8 dp tall, radius 4, 2 dp gaps, segments weighted by
/// count with a 2 dp minimum so a tiny count still shows.
class DpSegmentedBar extends StatelessWidget {
  const DpSegmentedBar({
    required this.done,
    required this.learning,
    required this.todo,
    super.key,
    this.height = 8,
    this.semanticLabel,
  });

  final int done;
  final int learning;
  final int todo;
  final double height;
  final String? semanticLabel;

  /// A segment never disappears entirely — one learned word out of five hundred
  /// still earns a sliver, which is the point of showing progress at all.
  static const double minimumSegment = 2;

  int get total => done + learning + todo;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final segments = <(int, Color)>[
      (done, tokens.color.easy),
      (learning, tokens.color.learning),
      (todo, tokens.surface.muted),
    ].where((s) => s.$1 > 0).toList();

    return Semantics(
      label: semanticLabel ?? '$done done, $learning learning, $todo to do',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: total == 0
                ? ColoredBox(color: tokens.surface.muted)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Widths are computed rather than left to flex: a
                      // Flexible child with a minWidth collapses TO that
                      // minimum instead of taking its share, and an Expanded
                      // one ignores the minimum entirely. Neither gives
                      // "proportional, but never thinner than 2 dp".
                      final gaps = 2.0 * (segments.length - 1);
                      final available = math.max(
                        0.0,
                        constraints.maxWidth - gaps,
                      );
                      final counts = segments.map((s) => s.$1).toList();
                      final sum = counts.fold(0, (a, b) => a + b);

                      final widths = <double>[
                        for (final count in counts)
                          math.max(minimumSegment, available * (count / sum)),
                      ];

                      // Honouring the floor can overshoot; take the excess back
                      // from the widest segment, which can afford it.
                      final overflow =
                          widths.fold(0.0, (a, b) => a + b) - available;
                      if (overflow > 0) {
                        final widest = widths.indexOf(widths.reduce(math.max));
                        widths[widest] = math.max(
                          minimumSegment,
                          widths[widest] - overflow,
                        );
                      }

                      return Row(
                        children: <Widget>[
                          for (var i = 0; i < segments.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 2),
                            SizedBox(
                              width: widths[i],
                              child: ColoredBox(color: segments[i].$2),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
