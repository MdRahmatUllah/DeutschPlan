import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// #522, the owner's decision: a Bangla word a little too wide for its line
/// shrinks to fit it whole, rather than break. The line here is 90 % of the
/// pronunciation's own width, at whatever the text size is, so it shrinks
/// at every audit scale too.
void main() {
  goldenTest(
    'bangla_shrink',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) {
      final tokens = context.tokens;
      // Vergangenheitsbewältigung's, from content.db.
      const pron = '/ফেয়াগাঙেনহাইট্‌সবেভেল্টিগুং/';
      final painter = TextPainter(
        text: TextSpan(
          text: pron,
          style: SgText.styleFor(tokens, SgTextRole.body.oneStepLarger),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width * 0.9;
      painter.dispose();
      // A page's text style, as a screen's scaffold gives it.
      return Material(
        color: tokens.surface.paper,
        child: Center(
          child: SizedBox(
            width: width,
            child: const SgText(
              'Nomen · $pron',
              role: SgTextRole.body,
              breakTooWide: true,
            ),
          ),
        ),
      );
    },
  );
}
