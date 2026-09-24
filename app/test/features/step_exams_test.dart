import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_fixtures.dart';

/// L10 · Mock exam hub — #127.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Where L10 went.
  late String? went;

  StepProgress step({bool unlocked = true, bool passed = false}) =>
      StepProgress(
        code: 'A1.2',
        levelCode: 'A1',
        words: 470,
        todo: 0,
        learning: 20,
        done: 450,
        grammar: 12,
        grammarLearned: 12,
        unlocked: unlocked,
        passedSeed: passed ? 1 : null,
        startedOn: '2026-07-01',
        dailyNew: 7,
        studyDaysMask: 127,
      );

  Future<void> pump(
    WidgetTester tester, {
    ExamHub? hub,
    StepProgress? progress,
  }) async {
    went = null;
    Widget away(GoRouterState state) {
      went = state.uri.toString();
      return const Scaffold(body: Text('away'));
    }

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: examStub(hub: hub),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/learn',
            routes: <RouteBase>[
              GoRoute(
                path: '/learn',
                builder: (_, _) =>
                    Scaffold(body: StepExamsTab(step: progress ?? step())),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'exam/:step/intro/:seed',
                    builder: (_, state) => away(state),
                  ),
                ],
              ),
              GoRoute(
                path: '/exam/:attemptId',
                builder: (_, state) => away(state),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder card(int seed) => find.ancestor(
    of: find.text(l10n.examHubMock(seed)),
    matching: find.byType(MockCard),
  );

  group('FR-L10-02 each mock\'s card', () {
    testWidgets('passed: its best score, in Lime', (tester) async {
      await pump(tester);
      final pill = tester.widget<DpPill>(
        find.descendant(of: card(1), matching: find.byType(DpPill)),
      );
      final tokens = tester.element(card(1)).tokens;

      expect(pill.label, l10n.examHubPassed(78));
      expect(pill.fill, tokens.color.easy);
      expect(
        find.descendant(
          of: card(1),
          matching: find.text(
            '${l10n.examHubLine(40, 20)} · ${l10n.examHubAttempts(2)}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('not yet: its best score, in Coral', (tester) async {
      await pump(tester);
      final pill = tester.widget<DpPill>(
        find.descendant(of: card(2), matching: find.byType(DpPill)),
      );

      expect(pill.label, l10n.examHubNotYet(62));
      expect(pill.fill, tester.element(card(2)).tokens.color.again);
      expect(find.text('62% — not yet'), findsOneWidget);
    });

    testWidgets('never sat: Not attempted, and BR-EXAM-02 on Mock 3', (
      tester,
    ) async {
      await pump(tester);

      expect(
        find.descendant(
          of: card(3),
          matching: find.text(l10n.examHubNotAttempted),
        ),
        findsOneWidget,
      );
      expect(
        find.text('${l10n.examHubLine(40, 20)} · ${l10n.examHubNoRepeats(3)}'),
        findsOneWidget,
      );
      expect(find.textContaining('no repeats within the step'), findsOneWidget);
    });

    testWidgets('FR-L12-04 only left unfinished: an attempt, and no score', (
      tester,
    ) async {
      await pump(
        tester,
        hub: artboardExamHub(
          seeds: const <SeedSummary>[
            SeedSummary(
              seed: 1,
              attempts: 1,
              finished: 0,
              bestPercent: 0,
              everPassed: false,
            ),
          ],
        ),
      );

      expect(
        find.descendant(of: card(1), matching: find.byType(DpPill)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card(1),
          matching: find.text(l10n.examHubNotAttempted),
        ),
        findsNothing,
      );
      expect(
        find.text('${l10n.examHubLine(40, 20)} · ${l10n.examHubAttempts(1)}'),
        findsOneWidget,
      );
    });

    testWidgets(
      'BR-EXAM-04 a fail never shows the pass mark: 69.8 % reads 69',
      (tester) async {
        // 33.5 of 48 at a 70 % mark.
        await pump(
          tester,
          hub: artboardExamHub(
            passPercent: 70,
            seeds: const <SeedSummary>[
              SeedSummary(
                seed: 2,
                attempts: 1,
                finished: 1,
                bestPercent: 33.5 * 100 / 48,
                everPassed: false,
              ),
            ],
          ),
        );

        expect(find.text(l10n.examHubNotYet(69)), findsOneWidget);
      },
    );

    testWidgets('BR-EXAM-02 a mock that shares grammar topics says so', (
      tester,
    ) async {
      await pump(tester, hub: artboardExamHub(reused: <int>{3}));

      expect(
        find.text('${l10n.examHubLine(40, 20)} · ${l10n.examHubShares}'),
        findsOneWidget,
      );
      expect(find.textContaining(l10n.examHubNoRepeats(3)), findsNothing);
    });

    testWidgets('and only that mock: Mock 3 keeps its note when Mock 2 '
        'shares', (tester) async {
      await pump(tester, hub: artboardExamHub(reused: <int>{2}));

      expect(
        find.descendant(
          of: card(2),
          matching: find.textContaining(l10n.examHubShares),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(l10n.examHubNoRepeats(3)), findsOneWidget);
    });

    testWidgets('Start opens L11 for that mock', (tester) async {
      await pump(tester);
      await tester.tap(
        find.descendant(of: card(2), matching: find.text(l10n.examHubStart)),
      );
      await tester.pumpAndSettle();

      expect(went, '/learn/exam/A1.2/intro/2');
    });

    testWidgets('an unfinished attempt offers Resume, into L12', (
      tester,
    ) async {
      await pump(tester, hub: artboardExamHub(resume: <int, int>{3: 17}));

      expect(
        find.descendant(of: card(3), matching: find.text(l10n.examHubStart)),
        findsNothing,
      );
      // Begun, never finished: no "Not attempted" beside Resume.
      expect(
        find.descendant(
          of: card(3),
          matching: find.text(l10n.examHubNotAttempted),
        ),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: card(3), matching: find.text(l10n.examHubResume)),
      );
      await tester.pumpAndSettle();

      expect(went, '/exam/17');
    });
  });

  group('BR-EXAM-03 what\'s in these exams', () {
    testWidgets('the sections and their counts, then the disclaimer', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(l10n.examHubContents.toUpperCase()), findsOneWidget);
      expect(
        find.text(
          'Vocabulary 10 · Reverse 8 · Articles 6 · Word forms 4 · Gap fill 6 '
          '· Grammar 4 · Listening 2 · Writing · Speaking',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Generated practice exams from this step's words and grammar — not "
          'official Goethe or telc papers. Pass mark 60%.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('FR-L10-04 with listening off, its points moved', (
      tester,
    ) async {
      await pump(tester, hub: artboardExamHub(listening: false));

      expect(
        find.text(
          'Vocabulary 11 · Reverse 9 · Articles 6 · Word forms 4 · Gap fill 6 '
          '· Grammar 4 · Writing · Speaking',
        ),
        findsOneWidget,
      );
      // Still 40 questions.
      expect(find.textContaining(l10n.examHubLine(40, 20)), findsNWidgets(3));
    });

    testWidgets('BR-EXAM-04 the pass mark is the setting\'s', (tester) async {
      await pump(tester, hub: artboardExamHub(passPercent: 75));

      expect(find.textContaining('Pass mark 75%.'), findsOneWidget);
    });
  });

  testWidgets('BR-EXAM-01 a locked step has no hub yet', (tester) async {
    await pump(tester, progress: step(unlocked: false));

    expect(find.byType(MockCard), findsNothing);
    expect(find.text(l10n.stepTabExams), findsOneWidget);
  });

  testWidgets('a passed step keeps its hub', (tester) async {
    await pump(tester, progress: step(unlocked: false, passed: true));

    expect(find.byType(MockCard), findsNWidgets(3));
  });
}
