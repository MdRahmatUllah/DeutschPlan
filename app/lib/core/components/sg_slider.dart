import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';

/// A whole-number slider in the Paper & Ink treatment.
///
/// `OnboardingPace` draws it: a 6 dp Oat track, a Lagoon fill, and a 24 dp
/// thumb with the ink border and hard shadow every raised control has. A
/// Material `Slider` cannot be themed into that thumb, and would still be
/// Material chrome on a screen that must have none.
///
/// Settings draws a smaller one: [compact], a 4 dp track and a 20 dp thumb
/// with no shadow.
class SgSlider extends StatelessWidget {
  const SgSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    super.key,
    this.compact = false,
    this.describe,
  }) : assert(min < max, 'a slider needs somewhere to slide');

  final int value;
  final int min;
  final int max;

  /// Null disables it.
  final ValueChanged<int>? onChanged;

  /// What a screen reader calls it — "New words per day".
  final String label;

  /// Settings' size.
  final bool compact;

  /// What a screen reader hears for a value, when the number is not it:
  /// speech speed's 10 is "1.0×". The number itself otherwise.
  final String Function(int value)? describe;

  static const double height = 32;
  static const double track = 6;
  static const double thumb = 24;
  static const double compactTrack = 4;
  static const double compactThumb = 20;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final changed = onChanged;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Rounded to the nearest whole value, so a drag lands on a number
        // rather than between two.
        int valueAt(double dx) =>
            (min + (dx / width).clamp(0.0, 1.0) * (max - min)).round();

        String said(int value) =>
            describe?.call(value) ?? AppLocalizations.of(context).digits(value);

        void moveTo(double dx) {
          final next = valueAt(dx);
          if (next != value) changed?.call(next);
        }

        // #877: the label and the values tagged bn-BD where they are
        // Bangla, as #743 tags every control: in bn the values are Bangla
        // digits ("৫"), which TalkBack on an English phone garbled too.
        // A step each way, landing inside the range from a value outside
        // it (restart setup's pace beyond page 4's, #1011 ME-4); none past
        // an end.
        final up = value < max ? (value + 1).clamp(min, max) : null;
        final down = value > min ? (value - 1).clamp(min, max) : null;

        return Semantics(
          slider: true,
          attributedLabel: SgScript.attributedLabel(label),
          attributedValue: SgScript.attributedLabel(said(value)),
          attributedIncreasedValue: up == null
              ? null
              : SgScript.attributedLabel(said(up)),
          attributedDecreasedValue: down == null
              ? null
              : SgScript.attributedLabel(said(down)),
          onIncrease: changed != null && up != null ? () => changed(up) : null,
          onDecrease: changed != null && down != null
              ? () => changed(down)
              : null,
          // #1007: a keyboard's arrows move it a step each way, as a screen
          // reader's increase and decrease do. Held at the ends rather than
          // passed on, so an arrow never moves the focus off it; up and down
          // stay a D-pad's, to leave it.
          child: SgFocusable(
            onPressed: null,
            radius: BorderRadius.circular(height / 2),
            keys: changed == null
                ? const <ShortcutActivator, VoidCallback>{}
                : <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                      if (up != null) changed(up);
                    },
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                      if (down != null) changed(down);
                    },
                  },
            child: GestureDetector(
              // The Semantics above is the slider's whole contract — increase
              // and decrease. Left in, the detector would also offer a screen
              // reader "tap" and "scroll left/right", which do nothing useful.
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTapDown: changed == null
                  ? null
                  : (details) => moveTo(details.localPosition.dx),
              onHorizontalDragUpdate: changed == null
                  ? null
                  : (details) => moveTo(details.localPosition.dx),
              child: SizedBox(
                height: height,
                width: width,
                child: CustomPaint(
                  painter: _SliderPainter(
                    // Clamped: a value outside the range never draws off the
                    // track (#692 ME-4 drew one at 155 %).
                    fraction: ((value - min) / (max - min)).clamp(0.0, 1.0),
                    rail: tokens.surface.track,
                    fill: tokens.color.primary,
                    thumbFill: tokens.surface.card,
                    // Ink on paper; the glass hairline under glass, as the
                    // glass artboards draw every raised control.
                    thumbBorder: tokens.isGlass
                        ? tokens.surface.outline
                        : tokens.color.ink,
                    thumbBorderWidth: tokens.isGlass
                        ? tokens.surface.outlineWidth
                        : 2,
                    track: compact ? compactTrack : track,
                    thumb: compact ? compactThumb : thumb,
                    shadow: compact ? null : tokens.surface.shadow,
                    shadowOffset: tokens.surface.shadowOffset,
                    shadowBlur: tokens.surface.shadowBlur,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.fraction,
    required this.rail,
    required this.track,
    required this.thumb,
    required this.fill,
    required this.thumbFill,
    required this.thumbBorder,
    required this.thumbBorderWidth,
    required this.shadow,
    required this.shadowOffset,
    required this.shadowBlur,
  });

  final double fraction;
  final Color rail;
  final double track;
  final double thumb;
  final Color fill;
  final Color thumbFill;
  final Color thumbBorder;
  final double thumbBorderWidth;
  final Color? shadow;
  final Offset shadowOffset;
  final double shadowBlur;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final rail = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, middle - track / 2, size.width, track),
      Radius.circular(track / 2),
    );

    canvas
      ..save()
      ..clipRRect(rail)
      ..drawRRect(rail, Paint()..color = this.rail)
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width * fraction, size.height),
        Paint()..color = fill,
      )
      ..restore();

    // The thumb's centre sits on the value, as the artboard's
    // `left: calc(15% - 12px)` puts it — so at either end it overhangs the
    // track by half its width, into the screen's own margin.
    final centre = Offset(size.width * fraction, middle);
    final radius = thumb / 2;

    final shadow = this.shadow;
    if (shadow != null) {
      canvas.drawCircle(
        centre + shadowOffset,
        radius,
        Paint()
          ..color = shadow
          ..maskFilter = shadowBlur == 0
              ? null
              : MaskFilter.blur(BlurStyle.normal, shadowBlur / 2),
      );
    }
    canvas
      ..drawCircle(centre, radius, Paint()..color = thumbFill)
      ..drawCircle(
        centre,
        radius - thumbBorderWidth / 2,
        Paint()
          ..color = thumbBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = thumbBorderWidth,
      );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.rail != rail ||
      old.track != track ||
      old.thumb != thumb ||
      old.fill != fill ||
      old.thumbFill != thumbFill ||
      old.thumbBorder != thumbBorder ||
      old.shadow != shadow;
}
