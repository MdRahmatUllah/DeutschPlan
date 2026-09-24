@TestOn('vm')
library;

import 'package:deutschplan/features/backlog/backlog_screen.dart';
import 'package:deutschplan/features/today/today_screen.dart';

import '../features/today_fixtures.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Cross-tab jumps — #72.
///
/// The behaviour was already right before the helper existed: `go` on a typed
/// nested route builds the whole parent stack in the target branch. What was
/// missing was anything asserting it, which is what this file is.
void main() {
  late GoRouter router;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pumpApp(WidgetTester tester, {String at = '/today'}) async {
    router = buildRouter(initialLocation: at, guards: RouteGuards.permissive());
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: todayStub(),
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

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// Jumps through the helper, from a widget inside the tree.
  Future<void> jump(WidgetTester tester, GoRouteData destination) async {
    final context = tester.element(find.byType(AppShell));
    context.jumpToTab(destination);
    await tester.pumpAndSettle();
  }

  group('the jump itself', () {
    testWidgets('T1 -> L2 switches the tab and opens the step', (tester) async {
      // Today's step chip.
      await pumpApp(tester);
      expect(find.byType(TodayScreen), findsOneWidget);

      await jump(tester, const LearnStepRoute(code: 'A1.1'));

      expect(location(), '/learn/step/A1.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);
      expect(
        find.byType(AppShell),
        findsOneWidget,
        reason: 'it left the shell',
      );
    });

    testWidgets('M1 -> the exam hub', (tester) async {
      // The Me badge, which opens a step on its exams tab.
      await pumpApp(tester, at: '/me');

      await jump(
        tester,
        const LearnStepRoute(code: 'A1.2', tab: StepTab.exams),
      );

      expect(location(), '/learn/step/A1.2?tab=exams');
      expect(
        tester.widget<StepDetailScreen>(find.byType(StepDetailScreen)).tab,
        StepTab.exams,
      );
    });

    testWidgets('T1 -> the grammar card', (tester) async {
      await pumpApp(tester);
      await jump(tester, const GrammarTopicRoute(uid: 'g1'));

      expect(location(), '/learn/grammar/g1');
      expect(find.text('L4'), findsOneWidget);
    });

    testWidgets('and within the same tab it is just a push', (tester) async {
      await pumpApp(tester, at: '/learn');
      await jump(tester, const CategoriesRoute());

      expect(location(), '/learn/categories');
    });
  });

  group('back walks the target tab, not the origin', () {
    /// Every location a back press leads to, until it stops changing.
    Future<List<String>> trail(WidgetTester tester) async {
      final seen = <String>[location()];
      for (var i = 0; i < 5; i++) {
        await pressBack(tester);
        if (location() == seen.last) break;
        seen.add(location());
      }
      return seen;
    }

    testWidgets('a step walks back through Learn', (tester) async {
      // The criterion: back must not jump straight to Today, and must not
      // walk Today's parents.
      await pumpApp(tester);
      await jump(tester, const LearnStepRoute(code: 'A1.1'));

      expect(await trail(tester), <String>[
        '/learn/step/A1.1',
        '/learn',
        '/today',
      ]);
    });

    testWidgets('a grammar topic walks through the library', (tester) async {
      await pumpApp(tester);
      await jump(tester, const GrammarTopicRoute(uid: 'g1'));

      expect(await trail(tester), <String>[
        '/learn/grammar/g1',
        '/learn/grammar',
        '/learn',
        '/today',
      ]);
    });

    testWidgets('a deep route in another tab walks all of it', (tester) async {
      await pumpApp(tester);
      await jump(tester, const ReminderSettingsRoute());

      expect(await trail(tester), <String>[
        '/me/settings/reminder',
        '/me/settings',
        '/me',
        '/today',
      ]);
    });

    testWidgets('the origin tab keeps what it had', (tester) async {
      // A jump is not a reset: coming back to Today finds the backlog the
      // learner had open, not /today.
      await pumpApp(tester, at: '/today/backlog');
      await jump(tester, const LearnRoute());
      expect(find.byType(LearnScreen), findsOneWidget);

      await tester.tap(find.text(l10n.tabToday).last);
      await tester.pumpAndSettle();

      expect(
        find.byType(BacklogScreen),
        findsOneWidget,
        reason: 'Today was reset',
      );
    });
  });

  group('what counts as a tab destination', () {
    test('the four roots and anything under them', () {
      for (final location in const <String>[
        '/today',
        '/today/backlog',
        '/learn',
        '/learn/step/A1.1',
        '/learn/step/A1.1?tab=exams',
        '/search/add/3',
        '/me/settings/reminder',
      ]) {
        expect(isTabDestination(location), isTrue, reason: location);
      }
    });

    test('and nothing else', () {
      for (final location in const <String>[
        '/study',
        '/quiz',
        '/exam/7',
        '/word/uid-haus',
        '/onboarding/1',
        '/splash',
      ]) {
        expect(isTabDestination(location), isFalse, reason: location);
      }
    });

    test('a prefix is not a parent', () {
      // `startsWith('/learn')` would call this one a tab route.
      expect(isTabDestination('/learnt'), isFalse);
      expect(isTabDestination('/todayish'), isFalse);
    });

    testWidgets('a full-screen route is refused', (tester) async {
      // Not a cross-tab jump: it covers the tab bar and closing it returns to
      // the opener, which is the opposite of what the helper promises.
      await pumpApp(tester);
      final context = tester.element(find.byType(AppShell));

      expect(
        () => context.jumpToTab(const ExamRoute(attemptId: 7)),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
