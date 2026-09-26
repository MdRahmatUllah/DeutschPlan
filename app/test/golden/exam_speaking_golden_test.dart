// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import '../features/exam_run_fixtures.dart';
import 'golden_harness.dart';

/// L12 · Speaking — #134. The ExamSpeaking artboard: A1, a minute, 52 s
/// recorded, three of the four ticked.
void main() {
  Widget runner(BuildContext context) => ProviderScope(
    overrides: <Override>[
      ...examRunStub(
        StubExamRun(
          items: const <ExamItem>[artboardSpeaking],
          given: const <int, String>{1: '/recordings/7.m4a'},
          ticks: const <int, List<bool>>{
            1: <bool>[true, true, false, true],
          },
        ),
      ),
      examRecorderProvider.overrideWithValue(
        FakeRecorder(recorded: const Duration(seconds: 52)),
      ),
    ],
    child: ExamRunnerScreen(
      attemptId: 7,
      results: (_) => const SizedBox.shrink(),
      onLeft: (_) {},
    ),
  );

  goldenTest('exam_speaking', builder: runner);
  goldenTest(
    'exam_speaking_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: runner,
    noBanglaAudit:
        'the timer row overflows 5.9 dp at 200 %; iOS is Later, #588',
  );
}
