import 'package:deutschplan/features/onboarding/onboarding_welcome_page.dart';

import 'golden_harness.dart';

/// S2 page 1 · Welcome goldens — #87.
void main() {
  goldenTest(
    'onboarding_welcome',
    builder: (context) => OnboardingWelcomePage(onStart: () {}),
  );
}
