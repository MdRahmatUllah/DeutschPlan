import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:deutschplan/features/me/me_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'me_fixtures.dart';

/// M1 · Me — #144.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Where M1 went.
  late String? went;

  GoRouter router() {
    Widget away(GoRouterState state) {
      went = state.uri.toString();
      return const Scaffold(body: Text('away'));
    }

    return GoRouter(
      initialLocation: '/me',
      routes: <RouteBase>[
        GoRoute(
          path: '/me',
          builder: (_, _) => const MeScreen(),
          routes: <RouteBase>[
            for (final path in <String>[
              'progress',
              'settings',
              'models',
              'about',
            ])
              GoRoute(path: path, builder: (_, state) => away(state)),
          ],
        ),
        GoRoute(path: '/today/backlog', builder: (_, state) => away(state)),
        GoRoute(path: '/learn/step/:code', builder: (_, state) => away(state)),
      ],
    );
  }

  Future<void> pump(WidgetTester tester, [MeView? view, Locale? locale]) async {
    went = null;
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: meStub(view),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          locale: locale,
          routerConfig: router(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  StepProgress step(
    String code, {
    bool passed = false,
    bool unlocked = false,
    bool active = false,
  }) => StepProgress(
    code: code,
    levelCode: code.substring(0, 2),
    words: 100,
    todo: 50,
    learning: 25,
    done: 25,
    grammar: 10,
    grammarLearned: 0,
    unlocked: unlocked,
    passedSeed: passed ? 1 : null,
    startedOn: active ? '2026-08-19' : null,
    dailyNew: 7,
    studyDaysMask: 127,
  );

  testWidgets("#317 Me's Cobalt stays behind the status bar when scrolled", (
    tester,
  ) async {
    await pump(tester);
    final scaffold = tester.widget<AdaptiveScaffold>(
      find
          .descendant(
            of: find.byType(MeScreen),
            matching: find.byType(AdaptiveScaffold),
          )
          .first,
    );
    expect(
      scaffold.statusBarColour,
      tester.element(find.byType(MeScreen)).tokens.color.der,
    );
  });

  group('FR-M1-01 the words card', () {
    testWidgets('sums the whole course', (tester) async {
      await pump(tester);

      expect(find.text('1,248'), findsOneWidget);
      expect(find.text('312'), findsOneWidget);
      expect(find.text('4,034'), findsOneWidget);
    });

    testWidgets('the legend says what Done means, from the setting', (
      tester,
    ) async {
      final view = artboardMe();
      await pump(tester, (
        today: view.today,
        steps: view.steps,
        streak: view.streak,
        since: view.since,
        activity: view.activity,
        schedule: view.schedule,
        doneDays: 21,
        unlockPercent: view.unlockPercent,
      ));

      expect(find.text(l10n.meWordsLegend(21)), findsOneWidget);
      expect(find.textContaining('21+ days'), findsOneWidget);
    });

    testWidgets('opens M2', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.text('1,248'));

      expect(went, '/me/progress');
    });
  });

  group('FR-M1-02 the heat-map', () {
    test('five shades: 0 / 1–9 / 10–19 / 20–39 / 40 or more', () {
      expect(
        <int>[
          for (final items in <int>[0, 1, 9, 10, 19, 20, 39, 40, 400])
            activityShade(items),
        ],
        <int>[0, 1, 1, 2, 2, 3, 3, 4, 4],
      );
    });

    test('twelve weeks from Monday, the last the week of today', () {
      // 21 September 2026 is a Monday: the last week is that day alone.
      final weeks = activityWeeks('2026-09-21');

      expect(weeks, hasLength(12));
      expect(weeks.every((week) => week.length == 7), isTrue);
      expect(weeks.first.first, '2026-07-06');
      expect(weeks.last, <String?>['2026-09-21', ...List.filled(6, null)]);
      expect(weeks[10].last, '2026-09-20');
    });

    test('a Sunday fills its week, and a Wednesday stops there', () {
      expect(activityWeeks('2026-09-27').last.last, '2026-09-27');
      expect(activityWeeks('2026-09-23').last, <String?>[
        '2026-09-21',
        '2026-09-22',
        '2026-09-23',
        null,
        null,
        null,
        null,
      ]);
    });

    testWidgets('each day is drawn in its shade of Lagoon', (tester) async {
      final view = artboardMe(
        activity: <String, int>{
          '2026-09-14': 5,
          '2026-09-15': 15,
          '2026-09-16': 30,
          '2026-09-17': 45,
        },
      );
      await pump(tester, view);
      final tokens = tester.element(find.byType(MeScreen)).tokens;

      Color? colour(String day) =>
          ((tester.widget<Container>(find.byKey(ValueKey<String>(day))))
                      .decoration!
                  as BoxDecoration)
              .color;

      expect(colour('2026-09-13'), tokens.surface.track, reason: '#437');
      expect(
        colour('2026-09-14'),
        tokens.color.primary.withValues(alpha: 0.15),
      );
      expect(
        colour('2026-09-15'),
        tokens.color.primary.withValues(alpha: 0.35),
      );
      expect(
        colour('2026-09-16'),
        tokens.color.primary.withValues(alpha: 0.65),
      );
      expect(colour('2026-09-17'), tokens.color.primary);
    });

    testWidgets('reads out how many days had practice', (tester) async {
      await pump(
        tester,
        artboardMe(
          activity: <String, int>{
            '2026-09-20': 3,
            '2026-09-21': 30,
            // Before the twelve weeks: studied, but not on the map.
            '2026-01-01': 5,
            // After today, from a change of clock or time zone: neither.
            '2026-09-22': 5,
          },
        ),
      );

      // Read with the rest of the card, which is one button.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n.meActivityLabel(2)))),
        findsOneWidget,
      );
      // The header counts every day ever studied.
      expect(find.textContaining(l10n.meDaysStudied(3)), findsOneWidget);
    });

    testWidgets('opens M2', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.text(l10n.meActivity));

      expect(went, '/me/progress');
    });
  });

  group('FR-M1-03 the schedule card', () {
    testWidgets('behind: days and words, and it opens the backlog', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(l10n.meBehind(2)), findsOneWidget);
      expect(find.text('2 days behind'), findsOneWidget);
      expect(find.text(l10n.meBehindLine(14)), findsOneWidget);

      await tapAndSettle(tester, find.text(l10n.meBehind(2)));
      expect(went, '/today/backlog');
    });

    testWidgets('under a day behind says so', (tester) async {
      await pump(
        tester,
        artboardMe(
          schedule: const ScheduleStatus(
            planned: 10,
            introduced: 7,
            dailyNew: 7,
          ),
        ),
      );

      expect(find.text(l10n.meBehindUnderADay), findsOneWidget);
      expect(find.text(l10n.meBehindLine(3)), findsOneWidget);
    });

    testWidgets('on schedule is read on its own, not with the exams', (
      tester,
    ) async {
      await pump(
        tester,
        artboardMe(
          schedule: const ScheduleStatus(
            planned: 140,
            introduced: 140,
            dailyNew: 7,
          ),
        ),
      );

      expect(find.bySemanticsLabel(l10n.meOnSchedule), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '${l10n.meExams}\n${l10n.meExamsPassed(2)} · '
          '${l10n.meExamsUnlocksAt('A2.1', 90)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('on schedule: no backlog line, and nowhere to go', (
      tester,
    ) async {
      await pump(
        tester,
        artboardMe(
          schedule: const ScheduleStatus(
            planned: 140,
            introduced: 140,
            dailyNew: 7,
          ),
        ),
      );

      expect(find.text(l10n.meOnSchedule), findsOneWidget);
      expect(find.textContaining('backlog'), findsNothing);
      await tapAndSettle(tester, find.text(l10n.meOnSchedule));
      expect(went, isNull);
    });
  });

  group('FR-M1-04 the mock exams card', () {
    test(
      'Lime passed, Lagoon unlocked, then the current step, then locked',
      () {
        expect(
          examBadge(step('A1.1', passed: true, unlocked: true, active: true)),
          ExamBadge.passed,
        );
        expect(
          examBadge(step('A1.1', unlocked: true, active: true)),
          ExamBadge.unlocked,
        );
        expect(examBadge(step('A1.1', active: true)), ExamBadge.current);
        expect(examBadge(step('A1.1')), ExamBadge.locked);
      },
    );

    testWidgets('a badge opens L10 for its step, in Learn', (tester) async {
      await pump(tester);
      await tapAndSettle(
        tester,
        find.bySemanticsLabel(l10n.meBadge('A1.2', l10n.learnPassed)),
      );

      expect(went, '/learn/step/A1.2?tab=exams');
    });

    testWidgets('#396 a locked step reads "Exams locked", not "Not started", '
        'and opens its hub too', (tester) async {
      await pump(tester);
      expect(
        find.bySemanticsLabel(l10n.meBadge('C2.2', l10n.learnNotStarted)),
        findsNothing,
      );
      await tapAndSettle(
        tester,
        find.bySemanticsLabel(l10n.meBadge('C2.2', l10n.meExamsLocked)),
      );

      expect(went, '/learn/step/C2.2?tab=exams');
    });

    testWidgets('the line: passed, and when the current step unlocks', (
      tester,
    ) async {
      await pump(tester);

      expect(
        find.text(
          '${l10n.meExamsPassed(2)} · ${l10n.meExamsUnlocksAt('A2.1', 90)}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.meBadge('A2.1', l10n.learnCurrent)),
        findsOneWidget,
      );
    });

    testWidgets('an unlocked current step says so', (tester) async {
      await pump(
        tester,
        artboardMe(
          steps: <StepProgress>[
            step('A1.1', passed: true),
            step('A1.2', unlocked: true, active: true),
            step('A2.1'),
          ],
        ),
      );

      expect(
        find.text('${l10n.meExamsPassed(1)} · ${l10n.meExamsUnlocked('A1.2')}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.meBadge('A1.2', l10n.learnExamsUnlocked)),
        findsOneWidget,
      );
    });

    testWidgets('each badge is a 48 dp target', (tester) async {
      await pump(tester);

      expect(
        tester
            .getSize(
              find.bySemanticsLabel(l10n.meBadge('A1.1', l10n.learnPassed)),
            )
            .height,
        48,
      );
    });
  });

  group('the header', () {
    testWidgets('the name, the streak, and since when', (tester) async {
      await pump(tester);

      expect(find.text('Maruf'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      // Read with the line under it: the pill is not a button here.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n.todayStreak(12)))),
        findsOneWidget,
      );
      expect(
        find.text(
          '${l10n.meSince('19 Aug 2026')} · '
          '${l10n.meDaysStudied(artboardActivity().length)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('before the course began, only the days studied', (
      tester,
    ) async {
      await pump(
        tester,
        artboardMe(since: null, activity: const <String, int>{}),
      );

      expect(find.text(l10n.meDaysStudied(0)), findsOneWidget);
    });

    testWidgets('edit name: the sheet saves what was typed', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.bySemanticsLabel('Maruf'));

      expect(find.text(l10n.meNameTitle), findsWidgets);
      await tester.enterText(find.byType(TextField), '  Rahmat ');
      await tapAndSettle(tester, find.text(l10n.meNameSave));

      expect(find.text('Rahmat'), findsOneWidget);
      expect(find.text('Maruf'), findsNothing);
    });

    testWidgets('a blank name asks for one', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.bySemanticsLabel('Maruf'));
      await tester.enterText(find.byType(TextField), '   ');
      await tapAndSettle(tester, find.text(l10n.meNameSave));

      expect(find.text(l10n.meNameEmpty), findsOneWidget);
    });

    testWidgets('dismissing the sheet keeps the name', (tester) async {
      await pump(tester);
      await tapAndSettle(tester, find.bySemanticsLabel('Maruf'));
      await tester.enterText(find.byType(TextField), 'Rahmat');
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      expect(find.text('Maruf'), findsOneWidget);
    });
  });

  group('the list', () {
    for (final (label, path) in <(String Function(), String)>[
      (() => l10n.meSettings, '/me/settings'),
      (() => l10n.meVoice, '/me/models'),
      (() => l10n.meAbout, '/me/about'),
    ]) {
      testWidgets('opens $path', (tester) async {
        await pump(tester);
        await tapAndSettle(tester, find.text(label()));

        expect(went, path);
      });
    }
  });

  testWidgets('a failed load says so, and retries', (tester) async {
    went = null;
    var fail = true;
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          learnerNameProvider.overrideWith(StubLearnerName.new),
          meViewProvider.overrideWith((ref) async {
            if (fail) throw StateError('no database');
            return artboardMe();
          }),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.meLoadFailed), findsOneWidget);
    fail = false;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('1,248'), findsOneWidget);
  });

  testWidgets("#425 in the Bangla UI, M1's course bar reads Bangla", (
    tester,
  ) async {
    await pump(tester, null, const Locale('bn'));
    final bar = find.bySemanticsLabel(RegExp('টি শেখা হয়েছে, '));
    await tester.scrollUntilVisible(bar, 200);
    expect(bar, findsWidgets);
    expect(
      find.bySemanticsLabel(
        RegExp(r'\d+ done, \d+ learning, \d+ to do|\b\d+ of \d+\b'),
      ),
      findsNothing,
    );
  });
}
