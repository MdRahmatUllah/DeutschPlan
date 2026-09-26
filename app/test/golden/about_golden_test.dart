// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/me/about_screen.dart';
import 'package:deutschplan/features/me/licences_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/about_fixtures.dart';
import 'golden_harness.dart';

/// M9 · About & privacy and M8 · Licences — #150, as the About and Licences
/// artboards draw them.
void main() {
  Widget about(BuildContext context) =>
      ProviderScope(overrides: aboutStub(), child: const AboutScreen());
  Widget licences(BuildContext context) =>
      ProviderScope(overrides: aboutStub(), child: const LicencesScreen());

  goldenTest('about', builder: about);
  goldenTest(
    'about_ios',
    builder: about,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
  );
  goldenTest('licences', builder: licences);
  goldenTest(
    'licences_ios',
    builder: licences,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    noBanglaAudit:
        "iOS's back label overflows 16 dp at 200 %; iOS is Later, #588",
  );
}
