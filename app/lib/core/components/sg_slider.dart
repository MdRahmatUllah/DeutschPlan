import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// A whole-number slider in the Paper & Ink treatment.
///
/// `OnboardingPace` draws it: a 6 dp Oat track, a Lagoon fill, and a 24 dp
/// thumb with the ink border and hard shadow every raised control has. A
/// Material `Slider` cannot be themed into that thumb, and would still be
/// Material chrome on a screen that must have none.
///
/// Settings draws a smaller one: [compact], a 4 dp track and a 20 dp thumb
/// with no shadow.
///
/// As Material's `Slider`: [onChanged] at every step, for what shows the
/// value, and [onChangeEnd] once, when the finger lets go, for what saves it
/// (#698: Settings wrote user.db at every step of a drag).
class SgSlider extends StatefulWidget {
  const SgSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    super.key,
    this.onChangeEnd,
    this.compact = false,
    this.describe,
  }) : assert(min < max, 'a slider needs somewhere to slide');

  final int value;
  final int min;
  final int max;

  /// Null disables it.
  final ValueChanged<int>? onChanged;

  /// The value a gesture ended on: a tap or a drag let go, and a drag the
  /// scroll view took over, which keeps what the thumb shows, as Material's
  /// does. A key's or a screen reader's step is a whole gesture: it is heard
  /// right after its [onChanged]. Never for a gesture that moved nothing.
  final ValueChanged<int>? onChangeEnd;

  /// What a screen reader calls it — "New words per day".
  final String label;

  /// Settings' size.
  final bool compact;

  /// What a screen reader hears for a value, when the number is not it:
  /// speech speed's 10 is "1.0×". The number itself otherwise.
  final String Function(int value)? describe;

  /// The drawn height, which the focus ring hugs.
  static const double height = 32;

  /// The touch target, and the screen reader's node: 48 dp tall
  /// (`accessibility-performance.md`, #698), the drawn slider at its middle.
  static const double target = 48;

  static const double track = 6;
  static const double thumb = 24;
  static const double compactTrack = 4;
  static const double compactThumb = 20;

  @override
  State<SgSlider> createState() => _SgSliderState();
}

class _SgSliderState extends State<SgSlider> {
  /// The last value this gesture sent through [SgSlider.onChanged], until it
  /// ends. Kept here: the parent's value may not have come back yet when the
  /// finger lifts (a tap's down and up arrive together).
  int? _moved;

  void _end() {
    final moved = _moved;
    _moved = null;
    if (moved != null) widget.onChangeEnd?.call(moved);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final SgSlider(:value, :min, :max, :label, :describe, :compact) = widget;
    final changed = widget.onChanged;

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
          if (next == value || changed == null) return;
          _moved = next;
          changed(next);
        }

        // A step from a key or a screen reader: a gesture of its own.
        void step(int next) {
          _moved = next;
          changed?.call(next);
          _end();
        }

        // #877: the label and the values tagged bn-BD where they are
        // Bangla, as #743 tags every control: in bn the values are Bangla
        // digits ("৫"), which TalkBack on an English phone garbled too.
        return Semantics(
          slider: true,
          attributedLabel: SgScript.attributedLabel(label),
          attributedValue: SgScript.attributedLabel(said(value)),
          attributedIncreasedValue: value < max
              ? SgScript.attributedLabel(said(value + 1))
              : null,
          attributedDecreasedValue: value > min
              ? SgScript.attributedLabel(said(value - 1))
              : null,
          onIncrease: changed != null && value < max
              ? () => step(value + 1)
              : null,
          onDecrease: changed != null && value > min
              ? () => step(value - 1)
              : null,
          // #1007: a keyboard's arrows move it a step each way, as a screen
          // reader's increase and decrease do. Held at the ends rather than
          // passed on, so an arrow never moves the focus off it; up and down
          // stay a D-pad's, to leave it.
          child: GestureDetector(
            // The Semantics above is the slider's whole contract — increase
            // and decrease. Left in, the detector would also offer a screen
            // reader "tap" and "scroll left/right", which do nothing useful.
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTapDown: changed == null
                ? null
                : (details) => moveTo(details.localPosition.dx),
            onTapUp: changed == null ? null : (_) => _end(),
            onHorizontalDragUpdate: changed == null
                ? null
                : (details) => moveTo(details.localPosition.dx),
            onHorizontalDragEnd: changed == null ? null : (_) => _end(),
            // A tap the scroll view took over ends here too, with the value
            // its down moved to (#698: never one shown and not saved).
            onHorizontalDragCancel: changed == null ? null : _end,
            // The 48 dp target round the drawn 32 (#698); the ring hugs the
            // drawn slider.
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: (SgSlider.target - SgSlider.height) / 2,
              ),
              child: SgFocusable(
                onPressed: null,
                radius: BorderRadius.circular(SgSlider.height / 2),
                keys: changed == null
                    ? const <ShortcutActivator, VoidCallback>{}
                    : <ShortcutActivator, VoidCallback>{
                        const SingleActivator(
                          LogicalKeyboardKey.arrowRight,
                        ): () {
                          if (value < max) step(value + 1);
                        },
                        const SingleActivator(
                          LogicalKeyboardKey.arrowLeft,
                        ): () {
                          if (value > min) step(value - 1);
                        },
                      },
                child: SizedBox(
                  height: SgSlider.height,
                  width: width,
                  child: CustomPaint(
                    painter: _SliderPainter(
                      // Clamped: a value outside the range never draws off the
                      // track (#692 ME-4 drew one at 155 %; the range itself
                      // waits for the owner).
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
                      track: compact ? SgSlider.compactTrack : SgSlider.track,
                      thumb: compact ? SgSlider.compactThumb : SgSlider.thumb,
                      shadow: compact ? null : tokens.surface.shadow,
                      shadowOffset: tokens.surface.shadowOffset,
                      shadowBlur: tokens.surface.shadowBlur,
                    ),
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
