// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/learn/exam_intro_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/exam_fixtures.dart';
import 'golden_harness.dart';

/// L11 · Exam intro — #129. The artboard's Mock 2 of A1.2: 62 % in one
/// attempt, pass mark 60 %, the timer on.
void main() {
  goldenTest(
    'exam_intro',
    builder: (context) => ProviderScope(
      overrides: examStub(),
      child: const ExamIntroScreen(step: 'A1.2', seed: 2),
    ),
  );

  // ExamIntro-ios: "‹ A1.2" and "Mock 2" in the bar, the iOS switch.
  goldenTest(
    'exam_intro_ios',
    modes: <GoldenMode>[GoldenMode.light],
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: examStub(),
      child: const ExamIntroScreen(step: 'A1.2', seed: 2),
    ),
  );
}
