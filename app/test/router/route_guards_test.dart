@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// `navigation.md`'s guards — #68.
///
/// Two layers, tested separately: the guards against a real database, and the
/// router against guards it is handed. A test that only did the second would
/// pass with a repository that answered nothing.
void main() {
  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester, {
    required RouteGuards guards,
    String at = '/today',
  }) async {
    router = buildRouter(initialLocation: at, guards: guards);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
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
        extra: const SessionArgs(wordUids: <String>['uid-haus']),
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
      expect(find.text('T1'), findsOneWidget);
    });

    testWidgets('an empty session is no session', (tester) async {
      await pumpApp(tester, guards: guardsWith());

      router.go('/study', extra: const SessionArgs(wordUids: <String>[]));
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
        extra: const SessionArgs(wordUids: <String>['uid-haus']),
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
      expect(find.text('S2'), findsOneWidget);
    });

    testWidgets('and goes to Today once they are', (tester) async {
      // A stale link would otherwise walk them through setup again.
      await pumpApp(tester, guards: guardsWith(enrolled: true));

      router.go('/onboarding/1');
      await tester.pumpAndSettle();

      expect(location(), '/today');
      expect(find.text('T1'), findsOneWidget);
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
        extra: const SessionArgs(wordUids: <String>['uid-haus']),
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
