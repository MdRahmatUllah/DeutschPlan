import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A stand-in for a screen that has not been built yet.
///
/// #67 is the shell and the route table; the twenty-odd screens are their own
/// issues. A placeholder that names the screen from `navigation.md` is what
/// makes the routing testable now, and it is replaced one route at a time
/// rather than all at once.
///
/// It is deliberately not empty: a blank page tells a router test nothing, and
/// [screen] is what the tests assert on.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.screen,
    this.detail,
    super.key,
  });

  final String title;

  /// The id `navigation.md` uses — `T1`, `L2`, `M4`.
  final String screen;

  /// Whatever the route carried: a step code, a uid, the number of cards.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AdaptiveScaffold(
      title: title,
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.lg),
        children: <Widget>[
          DpText(screen, role: DpTextRole.display),
          SizedBox(height: tokens.spacing.sm),
          DpText(title, role: DpTextRole.title),
          if (detail != null) ...<Widget>[
            SizedBox(height: tokens.spacing.xs),
            DpText(detail!, role: DpTextRole.caption),
          ],
          SizedBox(height: tokens.spacing.xl),
          // Long enough to scroll, which is what the shell's re-tap behaviour
          // needs something to do.
          for (var i = 1; i <= 40; i++)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
              child: DpText('$screen row $i', role: DpTextRole.body),
            ),
        ],
      ),
    );
  }
}
