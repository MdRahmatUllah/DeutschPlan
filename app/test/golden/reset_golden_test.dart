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

/// M7 · Reset — #149. The ResetDialog artboards: *Reset everything?* over
/// Settings, "RES" typed and *Reset* not yet on.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: artboardSettingsStub(),
    child: const SettingsScreen(),
  );

  Future<void> typing(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset everything'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'RES');
    await tester.pumpAndSettle();
  }

  goldenTest('reset', builder: screen, act: typing);
  goldenTest(
    'reset_ios',
    builder: screen,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    act: typing,
  );
}
