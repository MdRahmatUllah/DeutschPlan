import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/quiz/quiz_setup_sheet.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L2 · Quiz tab — #116.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  group('FR-L2-04 what a tile starts', () {
    test("this step's learned words, DE → EN, at the tile's length", () {
      final args = stepQuiz('A2.1', length: 20);
      expect(args.source, 'stepLearned');
      expect(args.sourceRef, 'A2.1');
      expect(args.direction, 'deEn');
      expect(args.length, 20);
    });

    test('Forms uses direction forms', () {
      expect(
        stepQuiz('A2.1', length: 20, direction: 'forms').direction,
        'forms',
      );
    });

    test('a new seed each time, so two quizzes differ', () {
      final seeds = <int>{
        for (var i = 0; i < 20; i++) stepQuiz('A2.1', length: 10).seed,
      };
      expect(seeds.length, greaterThan(1));
    });
  });

  late QuizArgs? started;

  Future<void> pump(WidgetTester tester, {String code = 'A2.1'}) async {
    started = null;
    final routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => StepDetailScreen(code: code, tab: StepTab.quiz),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) {
            started = state.extra as QuizArgs?;
            return const Scaffold(body: Text('L8'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: todayStub(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (tile, length) in <(String Function(), int)>[
    (() => l10n.quizQuick, 10),
    (() => l10n.quizStandard, 20),
    (() => l10n.quizLong, 30),
  ]) {
    testWidgets('FR-L2-04 the $length-question tile', (tester) async {
      await pump(tester);
      await tester.tap(find.text(tile()));
      await tester.pumpAndSettle();
      expect(started!.length, length);
      expect(started!.source, 'stepLearned');
      expect(started!.sourceRef, 'A2.1');
      expect(started!.direction, 'deEn');
    });
  }

  testWidgets('FR-L2-04 Forms', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizForms));
    await tester.pumpAndSettle();
    expect(started!.direction, 'forms');
  });

  testWidgets('Custom opens the custom quiz sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizCustom));
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupSheet), findsOneWidget);
    expect(started, isNull, reason: 'nothing starts until the sheet says so');
  });

  testWidgets('under ten learned: closed, saying why', (tester) async {
    // A2.2 has not started: nothing learned.
    await pump(tester, code: 'A2.2');
    expect(find.text(l10n.quizLocked(0)), findsOneWidget);
    await tester.tap(find.text(l10n.quizStandard));
    await tester.tap(find.text(l10n.quizCustom));
    await tester.pumpAndSettle();
    expect(started, isNull);
    expect(find.byType(QuizSetupSheet), findsNothing);
  });

  testWidgets('the last quiz: 16 / 20 · Standard · DE → EN · Sun 20 Sep', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.quizLast(16, 20)), findsOneWidget);
    expect(find.text('Standard · DE → EN · Sun 20 Sep'), findsOneWidget);
  });

  group('the last quiz names what it was', () {
    Future<void> card(WidgetTester tester, int length, String direction) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: LastQuizCard(
                quiz: (
                  score: 8,
                  outOf: length,
                  length: length,
                  direction: direction,
                  finishedAt: '2026-09-20T19:05:00',
                ),
              ),
            ),
          ),
        );

    testWidgets('a Forms quiz by its direction alone', (tester) async {
      await card(tester, 20, 'forms');
      expect(find.text('Forms · Sun 20 Sep'), findsOneWidget);
    });

    testWidgets('a length no tile has is a Custom one', (tester) async {
      await card(tester, 15, 'articles');
      expect(find.text('Custom · Articles · Sun 20 Sep'), findsOneWidget);
    });

    testWidgets('Quick and Long by their length', (tester) async {
      await card(tester, 10, 'enDe');
      expect(find.text('Quick · EN → DE · Sun 20 Sep'), findsOneWidget);
      await card(tester, 30, 'deBn');
      expect(find.text('Long · DE → বাংলা · Sun 20 Sep'), findsOneWidget);
    });
  });

  group('its score, coloured as a result is', () {
    Future<Color> colour(WidgetTester tester, int score) async {
      final LastQuiz quiz = (
        score: score,
        outOf: 20,
        length: 20,
        direction: 'deEn',
        finishedAt: '2026-09-20T19:05:00',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(body: LastQuizCard(quiz: quiz)),
        ),
      );
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('$score'), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    final palette = DpPalette.light;

    testWidgets('Lime from 80 %', (tester) async {
      expect(await colour(tester, 16), palette.easy);
    });

    testWidgets('Sun from 50 %', (tester) async {
      expect(await colour(tester, 10), palette.learning);
      expect(await colour(tester, 15), palette.learning);
    });

    testWidgets('Coral under', (tester) async {
      expect(await colour(tester, 9), palette.again);
    });
  });
}
