import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L1 · Learn — #112.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Where L1 went, and with what.
  late String? went;
  late SessionArgs? session;

  GoRouter router() => GoRouter(
    initialLocation: '/learn',
    routes: <RouteBase>[
      GoRoute(
        path: '/learn',
        builder: (_, _) => const LearnScreen(),
        routes: <RouteBase>[
          for (final path in <String>['step/:code', 'grammar', 'categories'])
            GoRoute(
              path: path,
              builder: (_, state) {
                went = state.uri.path;
                return const Scaffold(body: Text('away'));
              },
            ),
        ],
      ),
      GoRoute(
        path: '/study',
        builder: (_, state) {
          went = state.uri.path;
          session = state.extra as SessionArgs?;
          return const Scaffold(body: Text('away'));
        },
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    List<StepProgress>? course,
    TodayView? today,
    Duration? dayAfter,
  }) async {
    went = null;
    session = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: todayStub(
          today ?? artboardToday(reviseDone: 7),
          course,
          dayAfter,
        ),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StepProgress progress({
    int todo = 100,
    int learning = 0,
    int done = 0,
    bool passed = false,
    bool active = false,
    bool unlocked = false,
  }) => StepProgress(
    code: 'A1.1',
    levelCode: 'A1',
    words: todo + learning + done,
    todo: todo,
    learning: learning,
    done: done,
    grammar: 10,
    grammarLearned: 0,
    unlocked: unlocked,
    passedSeed: passed ? 1 : null,
    startedOn: active ? '2026-08-19' : null,
    dailyNew: 7,
    studyDaysMask: 127,
  );

  group('FR-L1-01 the badge', () {
    test('Passed for any passed mock, even on the active step', () {
      expect(
        stepBadge(
          progress(done: 100, passed: true, active: true, unlocked: true),
        ),
        StepBadge.passed,
      );
    });

    test('Current for the active step, even with exams unlocked', () {
      expect(
        stepBadge(progress(todo: 0, done: 100, active: true, unlocked: true)),
        StepBadge.current,
      );
    });

    test('Exams unlocked, and nothing for a step merely started', () {
      expect(
        stepBadge(progress(todo: 10, done: 90, unlocked: true)),
        StepBadge.examsUnlocked,
      );
      expect(stepBadge(progress(todo: 11, done: 89)), StepBadge.none);
    });

    test('the lock for a step not started', () {
      expect(stepBadge(progress()), StepBadge.locked);
    });
  });

  testWidgets('FR-L1-01 the artboard: badges, bars and counts', (tester) async {
    await pump(tester);
    expect(find.text(l10n.learnTitle), findsOneWidget);
    // 480 + 470 done in A1, 184 in A2.1; 30 of 182 topics learned.
    expect(
      find.text(l10n.learnCourseLine(1134, 5594, 30, 182)),
      findsOneWidget,
    );
    expect(
      find.text('1,134 of 5,594 words · 30 of 182 grammar topics'),
      findsOneWidget,
    );
    expect(find.text('A1 · ANFÄNGER'), findsOneWidget);
    expect(find.text('A2 · GRUNDSTUFE'), findsOneWidget);
    expect(find.text(l10n.learnPassed), findsNWidgets(2));
    expect(find.text(l10n.learnCurrent), findsOneWidget);
    expect(find.text(l10n.learnStepLine(540, 10)), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp(l10n.learnNotStarted)), findsWidgets);
    semantics.dispose();
  });

  testWidgets('each level band is a heading of its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    for (final band in <String>['A1 · ANFÄNGER', 'A2 · GRUNDSTUFE']) {
      expect(
        tester.getSemantics(find.text(band)),
        matchesSemantics(label: band, isHeader: true),
        reason: band,
      );
    }
    semantics.dispose();
  });

  testWidgets('FR-L1-01 the current tile: what is left of today', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.learnTodayLeft(8)), findsOneWidget);
    expect(find.text(l10n.learnStudy), findsOneWidget);
  });

  testWidgets('counting only what is still open', (tester) async {
    await pump(tester, today: artboardToday());
    // Revise 10/10 and new 2/7: five new words still open.
    expect(find.text(l10n.learnTodayLeft(5)), findsOneWidget);
  });

  testWidgets('and once today is studied, no Study', (tester) async {
    await pump(tester, today: artboardToday(newDone: 7));
    expect(find.text(l10n.learnTodayDone), findsOneWidget);
    expect(find.text(l10n.learnStudy), findsNothing);
  });

  testWidgets('FR-L1-02 the current tile is scrolled into view on open', (
    tester,
  ) async {
    // The day comes in after the course: its row grows the tile, so the
    // scroll has to wait for it or the tile ends half off screen.
    await pump(
      tester,
      course: artboardCourse(active: 'C2.2'),
      dayAfter: const Duration(milliseconds: 200),
    );
    final tile = tester.getRect(
      find.ancestor(of: find.text('C2.2'), matching: find.byType(StepTile)),
    );
    final screen = tester.getRect(find.byType(LearnScreen));
    expect(tile.top, greaterThanOrEqualTo(screen.top));
    expect(tile.bottom, lessThanOrEqualTo(screen.bottom));
  });

  testWidgets('#317 scrolled to C2.2 on open, L1 keeps a Sun strip behind '
      'the status bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 120);
    addTearDown(tester.view.resetPadding);
    await pump(
      tester,
      course: artboardCourse(active: 'C2.2'),
      dayAfter: const Duration(milliseconds: 200),
    );
    final sun = tester.element(find.byType(LearnScreen)).tokens.color.accent;
    final strip = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == sun,
    );
    expect(
      tester.getRect(strip.last),
      Rect.fromLTWH(0, 0, tester.getSize(find.byType(LearnScreen)).width, 40),
    );
  });

  testWidgets('and one already on screen leaves the header in place', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.learnTitle), findsOneWidget);
    expect(tester.getTopLeft(find.text(l10n.learnTitle)).dy, lessThan(40));
  });

  testWidgets('FR-L1-03 a locked tile opens its step, never blocked', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('A2.2'));
    await tester.pumpAndSettle();
    expect(went, '/learn/step/A2.2');
  });

  testWidgets('FR-L1-04 Study opens the session Today\'s button opens', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(DpButton, l10n.learnStudy));
    await tester.pumpAndSettle();
    expect(went, '/study');
    expect(session!.planDate, '2026-09-21');
    expect(session!.blocks, <SessionBlock>[
      const SessionBlock(SessionBlockKind.revise, <String>['r7', 'r8', 'r9']),
      const SessionBlock(SessionBlockKind.newWords, <String>[
        'n2',
        'n3',
        'n4',
        'n5',
        'n6',
      ]),
    ]);
  });

  testWidgets('the grammar library card, with its live counts', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text(l10n.learnGrammarLibrary), 300);
    expect(find.text(l10n.learnGrammarLibraryLine(182, 30)), findsOneWidget);
    await tester.tap(find.text(l10n.learnGrammarLibrary));
    await tester.pumpAndSettle();
    expect(went, '/learn/grammar');
  });

  testWidgets('and the word categories card', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text(l10n.learnCategories), 300);
    await tester.tap(find.text(l10n.learnCategories));
    await tester.pumpAndSettle();
    expect(went, '/learn/categories');
  });
}
