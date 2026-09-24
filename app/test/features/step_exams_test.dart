import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_fixtures.dart';
import 'today_fixtures.dart';

/// L10 · Mock exam hub — #127 (unlocked), #128 (locked).
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Where L10 went.
  late String? went;

  StepProgress step({
    bool unlocked = true,
    bool passed = false,
    int todo = 0,
    int learning = 20,
    int done = 450,
    int mask = 127,
    int suspended = 0,
  }) => StepProgress(
    code: 'A1.2',
    levelCode: 'A1',
    words: todo + learning + done + suspended,
    todo: todo,
    learning: learning,
    done: done,
    grammar: 12,
    grammarLearned: 12,
    unlocked: unlocked,
    passedSeed: passed ? 1 : null,
    startedOn: '2026-07-01',
    dailyNew: 7,
    studyDaysMask: mask,
  );

  /// The ExamHubLocked artboard's step: 184 done and 60 learning of 540.
  StepProgress locked({int mask = 127, int todo = 296, int suspended = 0}) =>
      step(
        unlocked: false,
        todo: todo,
        learning: 60,
        done: 184,
        mask: mask,
        suspended: suspended,
      );

  Future<void> pump(
    WidgetTester tester, {
    ExamHub? hub,
    StepProgress? progress,
    TodayView? today,
  }) async {
    went = null;
    Widget away(GoRouterState state) {
      went = state.uri.toString();
      return const Scaffold(body: Text('away'));
    }

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          ...examStub(hub: hub),
          todayViewProvider.overrideWith(
            (ref) async => today ?? artboardToday(),
          ),
        ],
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
              for (final path in <String>['/study', '/today'])
                GoRoute(path: path, builder: (_, state) => away(state)),
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

  group('FR-L10-01 a locked step', () {
    testWidgets('no mocks: what unlocks them, how far, and how long', (
      tester,
    ) async {
      await pump(tester, progress: locked());

      expect(find.byType(MockCard), findsNothing);
      expect(find.text(l10n.examHubUnlocksWhen(90, 'A1.2')), findsOneWidget);
      // 90 % of 540 is 486; 242 left at 7 a day is 35 days.
      expect(
        find.text(
          '${l10n.examHubIntroduced(244, 486)} · ${l10n.examHubDaysAt(35, 7)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text('244 of 486 words introduced · about 35 days at 7 a day'),
        findsOneWidget,
      );
    });

    testWidgets('the days follow the study days', (tester) async {
      // Five study days a week: 242 ÷ 7 × 7 ÷ 5, rounded up.
      await pump(tester, progress: locked(mask: 31));
      expect(find.textContaining(l10n.examHubDaysAt(49, 7)), findsOneWidget);

      // None: no end to promise.
      await pump(tester, progress: locked(mask: 0));
      expect(find.text(l10n.examHubIntroduced(244, 486)), findsOneWidget);
    });

    testWidgets('BR-EXAM-01 the threshold is the setting\'s', (tester) async {
      await pump(
        tester,
        progress: locked(),
        hub: artboardExamHub(unlockPercent: 80),
      );

      expect(find.text(l10n.examHubUnlocksWhen(80, 'A1.2')), findsOneWidget);
      expect(
        find.textContaining(l10n.examHubIntroduced(244, 432)),
        findsOneWidget,
      );

      // Rounded up: 80 % of 543 is 434.4, so 435 words.
      await pump(
        tester,
        progress: locked(todo: 299),
        hub: artboardExamHub(unlockPercent: 80),
      );
      expect(
        find.textContaining(l10n.examHubIntroduced(244, 435)),
        findsOneWidget,
      );
    });

    testWidgets('BR-EXAM-01 suspended words are left out of the target', (
      tester,
    ) async {
      await pump(tester, progress: locked(suspended: 40));

      expect(
        find.textContaining(l10n.examHubIntroduced(244, 486)),
        findsOneWidget,
      );
    });

    testWidgets('Study now opens today\'s session', (tester) async {
      await pump(tester, progress: locked());
      await tester.tap(find.text(l10n.examHubStudyNow));
      await tester.pumpAndSettle();

      expect(went, '/study');
    });

    testWidgets('and Today once the day is done', (tester) async {
      await pump(tester, progress: locked(), today: artboardDone());
      await tester.tap(find.text(l10n.examHubStudyNow));
      await tester.pumpAndSettle();

      expect(went, '/today');
    });

    testWidgets('a screen reader hears the count once, and Study now as a '
        'button of its own', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, progress: locked());

      final card = tester
          .getSemantics(find.text(l10n.examHubUnlocksWhen(90, 'A1.2')))
          .label;
      expect(l10n.examHubIntroduced(244, 486).allMatches(card), hasLength(1));
      expect(
        tester.getSemantics(find.text(l10n.examHubStudyNow)),
        isSemantics(label: l10n.examHubStudyNow, isButton: true),
      );
      semantics.dispose();
    });

    testWidgets('the panel says where the threshold is changed', (
      tester,
    ) async {
      await pump(tester, progress: locked());
      expect(
        find.text('${l10n.examHubDisclaimer(60)} ${l10n.examHubThreshold}'),
        findsOneWidget,
      );

      await pump(tester);
      expect(find.textContaining(l10n.examHubThreshold), findsNothing);
    });
  });

  testWidgets('a passed step keeps its hub', (tester) async {
    await pump(tester, progress: step(unlocked: false, passed: true));

    expect(find.byType(MockCard), findsNWidgets(3));
  });
}
