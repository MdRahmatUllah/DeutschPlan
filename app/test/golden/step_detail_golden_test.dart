// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L2 · Step detail — #113. The header and the inner tabs; each tab's
/// contents arrive with #114, #115, #116 and M4.
void main() {
  // The StepDetail artboard: A2.1, started 19 Aug, 184 · 60 · 296.
  goldenTest(
    'step_detail',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1'),
    ),
  );

  // The ExamHub artboard's header: A1.2, completed 18 Aug, Mock 1 passed,
  // opened on the Exams tab.
  goldenTest(
    'step_detail_completed',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A1.2', tab: StepTab.exams),
    ),
  );

  // iOS draws the tabs as a segmented control and centres the code in the
  // bar, with a labelled back chevron.
  goldenTest(
    'step_detail_ios',
    modes: const <GoldenMode>[GoldenMode.light, GoldenMode.dark],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1'),
    ),
  );
}
