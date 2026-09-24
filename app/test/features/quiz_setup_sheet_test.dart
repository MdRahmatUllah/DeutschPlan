import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/features/quiz/quiz_setup_sheet.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L7 · Custom quiz — #122 (`quiz.md`, FR-L2-04's *Custom* tile).
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late QuizArgs? started;

  Future<void> pump(WidgetTester tester) async {
    started = null;
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const StepDetailScreen(code: 'A2.1', tab: StepTab.quiz),
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
        key: UniqueKey(),
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
    await tester.tap(find.text(l10n.quizCustom));
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.widgetWithText(DpChip, label);

  bool selected(WidgetTester tester, String label) =>
      tester.widget<DpChip>(chip(label)).selected;

  testWidgets('FR-L2-04 Custom opens L7 with its title and sections', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(QuizSetupSheet), findsOneWidget);
    expect(find.text(l10n.quizSetupTitle), findsOneWidget);
    for (final label in <String>[
      l10n.quizSetupDirection,
      l10n.quizSetupLength,
      l10n.quizSetupSource,
    ]) {
      expect(find.text(label.toUpperCase()), findsOneWidget);
    }
  });

  testWidgets('all six directions are offered, DE → EN first and chosen', (
    tester,
  ) async {
    await pump(tester);
    final labels = <String>[
      'DE → EN',
      'DE → বাংলা',
      'EN → DE',
      l10n.quizDirectionArticles,
      l10n.quizDirectionListening,
      l10n.quizDirectionMixed,
    ];
    for (final label in labels) {
      expect(chip(label), findsOneWidget, reason: label);
    }
    expect(
      find.text(l10n.quizForms),
      findsOneWidget,
      reason: 'the L2 tile only',
    );
    expect(selected(tester, 'DE → EN'), isTrue);
    expect(
      tester.getTopLeft(chip('DE → EN')).dx,
      lessThan(tester.getTopLeft(chip('EN → DE')).dx),
    );
  });

  testWidgets('BR-QUIZ-01 lengths 10 / 20 / 30, 20 chosen; sources this step, '
      'all learned and the step\'s main category', (tester) async {
    await pump(tester);
    for (final length in <String>['10', '20', '30']) {
      expect(chip(length), findsOneWidget);
    }
    expect(selected(tester, '20'), isTrue);
    expect(chip(l10n.quizSourceStep), findsOneWidget);
    expect(chip(l10n.quizSourceAll), findsOneWidget);
    expect(chip('Wohnen & Haushalt'), findsOneWidget);
    expect(selected(tester, l10n.quizSourceStep), isTrue);
  });

  testWidgets('a step with no category offers two sources', (tester) async {
    // The sheet alone, over a step whose words have no category.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          stepCategoriesProvider.overrideWith(
            (ref, code) async => const <({int id, String name})>[],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const Scaffold(body: QuizSetupSheet(step: 'A2.1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DpChip), findsNWidgets(6 + 3 + 2));
    expect(chip(l10n.quizSourceAll), findsOneWidget);
    expect(chip('Wohnen & Haushalt'), findsNothing);
  });

  testWidgets('FR-L8-05 the timer says what it does, off and on', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.quizSetupTimerOff), findsOneWidget);
    expect(
      tester.widget<AdaptiveSwitch>(find.byType(AdaptiveSwitch)).semanticLabel,
      l10n.quizSetupTimer,
    );
    await tester.tap(find.byType(AdaptiveSwitch));
    await tester.pumpAndSettle();
    expect(find.text(l10n.quizSetupTimerOn), findsOneWidget);
  });

  testWidgets('choices are single-select and the button counts the length', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.quizStart(l10n.quizQuestions(20))), findsOneWidget);
    await tester.tap(chip('30'));
    await tester.tap(chip(l10n.quizDirectionMixed));
    await tester.pumpAndSettle();
    expect(selected(tester, '30'), isTrue);
    expect(selected(tester, '20'), isFalse);
    expect(selected(tester, l10n.quizDirectionMixed), isTrue);
    expect(selected(tester, 'DE → EN'), isFalse);
    expect(find.text(l10n.quizStart(l10n.quizQuestions(30))), findsOneWidget);
  });

  testWidgets('Start closes the sheet and starts the quiz it built', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(chip('EN → DE'));
    await tester.tap(chip('10'));
    await tester.tap(chip('Wohnen & Haushalt'));
    await tester.tap(find.byType(AdaptiveSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.quizStart(l10n.quizQuestions(10))));
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupSheet), findsNothing);
    expect(started, isNotNull);
    expect(
      (
        started!.direction,
        started!.length,
        started!.source,
        started!.sourceRef,
        started!.timer,
      ),
      ('enDe', 10, 'category', '1', true),
    );
  });

  testWidgets('dismissing the sheet starts nothing', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(195, 60)); // the scrim above the sheet
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupSheet), findsNothing);
    expect(started, isNull);
  });

  test('builds valid QuizArgs for every combination', () {
    for (final direction in customDirections) {
      for (final length in quizLengths) {
        for (final source in <QuizSource>[
          QuizSource.stepLearned,
          QuizSource.allLearned,
          QuizSource.category,
        ]) {
          for (final timer in <bool>[false, true]) {
            final args = customQuiz(
              direction: direction,
              length: length,
              source: source,
              step: 'A2.1',
              category: 7,
              timer: timer,
            );
            final label = '$direction $length $source $timer';
            expect(
              QuizDirection.parse(args.direction),
              direction,
              reason: label,
            );
            expect(QuizSource.parse(args.source), source, reason: label);
            expect(args.sourceRef, switch (source) {
              QuizSource.stepLearned => 'A2.1',
              QuizSource.category => '7',
              _ => null,
            }, reason: label);
            expect((args.length, args.timer), (length, timer), reason: label);
            expect(
              args.seed,
              inInclusiveRange(0, (1 << 31) - 1),
              reason: label,
            );
          }
        }
      }
    }
    expect(customDirections, isNot(contains(QuizDirection.forms)));
  });

  test('a seed can be given, so a quiz can be rebuilt', () {
    final a = customQuiz(
      direction: QuizDirection.deEn,
      length: 10,
      source: QuizSource.allLearned,
      step: 'A1.1',
      timer: false,
      seed: 42,
    );
    expect(a.seed, 42);
  });
}
