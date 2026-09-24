// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/learn/grammar_library_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L3 · Grammar library — #117. The artboard's library: All · 182, Not
/// learned yet · 145, Due · 2, the A1, A2 and B1 bands.
void main() {
  goldenTest(
    'grammar_library',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const GrammarLibraryScreen(),
    ),
  );

  // iOS: the title centred, a labelled back chevron.
  goldenTest(
    'grammar_library_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const GrammarLibraryScreen(),
    ),
  );
}
