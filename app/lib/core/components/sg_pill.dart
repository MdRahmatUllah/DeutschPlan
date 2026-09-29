import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';

/// A count on a coloured pill: S3's scores, Today's Tomorrow card, L1's
/// step badges.
///
/// 24 dp, a 1.5 px ink edge — the panel's edge under glass, as the glass
/// artboards draw it — and a bold label.
class SgPill extends StatelessWidget {
  const SgPill({
    required this.label,
    required this.fill,
    super.key,
    this.ink,
    this.small = false,
    this.icon,
  });

  final String label;
  final Color fill;

  /// The label on [fill]. Defaults to the dark ink the bright fills take in
  /// every mode — the page ink is light under dark and would vanish on them.
  final Color? ink;

  /// The artboards' smaller pill: S3's overall score.
  final bool small;

  /// A 16 dp mark before the label: L1's *Passed* tick.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colour = ink ?? tokens.color.onAccent;
    final text = SgText(
      label,
      role: small ? SgTextRole.caption : SgTextRole.label,
      weight: 700,
      color: colour,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(small ? 8 : 14),
        border: tokens.isGlass
            ? Border.all(
                color: tokens.surface.outline,
                width: tokens.surface.outlineWidth,
              )
            : Border.all(color: tokens.color.ink, width: 1.5),
      ),
      child: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: colour),
                const SizedBox(width: 4),
                // #1078: wraps where the pill's column is narrower than the
                // label, as the pill without an icon does: Polish's
                // *Zdany 78%* ran past L10's at 200 %.
                Flexible(child: text),
              ],
            ),
    );
  }
}
