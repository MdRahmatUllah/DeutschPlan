// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/words/compare_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// W2 · Compare words — #142. The artboard's Grund / Ursache / Anlass: the
/// labels pinned, the members scrolling on a phone and all three on a
/// tablet, *Quiz these · 5 items* and *Add all 3 to today*.
void main() {
  goldenTest(
    'compare',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const CompareScreen(uid: 'set-grund'),
    ),
  );

  // iOS: the title centred, "Word" on the back chevron.
  goldenTest(
    'compare_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const CompareScreen(uid: 'set-grund'),
    ),
  );
}
