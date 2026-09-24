import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import '../features/word_fixtures.dart';
import '../services/fake_tts.dart';
import 'golden_harness.dart';

/// W1 · WordDetail — #140. The artboard's die Straße: the sheet at its large
/// detent on a phone, the right-hand pane on a tablet, and the deep link's
/// full page.
void main() {
  List<Override> overrides() => <Override>[
    ...wordStub(),
    ttsProvider.overrideWithValue(FakeTts()),
    // The artboards' Monday: "Next review in 8 days".
    todayProvider.overrideWithValue('2026-09-21'),
  ];

  goldenTest(
    'word_detail',
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );

  // Cupertino presents the sheet with its own popup.
  goldenTest(
    'word_detail_ios',
    modes: <GoldenMode>[GoldenMode.light],
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );

  goldenTest(
    'word_detail_page',
    devices: <GoldenDevice>[GoldenDevice.phone],
    overrides: overrides(),
    builder: (_) => const WordDetailScreen(uid: 'uid-strasse'),
  );
}

/// A blank screen that opens W1 as soon as it is drawn, as a list row's tap
/// would.
class _Opener extends StatefulWidget {
  const _Opener();

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showWordDetail(context, 'uid-strasse'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: const SizedBox.expand(),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}
