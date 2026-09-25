// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/onboarding/onboarding_voice_page.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'golden_harness.dart';

/// S2 page 5 · Reminder and voice goldens — #91, and the voice's states
/// (#428).
///
/// The defaults as drawn: the reminder off at 19:30, the offer of Supertonic
/// open. The size is the manifest's, which rounds to the artboard's 100.
void main() {
  void page(
    String name,
    SupertonicOnPhone onPhone, {
    List<GoldenDevice> devices = GoldenDevice.values,
  }) => goldenTest(
    name,
    devices: devices,
    builder: (context) => ProviderScope(
      overrides: <Override>[
        supertonicMegabytesProvider.overrideWith((ref) async => 100),
        supertonicOnPhoneProvider.overrideWith((ref) => Stream.value(onPhone)),
      ],
      child: OnboardingVoicePage(onFinish: () {}, onBack: () {}),
    ),
  );

  page('onboarding_voice', (phase: null, progress: 0, shortfall: 0));

  // #428: the card's other looks, on the phone.
  const phone = <GoldenDevice>[GoldenDevice.phone];
  page('onboarding_voice_short', (
    phase: null,
    progress: 0,
    shortfall: 170700000,
  ), devices: phone);
  page('onboarding_voice_waiting', (
    phase: DownloadPhase.waitingForWifi,
    progress: 0,
    shortfall: 0,
  ), devices: phone);
  page('onboarding_voice_failed', (
    phase: DownloadPhase.failed,
    progress: 0.6,
    shortfall: 0,
  ), devices: phone);
  page('onboarding_voice_ready', (
    phase: DownloadPhase.ready,
    progress: 1,
    shortfall: 0,
  ), devices: phone);
}
