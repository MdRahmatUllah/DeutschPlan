import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';
import '../core/text_clipping.dart';

/// L2 · Step detail, the shell — #113.
void main() {
  late AppLocalizations l10n;
  const en = Locale('en');

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    // The app loads these with its localizations; a plain test has none.
    await initializeDateFormatting('en');
  });

  StepProgress step({
    int todo = 296,
    String? startedOn = '2026-08-19',
    String? completedOn,
    int? passedSeed,
    int dailyNew = 7,
    int studyDaysMask = 127,
    String code = 'A2.1',
    String level = 'A2',
  }) => StepProgress(
    code: code,
    levelCode: level,
    words: 540,
    todo: todo,
    learning: 60,
    done: 540 - 60 - todo,
    grammar: 10,
    grammarLearned: 4,
    unlocked: false,
    passedSeed: passedSeed,
    startedOn: startedOn,
    completedOn: completedOn,
    dailyNew: dailyNew,
    studyDaysMask: studyDaysMask,
  );

  group('FR-L2-01 the pace line', () {
    test('To-do words ÷ daily_new × (7 ÷ study days), rounded up', () {
      // 296 at 7 a day, every day: 42.3, so about 43.
      expect(
        paceLine(l10n, en, step()),
        'Started 19 Aug · about 43 days left at 7 words/day',
      );
      // Five study days a week: 296 × 7 ÷ 35 = 59.2, so 60.
      expect(
        paceLine(l10n, en, step(studyDaysMask: 31)),
        'Started 19 Aug · about 60 days left at 7 words/day',
      );
      expect(
        paceLine(l10n, en, step(dailyNew: 10)),
        'Started 19 Aug · about 30 days left at 10 words/day',
      );
    });

    test('a step with nothing left to do says so', () {
      expect(
        paceLine(l10n, en, step(todo: 0)),
        'Started 19 Aug · every word introduced',
      );
    });

    test('a completed step: when, the first mock passed, and revision', () {
      expect(
        paceLine(
          l10n,
          en,
          step(completedOn: '2026-08-18', passedSeed: 1, todo: 0),
        ),
        'Completed 18 Aug · Mock 1 passed · revision continues',
      );
      expect(
        paceLine(l10n, en, step(completedOn: '2026-08-18', todo: 0)),
        'Completed 18 Aug · revision continues',
      );
    });

    test('a step never started: how long it would take at the pace', () {
      expect(
        paceLine(l10n, en, step(startedOn: null, todo: 540)),
        'Not started · about 78 days at 7 words/day',
      );
    });
  });

  late String? went;

  GoRouter router() => GoRouter(
    initialLocation: '/learn',
    routes: <RouteBase>[
      GoRoute(
        path: '/learn',
        builder: (_, _) => const Scaffold(body: Text('L1')),
        routes: <RouteBase>[
          GoRoute(
            path: 'step/:code',
            builder: (_, state) => StepDetailScreen(
              code: state.pathParameters['code']!,
              tab: StepTab.values
                  .where((tab) => tab.name == state.uri.queryParameters['tab'])
                  .firstOrNull,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (_, state) {
          went = state.uri.toString();
          return const Scaffold(body: Text('R1'));
        },
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    String at, {
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    went = null;
    final routes = router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: todayStub(),
        child: AdaptiveChromeScope(
          chrome: chrome,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: routes,
          ),
        ),
      ),
    );
    // Pushed over L1, as a tile opens it.
    unawaited(routes.push(at));
    await tester.pumpAndSettle();
  }

  /// Which tab's body is showing.
  bool showing(WidgetTester tester, String tab) =>
      tester
          .widgetList<StepTabBody>(find.byType(StepTabBody))
          .single
          .tab
          .name ==
      tab;

  testWidgets('the header: code, level, words and topics, bar and pace', (
    tester,
  ) async {
    await pump(tester, '/learn/step/A2.1');
    expect(find.text('A2.1'), findsOneWidget);
    expect(
      find.text('Grundstufe · ${l10n.stepHeaderCounts(540, 10)}'),
      findsOneWidget,
    );
    expect(
      find.text('Started 19 Aug · about 43 days left at 7 words/day'),
      findsOneWidget,
    );
  });

  testWidgets('a level with no German name shows the counts alone', (
    tester,
  ) async {
    await pump(tester, '/learn/step/B2.1');
    expect(find.text(l10n.stepHeaderCounts(520, 18)), findsOneWidget);
  });

  testWidgets('a completed step: Mock 1 passed, revision continues', (
    tester,
  ) async {
    await pump(tester, '/learn/step/A1.2');
    expect(
      find.text('Completed 18 Aug · Mock 1 passed · revision continues'),
      findsOneWidget,
    );
  });

  testWidgets('a step the course does not have says so, with a way back', (
    tester,
  ) async {
    await pump(tester, '/learn/step/Z9.9');
    expect(find.text(l10n.stepNotFound('Z9.9')), findsOneWidget);
    await tester.tap(find.text(l10n.stepBackToCourse));
    await tester.pumpAndSettle();
    expect(find.text('L1'), findsOneWidget);
  });

  testWidgets('four inner tabs, Words first', (tester) async {
    await pump(tester, '/learn/step/A2.1');
    for (final label in <String>[
      l10n.stepTabWords,
      l10n.stepTabGrammar,
      l10n.stepTabQuiz,
      l10n.stepTabExams,
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(showing(tester, 'words'), isTrue);
    await tester.tap(find.text(l10n.stepTabGrammar));
    await tester.pumpAndSettle();
    expect(showing(tester, 'grammar'), isTrue);
  });

  testWidgets('?tab= opens the tab a deep entry point asked for', (
    tester,
  ) async {
    await pump(tester, '/learn/step/A1.2?tab=exams');
    expect(showing(tester, 'exams'), isTrue);
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, StepTab.exams.index);
  });

  testWidgets('and follows a new ?tab= when the same step is reached again', (
    tester,
  ) async {
    Widget screen(StepTab tab) => ProviderScope(
      overrides: todayStub(),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: StepDetailScreen(code: 'A1.2', tab: tab),
      ),
    );
    await tester.pumpWidget(screen(StepTab.words));
    await tester.pumpAndSettle();
    expect(showing(tester, 'words'), isTrue);
    // The exam card's jump, while A1.2 is already open on Words.
    await tester.pumpWidget(screen(StepTab.exams));
    await tester.pumpAndSettle();
    expect(showing(tester, 'exams'), isTrue);
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, StepTab.exams.index);
  });

  testWidgets('the search icon opens R1 filtered to the step', (tester) async {
    await pump(tester, '/learn/step/A2.1');
    await tester.tap(find.byTooltip(l10n.stepSearch));
    await tester.pumpAndSettle();
    expect(went, '/search?step=A2.1');
  });

  testWidgets('back returns to the course map', (tester) async {
    await pump(tester, '/learn/step/A2.1');
    await tester.tap(find.byType(AdaptiveBackButton));
    await tester.pumpAndSettle();
    expect(find.text('L1'), findsOneWidget);
  });

  testWidgets('iOS: a segmented control, the code centred in the bar and '
      'a labelled back', (tester) async {
    await pump(tester, '/learn/step/A2.1', chrome: AdaptiveChrome.cupertino);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(AdaptiveSegmented<StepTab>), findsOneWidget);
    expect(find.text('A2.1'), findsNWidgets(2));
    expect(find.text(l10n.tabLearn), findsOneWidget);
    await tester.tap(find.text(l10n.stepTabQuiz));
    await tester.pumpAndSettle();
    expect(showing(tester, 'quiz'), isTrue);
  });

  testWidgets('#404 at 200 % text the back row keeps its label whole, in '
      'either chrome', (tester) async {
    textAt(tester, 2);
    for (final chrome in AdaptiveChrome.values) {
      await pump(tester, '/learn/step/A2.1', chrome: chrome);
      expectNothingClipped(tester, within: find.byType(AdaptiveBackButton));
    }
  });
}
