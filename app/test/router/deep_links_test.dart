@TestOn('vm')
library;

import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:deutschplan/features/sentences/sentences_screen.dart';
import 'package:deutschplan/features/today/today_screen.dart';

import '../features/today_fixtures.dart';
import '../services/fake_tts.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/deep_links.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/services.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Deep links — #70.
///
/// Two layers. `resolveDeepLink` is pure and takes the bulk of the cases; the
/// widget tests drive the real platform channel, because a resolver that is
/// right and never called is the failure worth catching.
void main() {
  group('resolveDeepLink', () {
    test('the four shapes navigation.md names', () {
      expect(resolveDeepLink(Uri.parse('deutschplan://today')), '/today');
      expect(
        resolveDeepLink(Uri.parse('deutschplan://learn/A2.1')),
        '/learn/step/A2.1',
      );
      expect(
        resolveDeepLink(Uri.parse('deutschplan://word/uid-haus')),
        '/word/uid-haus',
      );
      expect(
        resolveDeepLink(Uri.parse('deutschplan://exam/A1.2')),
        '/learn/step/A1.2?tab=exams',
      );
    });

    test('an exam link opens the hub, not the runner', () {
      // `deutschplan://exam/A1.2` names a *step*; `/exam/:attemptId` in the
      // route table is the runner for one attempt. Passing the link through
      // unchanged would open an exam whose attempt id is "A1.2".
      final resolved = resolveDeepLink(Uri.parse('deutschplan://exam/A1.2'));
      expect(resolved, isNot(startsWith('/exam/')));
      expect(resolved, contains('tab=exams'));
    });

    test('a trailing slash is the same link', () {
      // Flutter hands `deutschplan://today` over as `deutschplan://today/`.
      expect(resolveDeepLink(Uri.parse('deutschplan://today/')), '/today');
    });

    group('?speak=1', () {
      test('is carried through', () {
        expect(
          resolveDeepLink(Uri.parse('deutschplan://word/uid-haus?speak=1')),
          '/word/uid-haus?speak=1',
        );
      });

      test('and is not invented when it is absent', () {
        expect(
          resolveDeepLink(Uri.parse('deutschplan://word/uid-haus')),
          isNot(contains('speak')),
        );
      });

      test('the typed route carries it, not just the URL', () {
        // `WordRoute.build` reads its own field. A route that declared the
        // parameter and then read the raw location would have two answers to
        // the same question.
        expect(
          const WordRoute(uid: 'uid-haus', speak: speakOn).location,
          '/word/uid-haus?speak=1',
        );
        expect(
          const WordRoute(uid: 'uid-haus').location,
          isNot(contains('speak')),
        );
      });

      test('only 1 asks for speech', () {
        // A truthy-string reading would make `?speak=0` play, which is the
        // one value someone writing that query expects to be silent.
        expect(wantsSpeech(Uri.parse('/word/x?speak=1')), isTrue);
        expect(wantsSpeech(Uri.parse('/word/x?speak=0')), isFalse);
        expect(wantsSpeech(Uri.parse('/word/x?speak=true')), isFalse);
        expect(wantsSpeech(Uri.parse('/word/x')), isFalse);
      });
    });

    group('anything else lands on Today', () {
      test('an unknown host', () {
        expect(
          resolveDeepLink(Uri.parse('deutschplan://nonsense')),
          fallbackLocation,
        );
      });

      test('a shape from an older build', () {
        expect(
          resolveDeepLink(Uri.parse('deutschplan://word')),
          fallbackLocation,
        );
        expect(
          resolveDeepLink(Uri.parse('deutschplan://word/a/b/c')),
          fallbackLocation,
        );
      });

      test('nothing at all', () {
        expect(resolveDeepLink(Uri.parse('deutschplan://')), fallbackLocation);
      });
    });

    test('a uid with awkward characters survives', () {
      // uids are hashes today, but a link is a URL and the encoding has to be
      // right whatever ends up in one.
      final resolved = resolveDeepLink(
        Uri.parse('deutschplan://word/${Uri.encodeComponent('a/b c')}'),
      );
      expect(Uri.parse(resolved).pathSegments, <String>['word', 'a/b c']);
    });
  });

  group('through the real router', () {
    late GoRouter router;

    Future<void> pumpApp(
      WidgetTester tester, {
      List<Override> extra = const <Override>[],
    }) async {
      router = buildRouter(guards: RouteGuards.permissive());
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[...todayStub(), ...extra],
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

    /// Delivers a link the way the platform does, through the navigation
    /// channel — not by calling `go` with an already-resolved path.
    Future<void> openLink(WidgetTester tester, String link) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', <String, dynamic>{
            'location': link,
            'state': null,
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('the notification link opens Today', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://learn/A2.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);

      await openLink(tester, 'deutschplan://today');

      expect(location(), '/today');
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('a step link opens the step', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://learn/A2.1');

      expect(location(), '/learn/step/A2.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a word link opens the word', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus');

      expect(location(), '/word/uid-haus');
      // FR-W1 presentation: a deep link is the full page.
      final page = tester.widget<WordDetailScreen>(
        find.byType(WordDetailScreen),
      );
      expect(page.uid, 'uid-haus');
      expect(page.speak, isFalse);
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
    });

    testWidgets('the widget"s Pronounce link asks for speech', (tester) async {
      // FR-X1-02: "the app plays on open". The route has to see the query,
      // not just keep it in the URL.
      late SettingsRepository settings;
      await tester.runAsync(() async {
        final db = AppDatabase.memory();
        settings = SettingsRepository(db);
        await settings.load();
        addTearDown(() async {
          await settings.dispose();
          await db.close();
        });
      });
      final tts = FakeTts();
      await pumpApp(
        tester,
        extra: <Override>[
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(tts),
        ],
      );
      await openLink(tester, 'deutschplan://word/uid-haus?speak=1');

      expect(location(), '/word/uid-haus?speak=1');
      expect(
        tester.widget<WordDetailScreen>(find.byType(WordDetailScreen)).speak,
        isTrue,
      );
      // Once, with its article, and not again as the page settles.
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['die Straße']);
    });

    testWidgets('a word link opened cold: back goes to Today, not out of '
        'the app', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus');
      expect(location(), '/word/uid-haus');

      await tester.tap(find.byType(AdaptiveBackButton));
      await tester.pumpAndSettle();
      expect(location(), '/today');

      await openLink(tester, 'deutschplan://word/uid-haus');
      // Android's back, which a lone page would otherwise answer by leaving.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(location(), '/today');
    });

    testWidgets('the same link without it does not', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus');

      expect(
        tester.widget<WordDetailScreen>(find.byType(WordDetailScreen)).speak,
        isFalse,
      );
    });

    testWidgets('an exam link opens the step"s exams tab', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://exam/A1.2');

      expect(location(), '/learn/step/A1.2?tab=exams');
      expect(find.byType(StepDetailScreen), findsOneWidget);
      expect(
        tester.widget<StepDetailScreen>(find.byType(StepDetailScreen)).tab,
        StepTab.exams,
      );
    });

    testWidgets('an unknown link lands on Today, not on an error', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://nonsense/from/an/old/build');

      expect(location(), fallbackLocation);
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a link does not take over a running exam', (tester) async {
      // FR-L12-04 makes leaving an exam a decision, with a dialog and an
      // abandoned attempt. A `go` is not a pop, so #69's `canPop: false`
      // never sees a link — and the reminder firing at 19:30 while the
      // learner is mid-exam is an ordinary sequence.
      router = buildRouter(
        initialLocation: '/exam/7',
        guards: RouteGuards.permissive(),
      );
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
      expect(find.byType(ExamRunnerScreen), findsOneWidget);

      await openLink(tester, 'deutschplan://today');

      expect(location(), '/exam/7');
      expect(find.byType(ExamRunnerScreen), findsOneWidget);
    });

    testWidgets('and works again once the exam is done', (tester) async {
      // Dropped, not queued — but not disabled either.
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://today');
      expect(location(), '/today');
    });

    testWidgets('only the exam is protected', (tester) async {
      // A link interrupting a study session or a quiz is fine: neither is
      // timed, and both are resumable.
      await pumpApp(tester);
      router.go('/sentences');
      await tester.pumpAndSettle();
      expect(find.byType(SentencesScreen), findsOneWidget);

      await openLink(tester, 'deutschplan://today');
      expect(location(), '/today');
    });

    testWidgets('a link still meets the guards', (tester) async {
      // Resolving is not a way around them: the resolved location goes round
      // again and is checked like any other navigation.
      router = buildRouter(
        guards: RouteGuards(
          hasExamAttempt: (_) async => true,
          isEnrolled: () async => true,
        ),
      );
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

      await openLink(tester, 'deutschplan://today');
      expect(location(), '/today');
    });
  });

  group('the platform registrations', () {
    test('Android declares the scheme', () {
      // The Dart side cannot receive a link the OS never delivers.
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android:scheme="$deepLinkScheme"'));
      expect(
        manifest,
        contains('android.intent.category.BROWSABLE'),
        reason: 'without BROWSABLE the widget intent does not reach the app',
      );
      expect(manifest, contains('android.intent.action.VIEW'));
    });

    test('iOS declares the scheme', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('CFBundleURLSchemes'));
      expect(plist, contains('<string>$deepLinkScheme</string>'));
    });

    test('both name the same scheme the resolver answers to', () {
      // Three places, one string. A rename in one of them would be a link
      // the OS delivers and the app throws away, or the reverse.
      expect(deepLinkScheme, 'deutschplan');

      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(manifest, contains(deepLinkScheme));
      expect(plist, contains(deepLinkScheme));
      expect(resolveDeepLink(Uri.parse('$deepLinkScheme://today')), '/today');
    });
  });
}
