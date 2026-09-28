// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show find;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/features/exam/exam_runner_screen.dart';

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
  // #691 EX-6: the retake used and the recording deleted: Record is off,
  // dimmed, and the line says why.
  goldenTest(
    'exam_speaking_spent',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    builder: runner,
    act: (tester) async {
      await tester.tap(find.text(tester.l10n.examSpeakingRetake(1)));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tester.l10n.examSpeakingDelete));
      await tester.pumpAndSettle();
    },
  );
  goldenTest(
    'exam_speaking_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: runner,
  );
}
