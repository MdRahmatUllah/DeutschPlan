// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/quiz/quiz_screen.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/quiz_fixtures.dart';
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
      await tester.tap(find.text(tester.l10n.quizCheck));
      await tester.pumpAndSettle();
    }

    for (var i = 1; i < 7; i++) {
      await check('x');
      await tester.tap(find.text(tester.l10n.practiceNext));
      await tester.pumpAndSettle();
    }
    await check('der Mietvertag');
  }

  goldenTest('quiz_runner', builder: screen, act: toTheSeventh);

  // #124: each item type, first in its own quiz.
  Widget only(QuizItem item, [List<QuizItem> more = const <QuizItem>[]]) =>
      ProviderScope(
        overrides: <Override>[
          todayProvider.overrideWithValue('2026-09-21'),
          ...quizStub(
            StubQuizRun(
              quiz: Quiz(
                direction: QuizDirection.mixed,
                source: QuizSource.stepLearned,
                seed: 7,
                items: <QuizItem>[item, ...more],
              ),
            ),
          ),
        ],
        child: const QuizScreen(
          args: QuizArgs(
            direction: 'mixed',
            source: 'stepLearned',
            sourceRef: 'A2.1',
            seed: 7,
          ),
        ),
      );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.text(tester.l10n.quizCheck));
    await tester.pumpAndSettle();
  }

  for (final (name, item, act)
      in <(String, QuizItem, Future<void> Function(WidgetTester)?)>[
        (
          'meaning',
          const QuizItem(
            ord: 1,
            wordUid: 'kaution',
            direction: QuizDirection.deEn,
            prompt: 'die Kaution',
            expected: 'deposit',
          ),
          null,
        ),
        (
          'tiles',
          const QuizItem(
            ord: 1,
            wordUid: 'kaution',
            direction: QuizDirection.deBn,
            prompt: 'die Kaution',
            expected: 'জামানত',
            options: <String>['ভাড়া', 'জামানত', 'চুক্তি', 'বাড়িওয়ালা'],
          ),
          (tester) async {
            await tester.tap(find.text('ভাড়া'));
            await tester.pumpAndSettle();
          },
        ),
        (
          'articles',
          const QuizItem(
            ord: 1,
            wordUid: 'vermieter',
            direction: QuizDirection.articles,
            prompt: 'Vermieter',
            expected: 'der',
          ),
          null,
        ),
        (
          'wrong_article',
          const QuizItem(
            ord: 1,
            wordUid: 'vermieter',
            direction: QuizDirection.enDe,
            prompt: 'landlord',
            expected: 'der Vermieter',
            hint: 'বাড়িওয়ালা',
          ),
          (tester) => type(tester, 'die Vermieter'),
        ),
        (
          'listening',
          const QuizItem(
            ord: 1,
            wordUid: 'kaution',
            direction: QuizDirection.listening,
            prompt: 'die Kaution',
            expected: 'die Kaution',
          ),
          null,
        ),
        (
          'forms',
          const QuizItem(
            ord: 1,
            wordUid: 'umziehen',
            direction: QuizDirection.forms,
            prompt: 'umziehen',
            expected: 'ist umgezogen',
            form: FormLabel.perfekt,
          ),
          (tester) => type(tester, 'ist umgezogen'),
        ),
      ]) {
    goldenTest(
      'quiz_runner_$name',
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      builder: (context) => only(item),
      act: act,
    );
  }

  // #125: a mistake, asked once more at the end.
  goldenTest(
    'quiz_runner_reask',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) => only(
      const QuizItem(
        ord: 1,
        wordUid: 'kaution',
        direction: QuizDirection.deEn,
        prompt: 'die Kaution',
        expected: 'deposit',
      ),
      const <QuizItem>[
        QuizItem(
          ord: 2,
          wordUid: 'miete',
          direction: QuizDirection.deEn,
          prompt: 'die Miete',
          expected: 'rent',
        ),
      ],
    ),
    act: (tester) async {
      await type(tester, 'rent');
      await tester.tap(find.text(tester.l10n.practiceNext));
      await tester.pumpAndSettle();
      await type(tester, 'rent');
      await tester.tap(find.text(tester.l10n.practiceNext));
      await tester.pumpAndSettle();
    },
  );

  goldenTest(
    'quiz_runner_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
    act: toTheSeventh,
  );

  // #568: typing German at 200 % with the keyboard up, the header and strip
  // give way and Check is a key on the umlaut row, in every theme.
  goldenTest(
    'quiz_runner_keyboard_200',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textScale: 2,
    textAudit: false,
    builder: (context) => only(
      const QuizItem(
        ord: 1,
        wordUid: 'umziehen',
        direction: QuizDirection.forms,
        prompt: 'umziehen',
        expected: 'ist umgezogen',
        form: FormLabel.perfekt,
      ),
    ),
    act: (tester) async {
      await tester.showKeyboard(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'ist um');
      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
    },
  );
}
