@TestOn('vm')
library;

import 'package:deutschplan/features/today/today_screen.dart';

import '../features/today_fixtures.dart';

import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/onboarding/onboarding_meaning_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:deutschplan/features/onboarding/onboarding_welcome_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_voice_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';
import 'package:deutschplan/domain/placement.dart';

import '../domain/placement_test.dart' show wordFor;

import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_pace_page.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransition;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// `navigation.md`'s guards — #68.
///
/// Two layers, tested separately: the guards against a real database, and the
/// router against guards it is handed. A test that only did the second would
/// pass with a repository that answered nothing.
void main() {
  late GoRouter router;

  // S2's finish, recorded rather than run: the commit and the plan are
  // setup_flow_test's, against SQLite. Here it is where the finish goes.
  late List<String> flowLog;
  var finishSucceeds = true;

  Future<void> pumpApp(
    WidgetTester tester, {
    required RouteGuards guards,
    String at = '/today',
  }) async {
    flowLog = <String>[];
    router = buildRouter(initialLocation: at, guards: guards);
    addTearDown(router.dispose);

    // S2's pages read settings (page 2 writes the languages), so the router
    // needs a scope to render them in. Nothing else here reads a provider.
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...todayStub(),
          settingsProvider.overrideWithValue(settings),
          meaningSampleProvider.overrideWith((ref) async => null),
          courseStepsProvider.overrideWith(
            (ref) async => <CourseStep>[
              (code: 'A1.1', levelCode: 'A1', wordCount: 637),
              (code: 'A1.2', levelCode: 'A1', wordCount: 679),
              (code: 'A2.1', levelCode: 'A2', wordCount: 540),
              (code: 'A2.2', levelCode: 'A2', wordCount: 498),
            ],
          ),
          setupFlowProvider.overrideWith(
            () => _RecordingFlow(flowLog, succeed: finishSucceeds),
          ),
          contentDaoProvider.overrideWithValue(_PoolDao(db)),
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

  RouteGuards guardsWith({bool attemptExists = true, bool enrolled = false}) =>
      RouteGuards(
        hasExamAttempt: (_) async => attemptExists,
        isEnrolled: () async => enrolled,
      );

  group('/exam/* needs a real attempt', () {
    testWidgets('an attempt that exists opens', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go('/exam/7');
      await tester.pumpAndSettle();

      expect(location(), '/exam/7');
      expect(find.text('attempt 7'), findsOneWidget);
    });

    testWidgets('one that does not goes to the Learn tab', (tester) async {
      // Not a blank runner and not a crash: an id from a stale notification,
      // or from a process restored after a data reset, is a wrong turn.
      await pumpApp(tester, guards: guardsWith(attemptExists: false));

      router.go('/exam/7');
      await tester.pumpAndSettle();

      expect(location(), examFallback);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('L1'), findsOneWidget);
    });

    testWidgets('an id that is not a number does too', (tester) async {
      // Asserted on `examFallback` rather than on "some shell": an unparsable
      // id could also be the typed route refusing to build and falling
      // through to `onException`, which lands on `/today`. The two fallbacks
      // differing is what tells them apart, and this is the guard.
      await pumpApp(tester, guards: guardsWith());

      router.go('/exam/nonsense');
      await tester.pumpAndSettle();

      expect(location(), examFallback);
      expect(location(), isNot(fallbackLocation));
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('it is the guard deciding, not the route being missing', (
      tester,
    ) async {
      // The same path, the same router, one answer each way.
      await pumpApp(tester, guards: guardsWith());
      router.go('/exam/7');
      await tester.pumpAndSettle();
      expect(find.text('L12'), findsOneWidget);
    });
  });

  group('/study needs a session', () {
    testWidgets('with cards it opens', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/study',
        extra: const SessionArgs(
          blocks: <SessionBlock>[
            SessionBlock(SessionBlockKind.revise, <String>['uid-haus']),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(location(), '/study');
      expect(find.text('T2'), findsOneWidget);
    });

    testWidgets('without one it goes to Today', (tester) async {
      // `extra` does not survive process death, so a restored `/study` has
      // nothing to show. Today is "your session ended", not a blank card.
      await pumpApp(tester, guards: guardsWith());

      router.go('/study');
      await tester.pumpAndSettle();

      expect(location(), studyFallback);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('an empty session is no session', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/study',
        extra: const SessionArgs(
          blocks: <SessionBlock>[
            SessionBlock(SessionBlockKind.revise, <String>[]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(location(), studyFallback);
    });

    testWidgets('something that is not a session is no session', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith());

      router.go('/study', extra: 'not a SessionArgs');
      await tester.pumpAndSettle();

      expect(location(), studyFallback);
    });
  });

  group('the other routes that carry their work in extra', () {
    testWidgets('a quiz with questions opens', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/quiz',
        extra: const QuizArgs(direction: 'deEn', source: 'allLearned', seed: 1),
      );
      await tester.pumpAndSettle();

      expect(location(), '/quiz');
      expect(find.text('L8'), findsOneWidget);
    });

    testWidgets('a restored quiz does not', (tester) async {
      // Same failure as `/study`: `extra` is gone after process death, and
      // the screen would open with no questions in it.
      await pumpApp(tester, guards: guardsWith());

      router.go('/quiz');
      await tester.pumpAndSettle();

      expect(location(), '/learn');
    });

    testWidgets('a grammar practice with topics opens', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/grammar-practice',
        extra: const GrammarPracticeArgs(topicUids: <String>['g1']),
      );
      await tester.pumpAndSettle();

      expect(location(), '/grammar-practice');
    });

    testWidgets('one with no topics does not', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/grammar-practice',
        extra: const GrammarPracticeArgs(topicUids: <String>[]),
      );
      await tester.pumpAndSettle();

      expect(location(), '/learn');
    });

    testWidgets('the wrong kind of argument is no argument', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go(
        '/quiz',
        extra: const SessionArgs(
          blocks: <SessionBlock>[
            SessionBlock(SessionBlockKind.revise, <String>['uid-haus']),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(location(), '/learn');
    });

    test('every route that reads extra is guarded', () {
      // Read out of the source, not restated: a route added later that
      // carries its work in `extra` and is not in the map has the same
      // failure and nothing to catch it. A hardcoded list here would only
      // ever agree with itself.
      final source = File('lib/router/routes.dart').readAsStringSync();
      final declarations = RegExp(r"\n@TypedGoRoute<(\w+)>\(path: '([^']+)'\)")
          .allMatches(source)
          .toList();
      expect(
        declarations,
        hasLength(greaterThan(5)),
        reason: 'the parse found no routes, so this proves nothing',
      );

      final reading = <String>{};
      for (var i = 0; i < declarations.length; i++) {
        final from = declarations[i].start;
        final to = i + 1 < declarations.length
            ? declarations[i + 1].start
            : source.length;
        if (source.substring(from, to).contains('state.extra')) {
          reading.add(declarations[i].group(2)!);
        }
      }

      expect(needsSession.keys.toSet(), reading);
    });
  });

  group('/onboarding/* is for learners who have not started', () {
    testWidgets('it opens when nobody is enrolled', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go('/onboarding/1');
      await tester.pumpAndSettle();

      expect(location(), '/onboarding/1');
      expect(find.byType(OnboardingWelcomePage), findsOneWidget);
    });

    testWidgets('and goes to Today once they are', (tester) async {
      // A stale link would otherwise walk them through setup again.
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      router.go('/onboarding/1');
      await tester.pumpAndSettle();

      expect(location(), '/today');
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('placement too', (tester) async {
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      router.go('/onboarding/placement');
      await tester.pumpAndSettle();

      expect(location(), '/today');
    });

    testWidgets('as the launch location, not just as a link', (tester) async {
      // A redirect that only fired on a `go` would let a restored process
      // open onboarding on a phone that is already set up.
      await pumpApp(
        tester,
        guards: guardsWith(enrolled: true),
        at: '/onboarding/1',
      );

      expect(location(), '/today');
    });
  });

  group('the five pages of S2', () {
    // #87: "Horizontal page slide; system back / edge swipe goes to the
    // previous page." Against the real router, because both halves are the
    // route's doing and a widget test of the page alone would pass without
    // either.
    testWidgets('a bad page number starts setup rather than a blank screen', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/99');

      expect(find.byType(OnboardingWelcomePage), findsOneWidget);
    });

    testWidgets('starting moves on, and system back returns', (tester) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/1');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingWelcomePage)),
      );

      // What is on screen rather than `location()`: a `push` leaves the
      // reported URL alone unless `optionURLReflectsImperativeAPIs` is set.
      await tester.tap(find.text(l10n.onboardingWelcomeStart));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingMeaningPage), findsOneWidget);
      expect(find.byType(OnboardingWelcomePage), findsNothing);

      // Android back. With `go` there is nothing under page 2, the press is
      // not handled, and the system closes the app instead.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.byType(OnboardingWelcomePage), findsOneWidget);
      expect(find.byType(OnboardingMeaningPage), findsNothing);
    });

    testWidgets('the Back button on page 2 returns the same way', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/1');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingWelcomePage)),
      );

      await tester.tap(find.text(l10n.onboardingWelcomeStart));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.back));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingWelcomePage), findsOneWidget);
      expect(find.byType(OnboardingMeaningPage), findsNothing);
    });

    testWidgets('and opened directly, Back still has somewhere to go', (
      tester,
    ) async {
      // A deep link or restart setup lands on a page with nothing under it.
      // A pop there would do nothing; Back goes to the previous page instead.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/2');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingMeaningPage)),
      );

      await tester.tap(find.text(l10n.back));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingWelcomePage), findsOneWidget);
      expect(location(), '/onboarding/1');
    });

    testWidgets('page 3 opens S3, and takes back what it suggests', (
      tester,
    ) async {
      // #89: "Link pushes S3 and returns with the suggested step
      // pre-selected." S3 is #93's; here it is popped with a result the way
      // it will pop itself.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/3');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingStartPage)),
      );

      await tester.tap(find.text(l10n.onboardingPlacementLink));
      await tester.pumpAndSettle();
      expect(find.byType(PlacementScreen), findsOneWidget);

      router.pop('A2.1');
      await tester.pumpAndSettle();

      final chosen = find.ancestor(
        of: find.text('A2.1'),
        matching: find.byType(DpSurface),
      );
      expect(tester.widget<DpSurface>(chosen).selected, isTrue);
    });

    testWidgets('FR-S3-03 its result pre-selects the step on page 3', (
      tester,
    ) async {
      // #94: the check ends on its result, and "Use <step>" is the way the
      // suggestion reaches page 3. Every answer right, so it climbs off A1.1.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/3');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingStartPage)),
      );
      await tester.tap(find.text(l10n.onboardingPlacementLink));
      await tester.pumpAndSettle();

      PlacementScreenState check() =>
          tester.state<PlacementScreenState>(find.byType(PlacementScreen));
      while (check().currentResult == null) {
        final item = check().currentItem!;
        await tester.tap(
          find
              .descendant(
                of: find.byType(PlacementScreen),
                matching: find.text(item.options[item.answer]),
              )
              .last,
        );
        await tester.pump();
        await tester.tap(find.text(l10n.placementNext));
        await tester.pumpAndSettle();
      }
      final step = check().currentResult!.step;
      expect(step, isNot('A1.1'));

      await tester.tap(find.text(l10n.placementUse(step)));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingStartPage), findsOneWidget);
      final chosen = find.ancestor(
        of: find.text(step),
        matching: find.byType(DpSurface),
      );
      expect(tester.widget<DpSurface>(chosen).selected, isTrue);
    });

    testWidgets('S3 opened directly closes to page 3, not to nothing', (
      tester,
    ) async {
      // A deep link to the check has no page 3 under it to pop back to.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/placement');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(PlacementScreen)),
      );

      await tester.tap(find.bySemanticsLabel(l10n.placementClose));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(OnboardingStartPage), findsOneWidget);
    });

    testWidgets("page 4's estimate is for the step page 3 picked", (
      tester,
    ) async {
      // One draft across the routes: A2.1's 540 words at 7 a day is 78 days,
      // and page 4 can only know that if page 3's pick reached it.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/3');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingStartPage)),
      );

      await tester.tap(find.text('A2.1'));
      await tester.pump();
      await tester.tap(find.text(l10n.continueAction));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPacePage), findsOneWidget);
      expect(
        find.text(l10n.onboardingPaceEstimate(78, 'A2.1', 7)),
        findsOneWidget,
      );
    });

    testWidgets('FR-S2-03 Start learning finishes and opens Today', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/5');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingVoicePage)),
      );

      await tester.tap(find.text(l10n.onboardingStartLearning));
      await tester.pumpAndSettle();

      expect(flowLog, <String>['finish']);
      expect(location(), '/today');
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('and clears the draft once Today is showing', (tester) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/5');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingVoicePage)),
      );
      container.read(onboardingProvider.notifier).chooseStep('A2.1');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingVoicePage)),
      );

      await tester.tap(find.text(l10n.onboardingStartLearning));
      await tester.pumpAndSettle();

      expect(container.read(onboardingProvider).step, 'A1.1');
    });

    testWidgets('FR-S2-01 Skip finishes from the page it is on', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/3');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingStartPage)),
      );

      await tester.tap(find.text(l10n.skip));
      await tester.pumpAndSettle();

      expect(flowLog, <String>['finish from 3']);
      expect(location(), '/today');
    });

    testWidgets('a finish that fails stays put and says so', (tester) async {
      finishSucceeds = false;
      addTearDown(() => finishSucceeds = true);
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/5');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingVoicePage)),
      );

      await tester.tap(find.text(l10n.onboardingStartLearning));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingVoicePage), findsOneWidget);
      expect(find.text(l10n.onboardingFinishFailed), findsOneWidget);
    });

    testWidgets('and the pages slide sideways, with the edge swipe', (
      tester,
    ) async {
      // The test platform is Android, whose default is a zoom that neither
      // slides nor swipes. `CupertinoPageTransition` is what does both.
      await pumpApp(tester, guards: guardsWith(), at: '/onboarding/1');

      expect(find.byType(CupertinoPageTransition), findsOneWidget);
    });
  });

  group('restart setup', () {
    testWidgets('lets an enrolled learner back in, on page 2', (tester) async {
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      await OnboardingRoute.restartSetup(tester.element(find.byType(AppShell)));
      await tester.pumpAndSettle();

      // Pre-filled first, then opened — page 1 is not part of restart.
      expect(flowLog, <String>['restart']);
      expect(find.byType(OnboardingMeaningPage), findsOneWidget);
      expect(find.byType(OnboardingWelcomePage), findsNothing);
    });

    testWidgets('while a plain link to setup still goes to Today', (
      tester,
    ) async {
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      router.go('/onboarding/2');
      await tester.pumpAndSettle();
      expect(location(), '/today');

      router.go('/onboarding/2?restart=true');
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingMeaningPage), findsOneWidget);
    });

    testWidgets('and carries on through every page it pushes', (tester) async {
      await pumpApp(tester, guards: guardsWith(enrolled: true));
      await OnboardingRoute.restartSetup(tester.element(find.byType(AppShell)));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingMeaningPage)),
      );

      // Without `restart` on the next page's link, the guard would send an
      // enrolled learner back to Today halfway through.
      await tester.tap(find.text(l10n.continueAction));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingStartPage), findsOneWidget);
    });

    testWidgets('and its placement link is not sent to Today', (tester) async {
      // The learner is enrolled, so a plain link to S3 would be redirected.
      await pumpApp(
        tester,
        guards: guardsWith(enrolled: true),
        at: '/onboarding/3?restart=true',
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingStartPage)),
      );

      await tester.tap(find.text(l10n.onboardingPlacementLink));
      await tester.pumpAndSettle();

      expect(find.byType(PlacementScreen), findsOneWidget);
    });

    testWidgets("Back from its first page leaves setup", (tester) async {
      await pumpApp(
        tester,
        guards: guardsWith(enrolled: true),
        at: '/onboarding/2?restart=true',
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingMeaningPage)),
      );

      // Opened directly, there is nothing under it — and page 1 is not
      // somewhere restart setup goes.
      await tester.tap(find.text(l10n.back));
      await tester.pumpAndSettle();

      expect(location(), '/today');
    });
  });

  group('an unguarded route is untouched', () {
    testWidgets('every tab root opens', (tester) async {
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      for (final path in const <String>[
        '/today',
        '/learn',
        '/search',
        '/me',
        '/learn/grammar',
        '/me/settings',
        '/word/uid-haus',
        '/sentences',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(location(), path, reason: '$path was redirected');
      }
    });
  });

  group('closing a modal returns to the opener', () {
    testWidgets('and to the tab it was opened from', (tester) async {
      // `navigation.md`: "Modals never switch tabs; closing returns to the
      // opener." The modal is on the root navigator, so what it returns to is
      // whatever branch the shell was showing.
      await pumpApp(tester, guards: guardsWith(), at: '/me/settings');
      expect(find.text('M3'), findsOneWidget);

      router.push(
        '/study',
        extra: const SessionArgs(
          blocks: <SessionBlock>[
            SessionBlock(SessionBlockKind.revise, <String>['uid-haus']),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('T2'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('M3'), findsOneWidget, reason: 'it lost the opener');
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a modal does not switch the tab under it', (tester) async {
      await pumpApp(tester, guards: guardsWith(), at: '/search');

      router.push('/sentences');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('R1'), findsOneWidget);
    });
  });

  group('the real guards, against a real database', () {
    late AppDatabase db;
    late RouteGuards guards;

    setUp(() {
      db = AppDatabase.memory();
      guards = RouteGuards.of(
        exams: ExamRepository(db),
        plan: PlanRepository(db),
      );
    });

    tearDown(() => db.close());

    test('an attempt that was never created does not exist', () async {
      expect(await guards.hasExamAttempt(1), isFalse);
    });

    test('one that was does', () async {
      final id = await ExamRepository(db).begin(
        sublevelCode: 'A1.1',
        seed: 1,
        startedAt: '2026-03-04T09:00:00Z',
        questions: const <ExamQuestion>[
          ExamQuestion(ord: 1, section: 'vocabulary', prompt: 'das Haus'),
        ],
      );

      expect(await guards.hasExamAttempt(id), isTrue);
      expect(await guards.hasExamAttempt(id + 1), isFalse);
    });

    test('a phone with no enrollment is not enrolled', () async {
      expect(await guards.isEnrolled(), isFalse);
    });

    test('one with a step is', () async {
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A1.1', '2026-01-05', 7, 127)",
      );

      expect(await guards.isEnrolled(), isTrue);
    });

    test('a finished step still counts', () async {
      // Someone between steps is not a new learner, and onboarding would
      // re-enrol them.
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask, completed_on) VALUES ('A1.1', '2026-01-05', 7, 127, "
        "'2026-02-01')",
      );

      expect(await guards.isEnrolled(), isTrue);
    });
  });

  test('the permissive default refuses nothing that exists', () async {
    // What a router built with no database falls back to. Refusing every
    // route would be a worse answer than allowing them.
    final guards = RouteGuards.permissive();
    expect(await guards.hasExamAttempt(1), isTrue);
    expect(await guards.isEnrolled(), isFalse);
  });
}

class _RecordingFlow extends SetupFlow {
  _RecordingFlow(this.log, {required this.succeed});

  final List<String> log;
  final bool succeed;

  @override
  SetupStatus build() => SetupStatus.idle;

  @override
  Future<bool> finish({OnboardingPage? skippingFrom}) async {
    log.add(
      skippingFrom == null ? 'finish' : 'finish from ${skippingFrom.step}',
    );
    if (!succeed) state = SetupStatus.failed;
    return succeed;
  }

  @override
  Future<void> beginRestart() async => log.add('restart');
}

class _PoolDao extends ContentDao {
  _PoolDao(super.db);

  @override
  Future<List<PlacementWord>> placementPool(String step) async =>
      <PlacementWord>[for (var i = 0; i < 12; i++) wordFor(step, i)];
}
