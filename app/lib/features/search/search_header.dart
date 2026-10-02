import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
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
            colour: tokens.color.ink,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: SgText(
                    title,
                    role: SgTextRole.headline,
                    color: tokens.color.ink,
                  ),
                ),
                SgText(
                  intro,
                  role: SgTextRole.caption,
                  color: tokens.color.ink,
                ),
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
        : SgHeaderFill(color: tokens.color.die, child: content);
  }
}
