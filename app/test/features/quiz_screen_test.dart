import 'dart:async';

import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/quiz/quiz_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'quiz_fixtures.dart';

/// L8 · Quiz runner — #123.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const standard = QuizArgs(
    direction: 'deEn',
    source: 'stepLearned',
    sourceRef: 'A2.1',
    seed: 7,
    length: 20,
  );

  Quiz quizOf(List<QuizItem> items) => Quiz(
    direction: QuizDirection.deEn,
    source: QuizSource.allLearned,
    seed: 1,
    items: items,
  );

  const haus = QuizItem(
    ord: 1,
    wordUid: 'haus',
    direction: QuizDirection.deEn,
    prompt: 'das Haus',
    expected: 'house',
  );
  const vertrag = QuizItem(
    ord: 2,
    wordUid: 'vertrag',
    direction: QuizDirection.enDe,
    prompt: 'rental contract, lease',
    expected: 'der Mietvertrag',
  );

  late StubQuizRun run;

  Future<void> pump(
    WidgetTester tester, {
    QuizArgs args = standard,
    StubQuizRun? stub,
  }) async {
    run = stub ?? StubQuizRun();
    final routes = GoRouter(
      initialLocation: '/opener',
      routes: <RouteBase>[
        GoRoute(
          path: '/opener',
          builder: (_, _) => const Scaffold(body: Text('opener')),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) => QuizScreen(args: state.extra! as QuizArgs),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          todayProvider.overrideWithValue('2026-09-21'),
          ...quizStub(run),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    unawaited(routes.push('/quiz', extra: args));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.text(l10n.quizCheck));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text(l10n.practiceNext));
    await tester.pumpAndSettle();
  }

  Finder close() => find.bySemanticsLabel(l10n.quizClose);

  testWidgets('FR-L8-01 the quiz is built from its args, seed and all', (
    tester,
  ) async {
    await pump(tester);
    expect(run.started, [
      (QuizDirection.deEn, QuizSource.stepLearned, 'A2.1', 20, 7),
    ]);
  });

  testWidgets('the top bar: the title, the counter; the item and its ask', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Standard · DE → EN'), findsOneWidget);
    expect(find.text('1 / 20'), findsOneWidget);
    expect(find.text(l10n.quizAskMeaning), findsOneWidget);
    expect(find.text('das Wort1'), findsOneWidget);
  });

  testWidgets('Check waits for an answer', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizCheck));
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(run.answers, isEmpty);
    expect(find.text(l10n.quizCorrect), findsNothing);
  });

  testWidgets('FR-L8-02 answers are graded and persisted per item', (
    tester,
  ) async {
    await pump(tester);
    await answer(tester, 'word 1');
    expect(find.text(l10n.quizCorrect), findsOneWidget);
    expect(run.answers, [(1, 'word 1', Verdict.correct)]);

    await next(tester);
    expect(find.text('2 / 20'), findsOneWidget);
    expect(find.text('das Wort2'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'each item starts with an empty field',
    );

    // The keyboard's done key checks too.
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(l10n.quizAnswerIs('word 2')), findsOneWidget);
    expect(run.answers.last, (2, 'nope', Verdict.wrong));
  });

  testWidgets('almost: "watch the spelling" with the answer', (tester) async {
    await pump(tester, stub: StubQuizRun(quiz: artboardQuiz()));
    for (var i = 1; i < 7; i++) {
      await answer(tester, 'x');
      await next(tester);
    }
    expect(find.text('7 / 20'), findsOneWidget);
    expect(find.text(l10n.quizAskGerman), findsOneWidget);
    await answer(tester, 'der Mietvertag');
    expect(find.text(l10n.quizAlmost('der Mietvertrag')), findsOneWidget);
    expect(run.answers.last, (7, 'der Mietvertag', Verdict.almost));
  });

  testWidgets('the last answer finishes the run, scored, and closes it', (
    tester,
  ) async {
    await pump(
      tester,
      stub: StubQuizRun(quiz: quizOf(<QuizItem>[haus, vertrag])),
    );
    await answer(tester, 'house');
    await next(tester);
    await answer(tester, 'der Mietvertag');
    expect(run.finished, isNull);
    await next(tester);
    expect(run.finished, 1.5, reason: 'correct 1 + almost 0.5');
    expect(find.text('opener'), findsOneWidget);
  });

  group('FR-L8-04 closing asks first', () {
    testWidgets('Keep going stays; Stop leaves', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await answer(tester, 'word 1');

      await tester.tap(close());
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsOneWidget);
      expect(find.text(l10n.quizStopBody), findsOneWidget);
      await tester.tap(find.text(l10n.quizKeepGoing));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);

      await tester.tap(close());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.quizStop));
      await tester.pumpAndSettle();
      expect(find.text('opener'), findsOneWidget);
      expect(run.answers, hasLength(1), reason: 'what was answered stays');
      expect(run.finished, isNull);
      semantics.dispose();
    });

    testWidgets('back asks as close does', (tester) async {
      await pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsOneWidget);
      expect(find.byType(QuizScreen), findsOneWidget);
    });

    testWidgets('an empty quiz says so and closes without asking', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, stub: StubQuizRun(quiz: quizOf(const <QuizItem>[])));
      expect(find.text(l10n.quizEmpty), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      await tester.tap(close());
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsNothing);
      expect(find.text('opener'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('FR-L8-05 the timer', () {
    const timed = QuizArgs(
      direction: 'deEn',
      source: 'stepLearned',
      sourceRef: 'A2.1',
      seed: 7,
      length: 20,
      timer: true,
    );

    testWidgets('auto-submits an empty answer as wrong at 0', (tester) async {
      await pump(tester, args: timed);
      expect(find.text(l10n.quizSecondsLeft(15)), findsOneWidget);
      await tester.pump(const Duration(seconds: 14));
      expect(find.text(l10n.quizSecondsLeft(1)), findsOneWidget);
      expect(run.answers, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, '', Verdict.wrong)]);
      expect(find.text(l10n.quizTimeUp('word 1')), findsOneWidget);
      expect(find.text(l10n.quizSecondsLeft(0)), findsNothing);

      await next(tester);
      expect(
        find.text(l10n.quizSecondsLeft(15)),
        findsOneWidget,
        reason: 'each question has its own 15 s',
      );
    });

    testWidgets(
      'FR-L8-04 the clock stops under the Stop dialog, and Keep going '
      'carries on from the seconds left',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, args: timed);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text(l10n.quizSecondsLeft(10)), findsOneWidget);

        await tester.tap(close());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 20));
        expect(run.answers, isEmpty, reason: 'no time runs out under it');

        await tester.tap(find.text(l10n.quizKeepGoing));
        await tester.pumpAndSettle();
        expect(find.text(l10n.quizSecondsLeft(10)), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(run.answers, [(1, '', Verdict.wrong)]);
        semantics.dispose();
      },
    );

    testWidgets('an answer in time stops the clock', (tester) async {
      await pump(tester, args: timed);
      await tester.pump(const Duration(seconds: 5));
      await answer(tester, 'word 1');
      await tester.pump(const Duration(seconds: 20));
      expect(run.answers, [(1, 'word 1', Verdict.correct)]);
    });

    testWidgets('off: no clock, and nothing is sent for you', (tester) async {
      await pump(tester);
      expect(find.text(l10n.quizSecondsLeft(15)), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(run.answers, isEmpty);
    });
  });

  testWidgets('a quiz that could not be built offers a retry', (tester) async {
    await pump(tester, stub: StubQuizRun(error: StateError('no db')));
    expect(find.text(l10n.quizLoadFailed), findsOneWidget);
    run.error = null;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('das Wort1'), findsOneWidget);
    expect(run.started, hasLength(2));
  });

  testWidgets('a forms item names its form; listening plays, not shows', (
    tester,
  ) async {
    await pump(
      tester,
      args: const QuizArgs(direction: 'mixed', source: 'allLearned', seed: 1),
      stub: StubQuizRun(
        quiz: quizOf(<QuizItem>[
          const QuizItem(
            ord: 1,
            wordUid: 'arbeiten',
            direction: QuizDirection.forms,
            prompt: 'arbeiten',
            expected: 'hat gearbeitet',
            form: FormLabel.perfekt,
          ),
          const QuizItem(
            ord: 2,
            wordUid: 'haus',
            direction: QuizDirection.listening,
            prompt: 'das Haus',
            expected: 'das Haus',
          ),
        ]),
      ),
    );
    expect(find.text(l10n.quizFormPerfekt('arbeiten')), findsOneWidget);
    expect(find.text(l10n.quizAskForm), findsOneWidget);
    await answer(tester, 'hat gearbeitet');
    expect(find.text(l10n.quizCorrect), findsOneWidget);

    await next(tester);
    expect(find.text(l10n.quizAskListening), findsOneWidget);
    expect(find.byType(DpSpeakerButton), findsOneWidget);
    expect(find.text('das Haus'), findsNothing);
  });

  test('the title: the length names the kind; Forms is Forms', () {
    QuizArgs args(String direction, int length) =>
        QuizArgs(direction: direction, source: 'x', seed: 0, length: length);
    expect(quizTitle(l10n, args('deEn', 20)), 'Standard · DE → EN');
    expect(quizTitle(l10n, args('deBn', 10)), 'Quick · DE → বাংলা');
    expect(quizTitle(l10n, args('enDe', 30)), 'Long · EN → DE');
    expect(quizTitle(l10n, args('mixed', 15)), 'Custom · Mixed');
    expect(quizTitle(l10n, args('forms', 20)), l10n.quizForms);
  });
}
