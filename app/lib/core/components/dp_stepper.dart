import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// − value +, as `OnboardingPace` and `Settings` both draw it: two 36 dp
/// outlined circles either side of the number.
class DpStepper extends StatelessWidget {
  const DpStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.decreaseLabel,
    required this.increaseLabel,
    super.key,
    this.step = 1,
  });

  final int value;
  final int min;
  final int max;
  final int step;

  /// Null disables both buttons.
  final ValueChanged<int>? onChanged;

  /// "Decrease revisions per day" — the artboard's own aria-labels, because a
  /// bare "minus" tells a screen-reader user nothing about what goes down.
  final String decreaseLabel;
  final String increaseLabel;

  static const double button = 36;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _RoundButton(
          icon: Icons.remove,
          label: decreaseLabel,
          onTap: changed != null && value > min
              ? () => changed((value - step).clamp(min, max))
              : null,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24),
          child: DpText(
            '$value',
            role: DpTextRole.bodyLarge,
            weight: 600,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.add,
          label: increaseLabel,
          onTap: changed != null && value < max
              ? () => changed((value + step).clamp(min, max))
              : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// accessibility-performance.md's 48 dp, around a 36 dp drawing.
  static const double tapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Disabled at an end of the range rather than hidden, so the number does
    // not jump sideways when it reaches 0 or 100.
    final colour = onTap == null
        ? tokens.color.textSecondary
        : tokens.color.ink;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: tapTarget,
          child: Center(
            child: Container(
              width: DpStepper.button,
              height: DpStepper.button,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colour, width: 1.5),
              ),
              child: Icon(icon, size: 18, color: colour),
            ),
          ),
        ),
      ),
    );
  }
}
