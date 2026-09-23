import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// T1's contextual cards, every kind — #98.
///
/// A sheet rather than six screens: Today shows at most one (FR-T1-06), and
/// the day around it is the in-progress golden's.
void main() {
  goldenTest(
    'today_cards',
    builder: (context) {
      final tokens = context.tokens;
      final sheet = ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final offer in const <ContextualOffer>[
            ContextualOffer(ContextualKind.stepComplete, step: 'A2.2'),
            ContextualOffer(ContextualKind.courseComplete),
            ContextualOffer(
              ContextualKind.contentUpdate,
              version: '202609201200',
              added: 12,
              removed: 3,
              changed: 40,
            ),
            ContextualOffer(ContextualKind.pauseOffer, backlog: 30),
            ContextualOffer(
              ContextualKind.examsUnlocked,
              step: 'A2.1',
              percent: 91,
            ),
            ContextualOffer(ContextualKind.voice),
          ]) ...<Widget>[
            ContextualCard(offer: offer, onAction: () {}, onDismiss: () {}),
            const SizedBox(height: 12),
          ],
        ],
      );
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
