// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/learn/category_words_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L6 · Category words — #121. The artboard's Wohnen & Haushalt: 412 words,
/// its bar, All selected, seven rows with step and status chips.
void main() {
  goldenTest(
    'category_words',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const CategoryWordsScreen(id: 1),
    ),
  );

  // iOS: the title centred, "Categories" on the back chevron.
  goldenTest(
    'category_words_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const CategoryWordsScreen(id: 1),
    ),
  );
}
