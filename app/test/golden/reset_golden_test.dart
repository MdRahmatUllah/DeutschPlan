// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/me/settings_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
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
    await tester.tap(find.text(tester.l10n.settingsReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tester.l10n.resetEverything));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'RES');
    await tester.pumpAndSettle();
  }

  // #432: with the keyboard up, at 200 % and in Bangla, the dialog scrolls
  // its message and field above the keyboard, the actions clear of them.
  Future<void> typingWithKeyboard(
    WidgetTester tester, {
    double scale = 1,
    Locale locale = const Locale('en'),
  }) async {
    final platform = tester.platformDispatcher
      ..textScaleFactorTestValue = scale
      ..localesTestValue = <Locale>[locale];
    addTearDown(platform.clearTextScaleFactorTestValue);
    addTearDown(platform.clearLocalesTestValue);
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(locale);
    await tester.scrollUntilVisible(
      find.text(l10n.settingsReset),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetEverything));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'RES');
    await tester.pumpAndSettle();
  }

  goldenTest('reset', builder: screen, act: typing);
  for (final chrome in AdaptiveChrome.values) {
    final ios = chrome == AdaptiveChrome.cupertino ? '_ios' : '';
    goldenTest(
      'reset_keyboard_200$ios',
      builder: screen,
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      chrome: chrome,
      act: (tester) => typingWithKeyboard(tester, scale: 2),
      // Its act sets its own text size and locale, overriding the
      // audit's, so it is a fixed-size golden and carries no audit;
      // `reset` and `reset_ios` do, in both languages (#581).
      textAudit: false,
    );
    goldenTest(
      'reset_keyboard_bn$ios',
      builder: screen,
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      chrome: chrome,
      act: (tester) => typingWithKeyboard(tester, locale: const Locale('bn')),
      // Its act sets its own text size and locale, overriding the
      // audit's, so it is a fixed-size golden and carries no audit;
      // `reset` and `reset_ios` do, in both languages (#581).
      textAudit: false,
    );
  }
  goldenTest(
    'reset_ios',
    builder: screen,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    act: typing,
  );
}
