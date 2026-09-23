// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/onboarding/onboarding_voice_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'golden_harness.dart';

/// S2 page 5 · Reminder and voice goldens — #91.
///
/// The defaults as drawn: the reminder off at 19:30, the offer of Supertonic
/// open. The size is the manifest's, which rounds to the artboard's 100.
void main() {
  goldenTest(
    'onboarding_voice',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        supertonicMegabytesProvider.overrideWith((ref) async => 100),
      ],
      child: OnboardingVoicePage(onFinish: () {}, onBack: () {}),
    ),
  );
}
