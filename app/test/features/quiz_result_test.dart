import 'dart:async';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart' show QuizAttempt;
import 'package:deutschplan/data/repositories/exam_repository.dart'
    show QuizMistakeRowsResult;
import 'package:deutschplan/features/learn/step_quiz.dart' show quizColour;
import 'package:deutschplan/features/quiz/quiz_result_screen.dart';
import 'package:deutschplan/features/words/word_row.dart' show WordPlayButton;
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

/// L9 · Quiz result — #126.
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
    timer: true,
  );

  const compare = QuizArgs(
    direction: 'compare',
    source: 'compareSet',
    sourceRef: 'set-grund',
    seed: 7,
    length: 5,
  );

  late StubQuizRun run;
  late QuizArgs? retried;

  Future<void> pump(
    WidgetTester tester, {
    StubQuizRun? stub,
    QuizArgs args = standard,
  }) async {
    run = stub ?? StubQuizRun();
    retried = null;
    final routes = GoRouter(
      initialLocation: '/opener',
      routes: <RouteBase>[
        GoRoute(
          path: '/opener',
          builder: (_, _) => const Scaffold(body: Text('opener')),
        ),
        GoRoute(
          path: '/result',
          builder: (_, _) => QuizResultView(attemptId: 1, args: args),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) {
            retried = state.extra as QuizArgs?;
            return const Scaffold(body: Text('L8'));
          },
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
    // Completes only when the result is popped.
    unawaited(routes.push('/result'));
    await tester.pumpAndSettle();
  }

  QuizAttempt attempt({double score = 16, double outOf = 20}) => QuizAttempt(
    id: 1,
    startedAt: '2026-09-21T19:00:00.000Z',
    finishedAt: '2026-09-21T19:00:42.000Z',
    direction: 'deEn',
    source: 'stepLearned',
    seed: 7,
    length: 20,
    scorePoints: score,
    maxPoints: outOf,
  );

  testWidgets('the score, its percent, time and title', (tester) async {
    await pump(tester);
    expect(find.text('16 / 20'), findsOneWidget);
    expect(find.text('80% · 4 min 12 s · Standard · DE → EN'), findsOneWidget);
  });

  testWidgets('a quiz scores in halves, and a short one in seconds', (
    tester,
  ) async {
    await pump(
      tester,
      stub: StubQuizRun(outcome: (attempt: attempt(score: 15.5), mistakes: [])),
    );
    expect(find.text('15.5 / 20'), findsOneWidget);
    expect(find.text('77% · 0 min 42 s · Standard · DE → EN'), findsOneWidget);
  });

  test('the result colour: Lime from 80 %, Sun from 50 %, Coral under', () {
    const palette = DpPalette.light;
    expect(quizColour(palette, 0.8), palette.easy);
    expect(quizColour(palette, 0.795), palette.learning);
    expect(quizColour(palette, 0.5), palette.learning);
    expect(quizColour(palette, 0.49), palette.again);
  });

  testWidgets('the block takes the colour its score earns', (tester) async {
    await pump(
      tester,
      stub: StubQuizRun(outcome: (attempt: attempt(score: 9), mistakes: [])),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == DpPalette.light.again,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the mistakes: the word, what was written, the article flag', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.quizResultMistakes(4).toUpperCase()), findsOneWidget);
    expect(find.text(l10n.quizResultWrote('die Kausion')), findsOneWidget);
    expect(find.text(l10n.quizResultWrote('umzihen')), findsOneWidget);
    expect(
      find.text(l10n.quizResultWroteArticle('die Vermieter')),
      findsOneWidget,
    );
    expect(find.text(l10n.summaryPlay('die Kaution')), findsNothing);
    expect(find.bySemanticsLabel(l10n.summaryPlay('der Vermieter')), findsOne);
  });

  testWidgets('an answer the timer sent says so', (tester) async {
    await pump(
      tester,
      stub: StubQuizRun(
        outcome: (
          attempt: attempt(score: 0, outOf: 1),
          mistakes: <QuizMistakeRowsResult>[
            QuizMistakeRowsResult(
              ord: 1,
              uid: 'haus',
              given: '',
              verdict: 'wrong',
              expected: 'house',
              german: 'Haus',
              article: 'das',
            ),
          ],
        ),
      ),
    );
    expect(find.text(l10n.quizResultNoAnswer), findsOneWidget);
  });

  testWidgets('FR-L9-01 Retry mistakes builds a quiz from their uids', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizRetryMistakes(4)));
    await tester.pumpAndSettle();
    expect(find.text('L8'), findsOneWidget);
    final args = retried!;
    expect(
      (args.direction, args.source, args.sourceRef, args.length, args.timer),
      ('deEn', 'compareSet', 'kaution,umziehen,vermieter,nebenkosten', 4, true),
    );

    // In place of the result: back returns to whatever opened the quiz.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('opener'), findsOneWidget);
  });

  testWidgets('FR-W2-03 a compare quiz retries its set, as many items', (
    tester,
  ) async {
    await pump(tester, args: compare);
    await tester.tap(find.text(l10n.quizRetryMistakes(4)));
    await tester.pumpAndSettle();
    final args = retried!;
    expect(
      (args.direction, args.source, args.sourceRef, args.length),
      ('compare', 'compareSet', 'set-grund', 4),
    );
  });

  testWidgets('FR-W2-03 a compare mistake names the member, not the set', (
    tester,
  ) async {
    await pump(
      tester,
      args: compare,
      stub: StubQuizRun(
        outcome: (
          attempt: attempt(),
          mistakes: <QuizMistakeRowsResult>[
            // A member with no word of its own rates the set word.
            QuizMistakeRowsResult(
              ord: 1,
              uid: 'set-angst',
              given: 'Angst',
              verdict: 'wrong',
              expected: 'Furcht',
              german: 'Angst / Furcht / Sorge / Panik',
              article: null,
            ),
            QuizMistakeRowsResult(
              ord: 2,
              uid: 'uid-grund',
              given: 'Anlass',
              verdict: 'wrong',
              expected: 'Grund',
              german: 'Grund',
              article: 'der',
            ),
          ],
        ),
      ),
    );
    expect(find.text('Furcht', findRichText: true), findsOneWidget);
    expect(find.textContaining('Sorge', findRichText: true), findsNothing);
    expect(find.text('der Grund', findRichText: true), findsOneWidget);
    expect(
      tester
          .widgetList<WordPlayButton>(find.byType(WordPlayButton))
          .map((button) => button.word),
      <String>['Furcht', 'der Grund'],
    );
  });

  testWidgets('FR-L9-01 Add mistakes to revision: due tomorrow, once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizAddToRevision));
    await tester.pumpAndSettle();
    expect(run.added.single.$1, <({String uid, String? verdict})>[
      (uid: 'kaution', verdict: 'almost'),
      (uid: 'umziehen', verdict: 'almost'),
      (uid: 'vermieter', verdict: 'wrongArticle'),
      (uid: 'nebenkosten', verdict: 'almost'),
    ]);
    expect(
      run.added.single.$2,
      '2026-09-21',
      reason: 'today; tomorrow is the service',
    );
    expect(find.text(l10n.quizAddedToRevision(4)), findsOneWidget);

    await tester.tap(find.text(l10n.quizAddToRevision));
    await tester.pumpAndSettle();
    expect(run.added, hasLength(1));
    expect(
      tester
          .widget<DpButton>(
            find.widgetWithText(DpButton, l10n.quizAddToRevision),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('no mistakes: nothing to retry or add, just Done', (
    tester,
  ) async {
    await pump(
      tester,
      stub: StubQuizRun(outcome: (attempt: attempt(score: 20), mistakes: [])),
    );
    expect(find.text(l10n.quizResultNoMistakes.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
    expect(find.text(l10n.quizAddToRevision), findsNothing);

    await tester.tap(find.text(l10n.done));
    await tester.pumpAndSettle();
    expect(find.text('opener'), findsOneWidget);
  });

  testWidgets('close leaves too', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel(l10n.quizClose));
    await tester.pumpAndSettle();
    expect(find.text('opener'), findsOneWidget);
    semantics.dispose();
  });
}
