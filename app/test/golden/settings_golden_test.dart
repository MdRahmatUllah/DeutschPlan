// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/me/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/settings_fixtures.dart';
import 'golden_harness.dart';

/// M3 · Settings — #146. The artboards' learner, at the top (Settings) and
/// scrolled to the end (SettingsBottom).
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: artboardSettingsStub(),
    child: const SettingsScreen(),
  );

  Future<void> toTheEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
  }

  goldenTest('settings', builder: screen);
  goldenTest('settings_bottom', builder: screen, act: toTheEnd);
  goldenTest(
    'settings_ios',
    builder: screen,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
  );
  goldenTest(
    'settings_bottom_ios',
    builder: screen,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    act: toTheEnd,
  );
}
