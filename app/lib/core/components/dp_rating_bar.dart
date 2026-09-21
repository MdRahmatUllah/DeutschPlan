import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// The four FSRS ratings. `business-rules.md` BR-FSRS-02 fixes both the order
/// and the numbers, which are written into `review_log`.
enum DpRating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const DpRating(this.value);

  /// 1 Again · 2 Hard · 3 Good · 4 Easy.
  final int value;

  Color colourFrom(DpPalette palette) => switch (this) {
    DpRating.again => palette.again,
    DpRating.hard => palette.hard,
    DpRating.good => palette.good,
    DpRating.easy => palette.easy,
  };

  /// Fill opacities, read off the Foundations artboard. They are not uniform —
  /// Lime needs more to register against paper than Coral does.
  double get fillOpacity => switch (this) {
    DpRating.again => 0.14,
    DpRating.hard => 0.16,
    DpRating.good => 0.16,
    DpRating.easy => 0.22,
  };
}

/// The four-button rating bar, with the next interval under each label.
///
/// `study-session.md` FR-T2-05: "Interval previews MUST be computed with the
/// card's current FSRS state on reveal" — this widget only displays them, and
/// the caller passes what `Fsrs.review` returned, so the preview can never
/// disagree with what the scheduler actually writes.
class DpRatingBar extends StatelessWidget {
  const DpRatingBar({
    required this.onRated,
    required this.intervals,
    super.key,
    this.enabled = true,
  });

  final ValueChanged<DpRating> onRated;

  /// The label under each button, already formatted — "1 d", "3 d", "8 d".
  /// Every rating must be present, so a missing preview is a compile error
  /// rather than a blank button.
  final Map<DpRating, String> intervals;

  final bool enabled;

  /// From the artboard: 60 dp tall, radius 12, 2 px border in the rating colour.
  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: <Widget>[
        for (final rating in DpRating.values) ...<Widget>[
          if (rating != DpRating.again) SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: _RatingButton(
              rating: rating,
              interval: intervals[rating],
              onRated: enabled ? onRated : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.interval,
    required this.onRated,
  });

  final DpRating rating;
  final String? interval;
  final ValueChanged<DpRating>? onRated;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colour = rating.colourFrom(tokens.color);
    final name = _label(rating);

    return Semantics(
      button: true,
      enabled: onRated != null,
      // The interval is part of the decision, so it is part of the label rather
      // than a separate node a screen reader might read out of order.
      label: interval == null ? name : '$name, $interval',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onRated == null ? null : () => onRated!(rating),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: DpRatingBar.height,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: rating.fillOpacity),
              borderRadius: BorderRadius.circular(tokens.shape.button),
              border: Border.all(color: colour, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DpText(name, role: DpTextRole.label, weight: 700),
                if (interval != null)
                  DpText(
                    interval!,
                    role: DpTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rating names are fixed English terms from the scheduler, not copy —
  /// `business-rules.md` names them and `review_log` stores them. They stay
  /// out of ARB for the same reason the ratings themselves do.
  static String _label(DpRating rating) => switch (rating) {
    DpRating.again => 'Again',
    DpRating.hard => 'Hard',
    DpRating.good => 'Good',
    DpRating.easy => 'Easy',
  };
}
