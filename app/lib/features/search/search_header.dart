import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/system_bars.dart';
import 'package:sogda/core/typography/sg_text.dart';

/// The band over the Search tab's pushed pages (R2, D1): back, the title,
/// and a line under it, on the tab's Raspberry. It runs under the status bar.
class SearchHeader extends StatelessWidget {
  const SearchHeader({required this.title, required this.intro, super.key});

  final String title;
  final String intro;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // #1412: on the Raspberry fill, the dark ink in every theme, as Today's
    // header (the page ink is light in dark mode: ~2:1 on its pink). Glass
    // has no fill, only a tint over frosted paper, so it keeps the page ink.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.paddingOf(context).top + 4,
        16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AdaptiveBackButton(
            colour: ink,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: SgText(title, role: SgTextRole.headline, color: ink),
                ),
                SgText(intro, role: SgTextRole.caption, color: ink),
              ],
            ),
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? SgSurface(
            kind: SgSurfaceKind.tint(tokens.color.die),
            radius: 0,
            child: content,
          )
        : SgHeaderFill(
            color: tokens.color.die,
            // #1064: the ring in the dark ink too, as R1's on die.
            child: SgFocusRingColour(colour: ink, child: content),
          );
  }
}
