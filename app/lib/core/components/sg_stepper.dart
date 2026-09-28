import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';

/// − value +, as `OnboardingPace` and `Settings` both draw it: two 36 dp
/// outlined circles either side of the number. On iOS both draw the number
/// and then UIStepper's pill: − | + on Oat.
class SgStepper extends StatelessWidget {
  const SgStepper({
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
    final VoidCallback? decrease = changed != null && value > min
        ? () => changed((value - step).clamp(min, max))
        : null;
    final VoidCallback? increase = changed != null && value < max
        ? () => changed((value + step).clamp(min, max))
        : null;

    if (context.isCupertino) {
      final tokens = context.tokens;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SgText(
            AppLocalizations.of(context).digits(value),
            role: SgTextRole.bodyLarge,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(width: 12),
          // The pill is 32 pt, as the artboards and UIStepper draw it; the
          // buttons over it are 44 pt, as accessibility-performance.md asks.
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: tokens.surface.muted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PillButton(
                    icon: Icons.remove,
                    label: decreaseLabel,
                    onTap: decrease,
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: tokens.surface.outline,
                  ),
                  _PillButton(
                    icon: Icons.add,
                    label: increaseLabel,
                    onTap: increase,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _RoundButton(icon: Icons.remove, label: decreaseLabel, onTap: decrease),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24),
          child: SgText(
            AppLocalizations.of(context).digits(value),
            role: SgTextRole.bodyLarge,
            weight: 600,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        _RoundButton(icon: Icons.add, label: increaseLabel, onTap: increase),
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
      attributedLabel: SgScript.attributedLabel(label),
      excludeSemantics: true,
      onTap: onTap,
      child: AdaptiveTooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox.square(
            dimension: tapTarget,
            child: Center(
              child: SgFocusable(
                onPressed: onTap,
                radius: BorderRadius.circular(SgStepper.button / 2),
                child: Container(
                  width: SgStepper.button,
                  height: SgStepper.button,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colour, width: 1.5),
                  ),
                  child: Icon(icon, size: 18, color: colour),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      enabled: onTap != null,
      attributedLabel: SgScript.attributedLabel(label),
      excludeSemantics: true,
      onTap: onTap,
      child: AdaptiveTooltip(
        message: label,
        child: SgFocusable(
          onPressed: onTap,
          radius: BorderRadius.circular(22),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.square(
              dimension: 44,
              child: Icon(
                icon,
                size: 18,
                color: onTap == null
                    ? tokens.color.textSecondary
                    : tokens.color.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
