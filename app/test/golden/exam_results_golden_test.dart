// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/exam/exam_results_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/exam_result_fixtures.dart';
import 'golden_harness.dart';

/// L13 · Exam results — #135. The ExamResults artboard: A1.2 · Mock 2,
/// 37 of 48, passed, 18:41, against attempt 1; and a paper that did not
/// pass, which no artboard draws.
void main() {
  Widget results(StubExamResult stub) => ProviderScope(
    overrides: examResultStub(stub),
    child: ExamResultsScreen(attemptId: 7, onHub: (_) {}, onStep: (_) {}),
  );

  goldenTest('exam_results', builder: (context) => results(StubExamResult()));

  goldenTest(
    'exam_results_fail',
    builder: (context) => results(StubExamResult(result: failedResult())),
  );

  goldenTest(
    'exam_results_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => results(StubExamResult()),
  );
}
