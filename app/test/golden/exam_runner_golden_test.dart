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

/// L12 · Exam runner — #130. The ExamRunner artboard: A1.2 · Mock 2,
/// question 21 of 40, the third of six Articles, "Wohnung" with *die*
/// tapped, 14:32 left.
void main() {
  Widget runner(StubExamRun run) => ProviderScope(
    overrides: examRunStub(run),
    child: ExamRunnerScreen(
      attemptId: 7,
      results: (_) => const SizedBox.shrink(),
    ),
  );

  Future<void> pickDie(WidgetTester tester) async {
    await tester.tap(find.text('die'));
    await tester.pumpAndSettle();
  }

  goldenTest(
    'exam_runner',
    builder: (context) => runner(StubExamRun()),
    act: pickDie,
  );

  goldenTest(
    'exam_runner_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => runner(StubExamRun()),
    act: pickDie,
  );

  // Each kind of question, first and unanswered: the paper's own items.
  final paper = artboardPaper();
  for (final (name, index) in <(String, int)>[
    ('vocabulary', 0),
    ('reverse', 10),
    ('word_forms', 24),
    ('gap_fill', 28),
    ('grammar_gap', 34),
    ('grammar_pick', 35),
    ('grammar_spot', 36),
    ('grammar_recall', 37),
    ('listening', 38),
    ('writing', 40),
  ]) {
    goldenTest(
      'exam_runner_$name',
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      builder: (context) => runner(
        StubExamRun(items: <ExamItem>[paper[index]], given: <int, String>{}),
      ),
    );
  }

  goldenTest(
    'exam_runner_paused',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) => runner(StubExamRun()),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
    },
  );
}
