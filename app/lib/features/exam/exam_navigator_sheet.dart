import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:material_ui/material_ui.dart';

/// One numbered question in the navigator.
typedef NavCell = ({bool answered, bool flagged});

/// What the navigator closes with: the question index to go to, or null
/// for *Submit exam*.
typedef NavChoice = ({int? jump});

/// L12's navigator (`exam-runner.md`, `ExamNavigator-android.html`, #131):
/// "Questions · 14:32 left", the legend with its counts, an 8-column grid
/// of the numbered questions (Lagoon answered, Sun flagged, outline empty,
/// the current one drawn chosen), the note on what is unanswered, and
/// *Submit exam*.
class ExamNavigatorSheet extends StatelessWidget {
  const ExamNavigatorSheet({
    required this.cells,
    required this.current,
    required this.left,
    super.key,
  });

  final List<NavCell> cells;

  /// The cell of the question on screen; null on a task.
  final int? current;

  /// The time left when it opened, as the clock shows it ("14:32"); null
  /// with the timer off.
  // ponytail: a snapshot; the sheet is open for seconds, and the clock
  // behind it keeps running.
  final String? left;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final flagged = cells.where((c) => c.flagged).length;
    final answered = cells.where((c) => c.answered && !c.flagged).length;
    final empty = cells.where((c) => !c.answered && !c.flagged).length;
    final unanswered = cells.where((c) => !c.answered).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: SgText(l10n.examNavTitle, role: SgTextRole.title),
              ),
              if (left case final time?)
                SgText(
                  l10n.examNavLeft(l10n.digits(time)),
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: <Widget>[
              _Key(tokens.color.primary, l10n.examNavAnswered(answered)),
              _Key(
                tokens.color.accent,
                l10n.examNavFlagged(flagged),
                icon: Icons.flag,
              ),
              _Key(null, l10n.examNavEmpty(empty)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 6.0;
              final width = (box.maxWidth - gap * 7) / 8;
              return Wrap(
                spacing: gap,
                // The cells are 40 dp tall (#952).
                runSpacing: AdaptiveTapTarget.runSpacing(40),
                children: <Widget>[
                  for (final (i, cell) in cells.indexed)
                    _Cell(
                      n: i + 1,
                      cell: cell,
                      current: i == current,
                      width: width,
                      onTap: () => Navigator.of(context).pop((jump: i)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          SgText(
            l10n.examNavUnanswered(unanswered),
            role: SgTextRole.caption,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 10),
          SgButton(
            label: l10n.examRunSubmit,
            onPressed: () => Navigator.of(context).pop((jump: null)),
          ),
        ],
      ),
    );
  }
}

/// A legend entry: a swatch and its count.
class _Key extends StatelessWidget {
  const _Key(this.fill, this.label, {this.icon});

  final Color? fill;
  final String label;

  /// The mark the swatch's cells carry besides their fill: the flag, so
  /// flagged is told from answered by shape, not by hue alone (#733).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: fill == null ? tokens.surface.outline : tokens.color.ink,
            ),
          ),
          child: icon == null
              ? null
              : Icon(icon, size: 10, color: tokens.color.onAccent),
        ),
        const SizedBox(width: 6),
        SgText(label, role: SgTextRole.caption),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.n,
    required this.cell,
    required this.current,
    required this.width,
    required this.onTap,
  });

  final int n;
  final NavCell cell;
  final bool current;

  /// An eighth of the grid, less its gaps. Under the target, which grows
  /// the cell's ring past it: a box around the target would stop taps at
  /// its own edge (#478).
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // Flagged wins over answered: the flag is what the learner asked to see.
    final fill = cell.flagged
        ? tokens.color.accent
        : cell.answered
        ? tokens.color.primary
        : null;
    return AdaptiveTapTarget(
      child: SizedBox(
        width: width,
        child: Semantics(
          button: true,
          selected: current,
          label: l10n.examNavQuestion(n),
          value: cell.flagged
              ? l10n.examNavFlaggedState
              : cell.answered
              ? l10n.examNavAnsweredState
              : l10n.examNavEmptyState,
          onTap: onTap,
          excludeSemantics: true,
          // ponytail: 40 dp tall, as the artboard draws it; eight to a row
          // leaves no room for 48 on a phone.
          child: SgSurface(
            kind: fill == null
                ? SgSurfaceKind.bar
                : SgSurfaceKind.tint(fill, opacity: 1),
            selected: current,
            radius: 8,
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Center(
                // A number in a fixed cell shrinks to fit: a Bangla digit is
                // a role larger, and at 200 % the 40 cut it (#580).
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SgText(
                        AppLocalizations.of(context).digits(n),
                        role: SgTextRole.label,
                        weight: 700,
                        color: fill == null
                            ? tokens.color.ink
                            : tokens.color.onAccent,
                      ),
                      // Flagged is told from answered by this mark, not only
                      // by Sun against Lagoon, about 1.4:1 apart (#733, WCAG
                      // 1.4.1). Beside the number and shrunk with it: in a
                      // corner, 200 % text drew the number under it.
                      if (cell.flagged)
                        Icon(
                          Icons.flag,
                          size: 12,
                          color: tokens.color.onAccent,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
