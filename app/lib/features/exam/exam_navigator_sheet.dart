import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
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
                child: DpText(l10n.examNavTitle, role: DpTextRole.title),
              ),
              if (left case final time?)
                DpText(
                  l10n.examNavLeft(l10n.digits(time)),
                  role: DpTextRole.caption,
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
              _Key(tokens.color.accent, l10n.examNavFlagged(flagged)),
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
                runSpacing: gap,
                children: <Widget>[
                  for (final (i, cell) in cells.indexed)
                    SizedBox(
                      width: width,
                      child: _Cell(
                        n: i + 1,
                        cell: cell,
                        current: i == current,
                        onTap: () => Navigator.of(context).pop((jump: i)),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          DpText(
            l10n.examNavUnanswered(unanswered),
            role: DpTextRole.caption,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 10),
          DpButton(
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
  const _Key(this.fill, this.label);

  final Color? fill;
  final String label;

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
        ),
        const SizedBox(width: 6),
        DpText(label, role: DpTextRole.caption),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.n,
    required this.cell,
    required this.current,
    required this.onTap,
  });

  final int n;
  final NavCell cell;
  final bool current;
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
        child: DpSurface(
          kind: fill == null
              ? DpSurfaceKind.bar
              : DpSurfaceKind.tint(fill, opacity: 1),
          selected: current,
          radius: 8,
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: DpText(
                AppLocalizations.of(context).digits(n),
                role: DpTextRole.label,
                weight: 700,
                color: fill == null ? tokens.color.ink : tokens.color.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
