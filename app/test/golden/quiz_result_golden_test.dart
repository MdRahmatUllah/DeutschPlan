// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/quiz/quiz_result_screen.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L9 · Quiz result — #126. The QuizResult artboard: 16 / 20 in 4 min 12 s,
/// Standard · DE → EN, four mistakes, one of them the article.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: todayStub(),
    child: const QuizResultView(
      attemptId: 1,
      args: QuizArgs(
        direction: 'deEn',
        source: 'stepLearned',
        sourceRef: 'A2.1',
        seed: 7,
        length: 20,
      ),
    ),
  );

  goldenTest('quiz_result', builder: screen);

  goldenTest(
    'quiz_result_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
  );
}
