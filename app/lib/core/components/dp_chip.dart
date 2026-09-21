import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// The chip families on the Foundations artboard. Each has its own height,
/// weight and treatment, so they are separate kinds rather than one chip with
/// a pile of flags.
enum DpChipKind {
  /// A step code — "A2.1". 24 dp, ink outline, Sun fill when it marks the
  /// active step.
  step,

  /// To do · Learning · Done. 24 dp, Oat fill, no outline, with a status dot.
  status,

  /// All · Learning · Done on a list. 32 dp, Lagoon wash and a tick when on.
  filter,

  /// The streak pill. 28 dp, Sun, ink outline, rounded to a pill.
  streak,

  /// Duden · DWDS · Wiktionary. 32 dp, Oat, no outline, external-link icon.
  webLink,
}

/// A chip in the Paper & Ink treatment.
///
/// Heights, radii and weights are read off `Foundations.html`; they are not
/// Material defaults, and a Material `Chip` cannot be coaxed into them without
/// more overrides than writing this outright.
class DpChip extends StatelessWidget {
  const DpChip({
    required this.label,
    super.key,
    this.kind = DpChipKind.step,
    this.selected = false,
    this.onTap,
    this.statusColour,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final DpChipKind kind;

  /// Marks the active step, the chosen filter, and nothing on the other kinds.
  final bool selected;

  final VoidCallback? onTap;

  /// The dot on a status chip — Oat for To do, Sun for Learning, Lime for Done.
  final Color? statusColour;

  /// Overrides the kind's own icon. Pass `SizedBox.shrink()` to remove it.
  final Widget? icon;

  /// The icon the artboard draws for this kind, at the size it draws it: a
  /// 16 dp flame on the streak pill, a 14 dp tick on a selected filter, a 14 dp
  /// external-link mark on a web link.
  ///
  /// The size travels with the icon rather than being derived from the text
  /// role — the two are unrelated, and deriving one from the other gave the
  /// filter and web-link marks 16 instead of 14.
  ({IconData icon, double size})? get defaultIcon => switch (kind) {
    DpChipKind.streak => (icon: Icons.local_fire_department, size: 16),
    DpChipKind.filter => selected ? (icon: Icons.check, size: 14) : null,
    DpChipKind.webLink => (icon: Icons.open_in_new, size: 14),
    DpChipKind.step || DpChipKind.status => null,
  };

  /// Defaults to [label]. Set it where the label is an abbreviation a screen
  /// reader should expand, such as a step code.
  final String? semanticLabel;

  double get height => switch (kind) {
    DpChipKind.step || DpChipKind.status => 24,
    DpChipKind.streak => 28,
    DpChipKind.filter || DpChipKind.webLink => 32,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final fill = switch (kind) {
      DpChipKind.step => selected ? tokens.color.accent : null,
      DpChipKind.status || DpChipKind.webLink => tokens.surface.muted,
      DpChipKind.streak => tokens.color.accent,
      DpChipKind.filter =>
        selected ? tokens.color.primary.withValues(alpha: 0.22) : null,
    };

    final outline = switch (kind) {
      DpChipKind.step || DpChipKind.streak => tokens.color.ink,
      DpChipKind.filter => selected ? tokens.color.ink : tokens.surface.outline,
      DpChipKind.status || DpChipKind.webLink => null,
    };

    final (role, weight) = switch (kind) {
      DpChipKind.step || DpChipKind.status => (DpTextRole.caption, 700.0),
      DpChipKind.streak => (DpTextRole.label, 700.0),
      DpChipKind.filter || DpChipKind.webLink => (DpTextRole.label, 600.0),
    };

    final radius = kind == DpChipKind.streak ? height / 2 : tokens.shape.chip;

    final fallback = defaultIcon;
    final glyph =
        icon ??
        (fallback == null
            ? null
            : Icon(
                fallback.icon,
                size: fallback.size,
                color: tokens.color.ink,
              ));
    final leading = kind == DpChipKind.webLink ? null : glyph;
    final trailing = kind == DpChipKind.webLink ? glyph : null;

    final chip = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: outline == null ? null : Border.all(color: outline, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (statusColour != null) ...<Widget>[
            _StatusDot(colour: statusColour!, ink: tokens.color.ink),
            SizedBox(width: tokens.spacing.xs + 2),
          ],
          if (leading != null) ...<Widget>[
            leading,
            SizedBox(width: tokens.spacing.xs),
          ],
          DpText(label, role: role, weight: weight),
          // The web-link mark trails its label, as the artboard draws it.
          if (trailing != null) ...<Widget>[
            SizedBox(width: tokens.spacing.xs),
            trailing,
          ],
        ],
      ),
    );

    return Semantics(
      label: semanticLabel ?? label,
      selected: kind == DpChipKind.filter || kind == DpChipKind.step
          ? selected
          : null,
      button: onTap != null,
      child: ExcludeSemantics(
        child: onTap == null
            ? chip
            : GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: chip,
              ),
      ),
    );
  }
}

/// The 8 dp status dot, outlined so it reads on any fill.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.colour, required this.ink});

  final Color colour;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: colour,
      shape: BoxShape.circle,
      border: Border.all(color: ink),
    ),
  );
}
