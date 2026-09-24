// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/exam_run_fixtures.dart';
import 'golden_harness.dart';

/// L12 · Writing — #133. The ExamWriting artboard: A1, the ten words, the
/// letter to the landlord typed, seven of them used.
void main() {
  Widget runner(BuildContext context) => ProviderScope(
    overrides: examRunStub(
      StubExamRun(
        // Speaking after it, so the button is the artboard's *Submit text*.
        items: const <ExamItem>[
          artboardWriting,
          SpeakingTask(
            'speaking:1',
            level: 'A1',
            category: 'Wohnen',
            seconds: 60,
          ),
        ],
        given: const <int, String>{},
      ),
    ),
    child: ExamRunnerScreen(
      attemptId: 7,
      results: (_) => const SizedBox.shrink(),
      onLeft: (_) {},
    ),
  );

  Future<void> typed(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), artboardWritingText);
    await tester.pumpAndSettle();
  }

  goldenTest('exam_writing', builder: runner, act: typed);
  goldenTest(
    'exam_writing_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: runner,
    act: typed,
  );
}
