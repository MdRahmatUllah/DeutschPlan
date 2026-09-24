import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/features/learn/exam_intro_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_fixtures.dart';

/// L11 · Exam intro — #129.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Where L11 went.
  late String? went;

  setUp(() {
    StubExamStart.begun.clear();
    StubExamStart.fail = false;
  });

  /// At the phone size, or [wide] for tests that read the section names:
  /// the test font draws every glyph 1 em wide, and a phone's half-width
  /// cell would ellipsize "Vocabulary".
  Future<void> pump(
    WidgetTester tester, [
    ExamIntro? intro,
    bool wide = false,
    AdaptiveChrome chrome = AdaptiveChrome.material,
  ]) async {
    went = null;
    tester.view
      ..physicalSize = (wide ? const Size(1024, 768) : const Size(390, 844)) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: examStub(intro: intro),
        child: MaterialApp.router(
          builder: (context, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/intro',
            routes: <RouteBase>[
              GoRoute(
                path: '/intro',
                builder: (_, _) => const ExamIntroScreen(step: 'A1.2', seed: 2),
              ),
              GoRoute(
                path: '/exam/:attemptId',
                builder: (_, state) {
                  went = state.uri.toString();
                  return const Scaffold(body: Text('away'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.ensureVisible(find.text(l10n.examIntroBegin));
    await tester.tap(find.text(l10n.examIntroBegin));
    await tester.pumpAndSettle();
  }

  testWidgets('FR-L10-02 the mock, its size, the pass mark and the best so '
      'far', (tester) async {
    await pump(tester);

    expect(find.text('A1.2 · Mock 2'), findsWidgets);
    expect(
      find.text(
        '40 questions · ≈ 20 min · pass mark 60% · your best: 62% (1 attempt)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('FR-L10-02 never finished: no best', (tester) async {
    await pump(
      tester,
      artboardExamIntro(
        best: const SeedSummary(
          seed: 2,
          attempts: 1,
          finished: 0,
          bestPercent: 0,
          everPassed: false,
        ),
      ),
    );

    expect(
      find.text('${l10n.examHubLine(40, 20)} · ${l10n.examIntroPassMark(60)}'),
      findsOneWidget,
    );
  });

  testWidgets('BR-EXAM-04 the best rounds down: a fail never reads as the '
      'mark', (tester) async {
    await pump(
      tester,
      artboardExamIntro(
        passPercent: 70,
        best: const SeedSummary(
          seed: 2,
          attempts: 1,
          finished: 1,
          bestPercent: 33.5 * 100 / 48,
          everPassed: false,
        ),
      ),
    );

    expect(find.textContaining(l10n.examIntroBest(69, 1)), findsOneWidget);
  });

  group('BR-EXAM-03 the sections, in order', () {
    List<String> names(WidgetTester tester) => <String>[
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if (<String>[
          'Vocabulary', 'Reverse', 'Articles', 'Word forms', 'Gap fill', //
          'Grammar', 'Listening', 'Writing', 'Speaking',
        ].contains(text.data))
          text.data!,
    ];

    testWidgets('with their counts, Writing and Speaking self-assessed', (
      tester,
    ) async {
      await pump(tester, null, true);

      expect(names(tester), <String>[
        'Vocabulary', 'Reverse', 'Articles', 'Word forms', 'Gap fill', //
        'Grammar', 'Listening', 'Writing', 'Speaking',
      ]);
      expect(find.text(l10n.examIntroSelfAssessed), findsNWidgets(2));
      expect(find.text('10'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('FR-L10-04 without listening, its points moved', (
      tester,
    ) async {
      await pump(tester, artboardExamIntro(listening: false), true);

      expect(names(tester), isNot(contains('Listening')));
      expect(find.text('11'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
    });
  });

  testWidgets('iOS: "Mock 2" in the bar, beside the step to go back to', (
    tester,
  ) async {
    await pump(tester, null, false, AdaptiveChrome.cupertino);

    expect(find.text(l10n.examHubMock(2)), findsOneWidget);
    expect(find.text('A1.2 · Mock 2'), findsOneWidget);
    expect(find.textContaining('A1.2'), findsWidgets);
  });

  testWidgets('BR-EXAM-05 the rules', (tester) async {
    await pump(tester);

    for (final rule in <String>[
      l10n.examIntroRuleFeedback,
      l10n.examIntroRuleFlag,
      l10n.examIntroRulePause,
    ]) {
      expect(find.text(rule), findsOneWidget);
    }
  });

  group('FR-L10-03 Begin exam', () {
    testWidgets('begins the attempt and opens L12', (tester) async {
      await pump(tester);
      await begin(tester);

      expect(StubExamStart.begun, <(String, int, bool)>[('A1.2', 2, true)]);
      expect(went, '/exam/42');
    });

    testWidgets('the timer switch starts from the setting and goes with the '
        'exam', (tester) async {
      await pump(tester, artboardExamIntro(timer: false));
      expect(
        tester.widget<AdaptiveSwitch>(find.byType(AdaptiveSwitch)).value,
        isFalse,
      );
      expect(find.text(l10n.examIntroTimerLine(20)), findsOneWidget);

      await tester.tap(find.byType(AdaptiveSwitch));
      await tester.pumpAndSettle();
      await begin(tester);

      expect(StubExamStart.begun.single.$3, isTrue);
    });

    testWidgets('a failure says so and stays', (tester) async {
      StubExamStart.fail = true;
      await pump(tester);
      await begin(tester);

      expect(find.text(l10n.examIntroFailed), findsOneWidget);
      expect(went, isNull);
    });
  });
}
