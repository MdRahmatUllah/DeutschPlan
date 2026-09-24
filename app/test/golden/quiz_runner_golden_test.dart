// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/quiz/quiz_screen.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L8 · Quiz runner — #123. The QuizRunner artboard: Standard · DE → EN,
/// the seventh of twenty, "rental contract, lease" answered der Mietvertag,
/// almost.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: todayStub(),
    child: const QuizScreen(
      args: QuizArgs(
        direction: 'deEn',
        source: 'stepLearned',
        sourceRef: 'A2.1',
        seed: 7,
        length: 20,
      ),
    ),
  );

  Future<void> toTheSeventh(WidgetTester tester) async {
    Future<void> check(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
    }

    for (var i = 1; i < 7; i++) {
      await check('x');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await check('der Mietvertag');
  }

  goldenTest('quiz_runner', builder: screen, act: toTheSeventh);

  goldenTest(
    'quiz_runner_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
    act: toTheSeventh,
  );
}
