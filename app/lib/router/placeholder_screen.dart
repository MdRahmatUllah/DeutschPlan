import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
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
          SgText(screen, role: SgTextRole.display),
          SizedBox(height: tokens.spacing.sm),
          SgText(title, role: SgTextRole.title),
          if (detail != null) ...<Widget>[
            SizedBox(height: tokens.spacing.xs),
            SgText(detail!, role: SgTextRole.caption),
          ],
          SizedBox(height: tokens.spacing.xl),
          // Long enough to scroll, which is what the shell's re-tap behaviour
          // needs something to do.
          for (var i = 1; i <= 40; i++)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
              child: SgText('$screen row $i', role: SgTextRole.body),
            ),
        ],
      ),
    );
  }
}
