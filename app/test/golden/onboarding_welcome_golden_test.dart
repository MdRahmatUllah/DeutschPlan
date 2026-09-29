import 'dart:ui' show Locale;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/onboarding/onboarding_welcome_page.dart';

import 'golden_harness.dart';

/// S2 page 1 · Welcome goldens — #87, with the app language (#1078).
void main() {
  goldenTest(
    'onboarding_welcome',
    overrides: <Override>[languagesProvider.overrideWith(_English.new)],
    builder: (context) =>
        OnboardingWelcomePage(onStart: () {}, onRestored: () {}),
  );
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'onboarding_welcome_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    overrides: <Override>[languagesProvider.overrideWith(_English.new)],
    builder: (context) =>
        OnboardingWelcomePage(onStart: () {}, onRestored: () {}),
  );
}

class _English extends Languages {
  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() =>
      (meaning: MeaningLanguage.both, ui: UiLanguage.english);
}
