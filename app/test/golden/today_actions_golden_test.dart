import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// T1's docked button in every state FR-T1-03 names — #99.
///
/// One sheet rather than one screen per state: the states differ only in the
/// button, and the done and rest-day screens around it are #96 and #97.
void main() {
  goldenTest(
    'today_actions',
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final tokens = context.tokens;
      final sheet = ListView(
        children: <Widget>[
          for (final (action, label) in <(TodayAction, String)>[
            (TodayAction.start, l10n.todayStart(20)),
            (TodayAction.resume, l10n.todayContinue(8)),
            (TodayAction.sentences, l10n.todaySentencesAction(3)),
            (TodayAction.backlog, l10n.todayBacklogAction(14)),
            (TodayAction.done, l10n.todayAllDone),
            (TodayAction.reviseAnyway, l10n.todayReviseAnyway(6)),
          ])
            PrimaryActionBar(
              action: action,
              label: label,
              onPressed: action == TodayAction.done ? null : () {},
            ),
        ],
      );
      // Today's own paper: the aurora under glass.
      return AdaptiveScaffold(
        backgroundColor: tokens.isGlass
            ? tokens.surface.paper.withValues(alpha: 0)
            : tokens.surface.paper,
        body: tokens.isGlass
            ? AuroraBackdrop(leading: tokens.color.primary, child: sheet)
            : sheet,
      );
    },
  );
}
