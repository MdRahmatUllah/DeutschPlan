import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

/// The four FSRS ratings. `business-rules.md` BR-FSRS-02 fixes both the order
/// and the numbers, which are written into `review_log`.
enum SgRating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const SgRating(this.value);

  /// 1 Again · 2 Hard · 3 Good · 4 Easy.
  final int value;

  Color colourFrom(SgPalette palette) => switch (this) {
    SgRating.again => palette.again,
    SgRating.hard => palette.hard,
    SgRating.good => palette.good,
    SgRating.easy => palette.easy,
  };

  /// Fill opacities, read off the Foundations artboard. They are not uniform —
  /// Lime needs more to register against paper than Coral does.
  double get fillOpacity => switch (this) {
    SgRating.again => 0.14,
    SgRating.hard => 0.16,
    SgRating.good => 0.16,
    SgRating.easy => 0.22,
  };
}

/// The four-button rating bar, with the next interval under each label.
///
/// `study-session.md` FR-T2-05: "Interval previews MUST be computed with the
/// card's current FSRS state on reveal" — this widget only displays them, and
/// the caller passes what `Fsrs.review` returned, so the preview can never
/// disagree with what the scheduler actually writes.
class SgRatingBar extends StatelessWidget {
  const SgRatingBar({
    required this.onRated,
    required this.intervals,
    super.key,
    this.enabled = true,
    this.only,
  });

  final ValueChanged<SgRating> onRated;

  /// The label under each button, already formatted — "1 d", "3 d", "8 d".
  /// Every rating must be present, so a missing preview is a compile error
  /// rather than a blank button.
  final Map<SgRating, String> intervals;

  final bool enabled;

  /// The ratings offered, when not all four are: the rest are drawn faded
  /// and can't be pressed. After a wrong cloze answer, Again and Hard (#345).
  final Set<SgRating>? only;

  /// From the artboard: 60 dp tall, radius 12, 2 px border in the rating colour.
  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // One height for the four, the tallest's: an interval of a thousand
    // days wraps in Bangla at 200 %, and its button grows with the others
    // (#580). Each button's Column fills the row's height, which this bounds.
    return IntrinsicHeight(
      child: Row(
        children: <Widget>[
          for (final rating in SgRating.values) ...<Widget>[
            if (rating != SgRating.again) SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Opacity(
                opacity: only == null || only!.contains(rating) ? 1 : 0.35,
                child: _RatingButton(
                  rating: rating,
                  interval: intervals[rating],
                  onRated: enabled && (only?.contains(rating) ?? true)
                      ? onRated
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.interval,
    required this.onRated,
  });

  final SgRating rating;
  final String? interval;
  final ValueChanged<SgRating>? onRated;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colour = rating.colourFrom(tokens.color);
    final name = _label(context, rating);
    final onTap = onRated == null ? null : () => onRated!(rating);

    return Semantics(
      button: true,
      enabled: onRated != null,
      onTap: onTap,
      // The interval is part of the decision, so it is part of the label rather
      // than a separate node a screen reader might read out of order.
      attributedLabel: SgScript.attributedLabel(
        interval == null ? name : '$name, $interval',
      ),
      child: ExcludeSemantics(
        child: SgFocusable(
          onPressed: onTap,
          radius: BorderRadius.circular(tokens.shape.button),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            // The artboard's 60: two lines of text (32) and the room around
            // them. The lines grow with the text size and the room doesn't: a
            // fixed 60 overflowed at 200 % (#165). A minimum: in Bangla at 200 %
            // an interval of 1,000 days or more wraps (#580).
            child: Container(
              constraints: BoxConstraints(
                minHeight:
                    SgRatingBar.height -
                    32 +
                    SgScript.grow(context, 32, role: SgTextRole.label),
              ),
              decoration: BoxDecoration(
                color: colour.withValues(alpha: rating.fillOpacity),
                borderRadius: BorderRadius.circular(tokens.shape.button),
                border: Border.all(color: colour, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // A word too wide for a quarter of the row shrinks before it
                  // would break: in Bangla at 200 % আবার broke onto a third
                  // line and overflowed the button by 30 dp (#522, #580).
                  SgText(
                    name,
                    role: SgTextRole.label,
                    weight: 700,
                    breakTooWide: true,
                  ),
                  if (interval != null)
                    SgText(
                      interval!,
                      role: SgTextRole.caption,
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

  /// `review_log` stores the integer 1–4; these four words exist only to be
  /// read, so they are copy and live in ARB like everything else the learner
  /// sees. A Bangla learner gets Bangla ratings.
  static String _label(BuildContext context, SgRating rating) {
    final l10n = AppLocalizations.of(context);
    return switch (rating) {
      SgRating.again => l10n.ratingAgain,
      SgRating.hard => l10n.ratingHard,
      SgRating.good => l10n.ratingGood,
      SgRating.easy => l10n.ratingEasy,
    };
  }
}
