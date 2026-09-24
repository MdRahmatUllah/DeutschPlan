// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/learn/categories_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L5 · Categories — #120. The artboard's eight categories, biggest first,
/// each with its bar.
void main() {
  goldenTest(
    'categories',
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const CategoriesScreen()),
  );

  // iOS: the title centred, a labelled back chevron.
  goldenTest(
    'categories_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const CategoriesScreen()),
  );
}
