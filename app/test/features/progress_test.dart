import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/word_repository.dart' show StepProgress;
import 'package:sogda/domain/progress_stats.dart';
import 'package:sogda/features/me/progress_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import 'progress_fixtures.dart';

/// M2 · Progress detail — #145.
void main() {
  late AppLocalizations l10n;
  late List<ProgressRange> asked;
  late String went;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(
    WidgetTester tester, {
    ProgressView? view,
    Future<ProgressView> Function(ProgressRange range)? load,
    List<StepProgress>? steps,
  }) async {
    asked = <ProgressRange>[];
    went = '';
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressViewProvider.overrideWith((ref, range) async {
            asked.add(range);
            return load?.call(range) ?? view ?? artboardProgress();
          }),
          stepProgressProvider.overrideWith(
            (ref) => Stream.value(steps ?? artboardProgressSteps()),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/me/progress',
            routes: <RouteBase>[
              GoRoute(
                path: '/me/progress',
                builder: (_, _) => const ProgressScreen(),
              ),
              GoRoute(
                path: '/learn/step/:code',
                builder: (_, state) {
                  went = state.uri.toString();
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("this week's cards, stacked: revisions under new words", (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(l10n.progressCardsPerDay), findsOneWidget);
    expect(
      find.text(l10n.progressCardsLine(l10n.progressPeriodWeek, 85)),
      findsOneWidget,
    );
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final monday = chart.data.barGroups.first.barRods.single;
    expect(
      monday.rodStackItems.map((s) => (s.fromY, s.toY)),
      <(double, double)>[(0, 11), (11, 17)],
      reason: 'revisions first, new words on top',
    );
    for (final label in <String>[
      l10n.weekdayShortMon,
      l10n.weekdayShortSun,
      l10n.progressRevisions,
      l10n.progressNew,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the segments ask for their view', (tester) async {
    await pump(tester);
    expect(asked, <ProgressRange>[ProgressRange.week]);

    await tester.tap(find.text(l10n.progressMonth));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.progressAll));
    await tester.pumpAndSettle();
    expect(asked, <ProgressRange>[
      ProgressRange.week,
      ProgressRange.month,
      ProgressRange.all,
    ]);
    expect(find.text(l10n.progressCardsPerMonth), findsOneWidget);
  });

  testWidgets('a range still loading keeps the last cards, and their labels', (
    tester,
  ) async {
    final month = Completer<ProgressView>();
    await pump(
      tester,
      load: (range) => range == ProgressRange.month
          ? month.future
          : Future<ProgressView>.value(artboardProgress()),
    );

    await tester.tap(find.text(l10n.progressMonth));
    await tester.pump();
    expect(find.byType(BarChart), findsOneWidget);
    expect(
      find.text(l10n.progressCardsLine(l10n.progressPeriodWeek, 85)),
      findsOneWidget,
    );
    expect(find.text(l10n.progressIntroduced), findsOneWidget);

    month.complete(artboardProgress());
    await tester.pumpAndSettle();
  });

  testWidgets('a view that fails to load says so, and Retry asks again', (
    tester,
  ) async {
    var fail = true;
    await pump(
      tester,
      load: (range) async =>
          fail ? throw StateError('disk') : artboardProgress(),
    );
    expect(find.text(l10n.meLoadFailed), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);

    fail = false;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.meLoadFailed), findsNothing);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets("a range that fails says so, not with the last range's cards", (
    tester,
  ) async {
    await pump(
      tester,
      load: (range) async => range == ProgressRange.month
          ? throw StateError('disk')
          : artboardProgress(),
    );
    await tester.tap(find.text(l10n.progressMonth));
    await tester.pumpAndSettle();

    expect(find.text(l10n.meLoadFailed), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  group('FR-M2-01 retention', () {
    testWidgets('the line against the dashed target', (tester) async {
      await pump(tester);

      expect(
        find.text(l10n.progressRetentionLine(88, l10n.progressPeriodWeek, 90)),
        findsOneWidget,
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots, hasLength(7));
      final target = chart.data.extraLinesData.horizontalLines.single;
      expect(target.y, 0.9);
      expect(target.dashArray, <int>[5, 4]);
    });

    testWidgets('before 30 days of data: when it will show', (tester) async {
      await pump(tester, view: artboardProgress(retentionDaysLeft: 12));

      expect(find.byType(LineChart), findsNothing);
      expect(find.text(l10n.progressRetentionLater(12)), findsOneWidget);
    });

    testWidgets('a period with no revisions says so', (tester) async {
      await pump(tester, view: artboardProgress(retentionOverall: null));
      expect(
        find.text(l10n.progressRetentionNone(l10n.progressPeriodWeek, 90)),
        findsOneWidget,
      );
    });
  });

  testWidgets('by step: the steps begun, and the way to each', (tester) async {
    await pump(tester);

    expect(find.text(l10n.progressStepCount(184, 540)), findsOneWidget);
    expect(find.text('A2.2'), findsNothing, reason: 'not begun');

    // accessibility-performance.md: 48 dp on Android.
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('A2.1'),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('A2.1'));
    await tester.pumpAndSettle();
    expect(went, '/learn/step/A2.1');
  });

  testWidgets('FR-M2-02 and -03: the totals', (tester) async {
    await pump(tester);

    for (final text in <String>[
      l10n.progressHours(6, 48),
      '1,560',
      '4,912',
      l10n.progressStreakBest(12, 19),
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('a screen reader hears each bar, not only its colour', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(l10n.progressBar(l10n.weekdayShortMon, 11, 6))),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('#854 By step counts To do as L2 and M1 do: not suspended or '
      'removed words', (tester) async {
    final semantics = tester.ensureSemantics();
    // 637 words: 563 done, 8 learning, 64 to do, and 2 suspended.
    final a11 = artboardProgressSteps().first;
    await pump(
      tester,
      steps: <StepProgress>[
        StepProgress(
          code: 'A1.1',
          levelCode: 'A1',
          words: 637,
          todo: 64,
          learning: 8,
          done: 563,
          grammar: a11.grammar,
          grammarLearned: a11.grammarLearned,
          unlocked: false,
          startedOn: '2026-06-01',
          dailyNew: 7,
          studyDaysMask: 127,
        ),
      ],
    );
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(l10n.progressBarLabel(563, 8, 64))),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('#853 a bar with one revision says it in the singular', () {
    expect(l10n.progressBar('Mo', 1, 0), 'Mo: 1 revision, 0 new');
    expect(l10n.progressBar('Mo', 2, 1), 'Mo: 2 revisions, 1 new');
  });

  testWidgets('iOS: "Me" beside the back chevron', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressViewProvider.overrideWith(
            (ref, range) async => artboardProgress(),
          ),
          stepProgressProvider.overrideWith(
            (ref) => Stream.value(artboardProgressSteps()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => AdaptiveChromeScope(
            chrome: AdaptiveChrome.cupertino,
            child: child!,
          ),
          home: const ProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.tabMe), findsOneWidget);
  });
}
