@TestOn('vm')
library;

import 'package:deutschplan/features/backlog/backlog_screen.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/features/today/today_screen.dart';

import '../features/today_fixtures.dart';

import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../domain/placement_test.dart' show wordFor;

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/features/learn/grammar_library_screen.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The shell and the route table — #67.
///
/// `docs/01-architecture/navigation.md` is the spec, and its route table is
/// read out of the doc rather than restated here: a path added to the doc and
/// not to the router should fail, and a test that copied the table would only
/// ever agree with itself.
void main() {
  // Today's first line, which scrolls away first.
  final todayTop = germanDate(artboardToday().date);

  late GoRouter router;

  /// What a real caller passes to the routes that take one. `/study` is
  /// guarded on it (#68), so a test that navigated there empty would be
  /// redirected — which is the guard working, not the route missing.
  Object? extraFor(String path) => switch (path) {
    '/study' => const SessionArgs(
      blocks: <SessionBlock>[
        SessionBlock(SessionBlockKind.revise, <String>['uid-haus']),
      ],
    ),
    '/quiz' => const QuizArgs(direction: 'deEn', source: 'allLearned', seed: 1),
    '/grammar-practice' => const GrammarPracticeArgs(topicUids: <String>['g1']),
    _ => null,
  };

  Future<void> pumpApp(WidgetTester tester, {String at = '/today'}) async {
    router = buildRouter(initialLocation: at);
    addTearDown(router.dispose);

    // S3 reads the course to draw its first question; with nothing to read
    // it would end at once and leave for page 3, and the path would look
    // unreachable. A course of one step keeps it where the table puts it.
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...todayStub(),
          languagesProvider.overrideWith(
            () => _FixedLanguages(MeaningLanguage.english),
          ),
          contentDaoProvider.overrideWithValue(_OneStepDao(db)),
          courseStepsProvider.overrideWith(
            (ref) async => const <CourseStep>[
              (code: 'A1.1', levelCode: 'A1', wordCount: 12),
            ],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Whether the last navigation actually matched a route.
  ///
  /// `currentConfiguration.uri` is what was *asked for*, not what matched —
  /// go_router keeps the URL and falls through to `errorBuilder`. Comparing
  /// the two would say a route exists when nothing does, which is how the
  /// first version of the table test passed with a route deleted.
  bool matched() => !router.routerDelegate.currentConfiguration.isError;

  group('every path in the doc exists as a route', () {
    /// The `| /path |` cells of navigation.md's route table.
    List<String> documentedPaths() {
      final doc = File('../docs/01-architecture/navigation.md')
          .readAsStringSync();
      final table = doc.substring(
        doc.indexOf('## Route table'),
        doc.indexOf('## Behaviour rules'),
      );

      final paths = <String>{};
      for (final match in RegExp(r'`(/[^`]*)`').allMatches(table)) {
        final raw = match.group(1)!;
        // The table writes a query variant and an `extra` note inside the
        // same cell; the route is the path.
        final path = raw.split(RegExp(r'[ (?]')).first;
        if (path.length > 1) paths.add(path);
      }
      return paths.toList()..sort();
    }

    test('the doc really does list them', () {
      // If the parse broke, every assertion below would pass vacuously.
      final paths = documentedPaths();
      expect(paths, hasLength(greaterThanOrEqualTo(25)));
      expect(paths, contains('/today'));
      expect(paths, contains('/exam/:attemptId'));
    });

    testWidgets('and the router matches each one', (tester) async {
      await pumpApp(tester);

      final missing = <String>[];
      for (final path in documentedPaths()) {
        // Fill the parameters with something that parses: `:id` and `:seed`
        // are ints in the typed routes.
        final concrete = path
            .replaceAll(':attemptId', '7')
            .replaceAll(':seed', '2')
            .replaceAll(':id', '3')
            .replaceAll(':page', '1')
            .replaceAll(':code', 'A1.1')
            .replaceAll(':step', 'A1.1')
            .replaceAll(':uid', 'uid-haus');

        router.go(concrete, extra: extraFor(concrete));
        await tester.pumpAndSettle();

        if (!matched() || location() != concrete) {
          missing.add('$path -> ${matched() ? location() : "no route"}');
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'navigation.md lists these and the router does not reach '
            'them:\n${missing.join('\n')}',
      );
    });
  });

  group('the Learn screens behind their routes', () {
    for (final (path, screen) in <(String, Type)>[
      ('/learn', LearnScreen),
      ('/learn/step/A2.1', StepDetailScreen),
      ('/learn/grammar', GrammarLibraryScreen),
    ]) {
      testWidgets(path, (tester) async {
        await pumpApp(tester, at: path);
        expect(find.byType(screen), findsOneWidget);
      });
    }
  });

  group('the four branches', () {
    testWidgets('start on Today', (tester) async {
      await pumpApp(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('each tab shows its own root', (tester) async {
      await pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);

      for (final pair in <(String, Finder)>[
        (l10n.tabLearn, find.byType(LearnScreen)),
        (l10n.tabSearch, find.text('R1')),
        (l10n.tabMe, find.text('M1')),
        (l10n.tabToday, find.byType(TodayScreen)),
      ]) {
        await tester.tap(find.text(pair.$1).last);
        await tester.pumpAndSettle();
        expect(pair.$2, findsOneWidget, reason: pair.$1);
      }
    });

    testWidgets("each tab's pill is its own colour", (tester) async {
      // The artboards: Today Lagoon, Learn Sun, Search Raspberry, Me Cobalt.
      await pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
      final colours = tester.element(find.byType(AppShell)).tokens.color;
      for (final (tab, pill) in <(String, Color)>[
        (l10n.tabLearn, colours.accent),
        (l10n.tabSearch, colours.die),
        (l10n.tabMe, colours.der),
        (l10n.tabToday, colours.primary),
      ]) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .indicatorColor,
          pill,
          reason: tab,
        );
      }
    });

    testWidgets('a tab keeps its pushed route while another is used', (
      tester,
    ) async {
      // What `indexedStack` buys: leaving Learn on a step and coming back
      // finds the step, not /learn.
      await pumpApp(tester, at: '/learn/step/A1.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);

      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
      await tester.tap(find.text(l10n.tabToday).last);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);

      await tester.tap(find.text(l10n.tabLearn).last);
      await tester.pumpAndSettle();
      expect(
        find.byType(StepDetailScreen),
        findsOneWidget,
        reason: 'the branch was reset',
      );
    });

    testWidgets('a tab keeps its scroll position', (tester) async {
      await pumpApp(tester);
      await tester.drag(find.text(todayTop), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text(todayTop), findsNothing);

      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
      await tester.tap(find.text(l10n.tabMe).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.tabToday).last);
      await tester.pumpAndSettle();

      expect(
        find.text(todayTop),
        findsNothing,
        reason: 'the branch scrolled back to the top',
      );
    });
  });

  group('re-tapping the current tab', () {
    Future<String> tabLabel() async =>
        (await AppLocalizations.delegate.load(supportedLocales.first)).tabToday;

    testWidgets('scrolls to top', (tester) async {
      await pumpApp(tester);
      await tester.drag(find.text(todayTop), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text(todayTop), findsNothing);

      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();

      expect(find.text(todayTop), findsOneWidget);
    });

    testWidgets('does not pop while there is still somewhere to scroll', (
      tester,
    ) async {
      // The order matters: a re-tap that popped straight to root would throw
      // away the screen the learner is reading.
      await pumpApp(tester, at: '/today/backlog');
      await tester.drag(
        find.text('das Wort1', findRichText: true),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();

      expect(
        find.byType(BacklogScreen),
        findsOneWidget,
        reason: 'it popped too early',
      );
      expect(find.text('das Wort1', findRichText: true), findsOneWidget);
    });

    testWidgets('the second re-tap pops to root', (tester) async {
      await pumpApp(tester, at: '/today/backlog');
      expect(find.byType(BacklogScreen), findsOneWidget);

      // Already at the top, so the first re-tap has nothing to scroll.
      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(BacklogScreen), findsNothing);
    });

    testWidgets('scroll then pop, in that order', (tester) async {
      await pumpApp(tester, at: '/today/backlog');
      await tester.drag(
        find.text('das Wort1', findRichText: true),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();
      expect(find.byType(BacklogScreen), findsOneWidget);

      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('it scrolls the tab that is showing, not the one behind', (
      tester,
    ) async {
      // `IndexedStack` keeps every branch alive, so Learn's controller still
      // has clients while Today is showing. A search that did not skip the
      // offstage branches would scroll Learn instead.
      await pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);

      await tester.tap(find.text(l10n.tabLearn).last);
      await tester.pumpAndSettle();
      await tester.drag(find.text(l10n.learnTitle), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text(l10n.learnTitle), findsNothing);

      await tester.tap(find.text(l10n.tabToday).last);
      await tester.pumpAndSettle();
      await tester.drag(find.text(todayTop), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Re-tap Today. Today comes back to the top; Learn must not move.
      await tester.tap(find.text(l10n.tabToday).last);
      await tester.pumpAndSettle();
      expect(find.text(todayTop), findsOneWidget);

      await tester.tap(find.text(l10n.tabLearn).last);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.learnTitle),
        findsNothing,
        reason: 'the offstage branch was scrolled too',
      );
    });

    testWidgets('a re-tap on a root that cannot scroll does nothing', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text(await tabLabel()).last);
      await tester.pumpAndSettle();

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(location(), '/today');
    });
  });

  group('full-screen routes sit over the shell', () {
    testWidgets('the tab bar is gone', (tester) async {
      await pumpApp(tester);
      expect(find.byType(AppShell), findsOneWidget);

      router.go('/study', extra: extraFor('/study'));
      await tester.pumpAndSettle();

      expect(find.byType(StudyScreen), findsOneWidget);
      expect(
        find.byType(AppShell),
        findsNothing,
        reason: 'a modal must cover the tab bar, not sit inside a tab',
      );
    });

    testWidgets('every one of them does', (tester) async {
      await pumpApp(tester);

      for (final path in const <String>[
        '/study',
        '/sentences',
        '/day-complete',
        '/grammar-practice',
        '/quiz',
        '/exam/7',
        '/word/uid-haus',
        '/compare/uid-haus',
        '/onboarding/1',
        '/splash',
      ]) {
        router.go(path, extra: extraFor(path));
        await tester.pumpAndSettle();

        // Both halves: a path that matches nothing also renders no shell, and
        // would pass the second check on its own.
        expect(matched(), isTrue, reason: '$path matched no route');
        expect(find.byType(AppShell), findsNothing, reason: path);
      }
    });
  });

  group('the criterion about extra', () {
    testWidgets('an ephemeral argument rides on extra', (tester) async {
      await pumpApp(tester);

      router.go(
        '/study',
        extra: const SessionArgs(
          blocks: <SessionBlock>[
            SessionBlock(SessionBlockKind.revise, <String>['a', 'b', 'c']),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<StudyScreen>(find.byType(StudyScreen)).args.wordUids,
        <String>['a', 'b', 'c'],
      );
    });

    testWidgets('an exam carries its id in the path instead', (tester) async {
      // FR-L12-01 resumes an exam after the app is killed, and `extra` does
      // not survive that — so the attempt has to be reachable from the URL
      // alone. Opening it with nothing but the path is that property.
      await pumpApp(tester, at: '/exam/42');
      expect(find.text('attempt 42'), findsOneWidget);
    });

    test('only the ephemeral routes read extra', () {
      // The rule, checked against the source rather than trusted: a route
      // that reads `extra` and is not one of these three is one whose
      // argument would be gone after process death.
      final source = File('lib/router/routes.dart').readAsStringSync();

      // Each class declaration, and everything up to the next one.
      final declarations = RegExp(r'\nclass (\w+Route) extends GoRouteData')
          .allMatches(source)
          .toList();
      expect(
        declarations,
        hasLength(greaterThan(20)),
        reason: 'the parse found no routes, so the check below proves nothing',
      );

      final reading = <String>{};
      for (var i = 0; i < declarations.length; i++) {
        final from = declarations[i].start;
        final to = i + 1 < declarations.length
            ? declarations[i + 1].start
            : source.length;
        if (source.substring(from, to).contains('state.extra')) {
          reading.add(declarations[i].group(1)!);
        }
      }

      expect(
        reading,
        <String>{'StudyRoute', 'GrammarPracticeRoute', 'QuizRoute'},
        reason:
            'navigation.md: extra is for ephemeral data only. Anything that '
            'must survive process death is keyed by an id in the path.',
      );
    });
  });

  group('a link that matches nothing', () {
    testWidgets('lands on Today, not on a blank screen', (tester) async {
      // A stale notification or a stale home-screen widget. Rendering
      // nothing would leave the learner on a white page with no tab bar and
      // no way back.
      await pumpApp(tester);

      router.go('/nope/not/a/route');
      await tester.pumpAndSettle();

      expect(location(), fallbackLocation);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('so does a half-right one', (tester) async {
      await pumpApp(tester);

      router.go('/learn/step');
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
    });
  });

  testWidgets('a typed route builds its own path', (tester) async {
    // The point of go_router_builder: the path exists in one place, and a
    // caller that goes to the wrong one does not compile.
    await pumpApp(tester);

    const route = LearnStepRoute(code: 'A2.1', tab: StepTab.grammar);
    expect(route.location, '/learn/step/A2.1?tab=grammar');

    expect(const ExamRoute(attemptId: 9).location, '/exam/9');
    expect(const WordRoute(uid: 'uid-haus').location, '/word/uid-haus');
  });
}

class _OneStepDao extends ContentDao {
  _OneStepDao(super.db);

  @override
  Future<List<PlacementWord>> placementPool(String step) async =>
      <PlacementWord>[for (var i = 0; i < 12; i++) wordFor(step, i)];
}

class _FixedLanguages extends Languages {
  _FixedLanguages(this.meaning);

  final MeaningLanguage meaning;

  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() =>
      (meaning: meaning, ui: UiLanguage.english);
}
