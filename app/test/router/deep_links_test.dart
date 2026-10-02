@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/documents/doc_import_screen.dart';
import 'package:sogda/features/exam/exam_runner_screen.dart';
import 'package:sogda/features/learn/step_detail_screen.dart';
import 'package:sogda/features/sentences/sentences_screen.dart';
import 'package:sogda/features/today/today_screen.dart';
import 'package:sogda/features/words/word_detail_screen.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/router/app_router.dart';
import 'package:sogda/router/app_shell.dart';
import 'package:sogda/router/deep_links.dart';
import 'package:sogda/router/route_guards.dart';
import 'package:sogda/router/routes.dart';
import 'package:sogda/services/shared_text.dart';

import '../features/today_fixtures.dart';
import '../services/fake_tts.dart';

/// Deep links — #70.
///
/// Two layers. `resolveDeepLink` is pure and takes the bulk of the cases; the
/// widget tests drive the real platform channel, because a resolver that is
/// right and never called is the failure worth catching.
void main() {
  group('resolveDeepLink', () {
    test('the four shapes navigation.md names', () {
      expect(resolveDeepLink(Uri.parse('sogda://today')), '/today');
      expect(
        resolveDeepLink(Uri.parse('sogda://learn/A2.1')),
        '/learn/step/A2.1',
      );
      expect(
        resolveDeepLink(Uri.parse('sogda://word/uid-haus')),
        '/word/uid-haus',
      );
      expect(
        resolveDeepLink(Uri.parse('sogda://exam/A1.2')),
        '/learn/step/A1.2?tab=exams',
      );
    });

    test('#1227 the share link opens D1, without the text, which stays '
        'out of links', () {
      expect(resolveDeepLink(Uri.parse('sogda://import')), shareLocation);
      expect(shareLocation, const DocImportRoute().location);
      expect(numberedArrival(Uri.parse(shareLocation)), isTrue);
      expect(numberedArrival(Uri.parse('/search')), isFalse);
    });

    test('an exam link opens the hub, not the runner', () {
      // `sogda://exam/A1.2` names a *step*; `/exam/:attemptId` in the
      // route table is the runner for one attempt. Passing the link through
      // unchanged would open an exam whose attempt id is "A1.2".
      final resolved = resolveDeepLink(Uri.parse('sogda://exam/A1.2'));
      expect(resolved, isNot(startsWith('/exam/')));
      expect(resolved, contains('tab=exams'));
    });

    test('a trailing slash is the same link', () {
      // Flutter hands `sogda://today` over as `sogda://today/`.
      expect(resolveDeepLink(Uri.parse('sogda://today/')), '/today');
    });

    group('?speak=1', () {
      test('is carried through', () {
        expect(
          resolveDeepLink(Uri.parse('sogda://word/uid-haus?speak=1')),
          '/word/uid-haus?speak=1',
        );
      });

      test('and is not invented when it is absent', () {
        expect(
          resolveDeepLink(Uri.parse('sogda://word/uid-haus')),
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
          resolveDeepLink(Uri.parse('sogda://nonsense')),
          fallbackLocation,
        );
      });

      test('a shape from an older build', () {
        expect(resolveDeepLink(Uri.parse('sogda://word')), fallbackLocation);
        expect(
          resolveDeepLink(Uri.parse('sogda://word/a/b/c')),
          fallbackLocation,
        );
      });

      test('nothing at all', () {
        expect(resolveDeepLink(Uri.parse('sogda://')), fallbackLocation);
      });
    });

    test('a uid with awkward characters survives', () {
      // uids are hashes today, but a link is a URL and the encoding has to be
      // right whatever ends up in one.
      final resolved = resolveDeepLink(
        Uri.parse('sogda://word/${Uri.encodeComponent('a/b c')}'),
      );
      expect(Uri.parse(resolved).pathSegments, <String>['word', 'a/b c']);
    });
  });

  group('through the real router', () {
    late GoRouter router;

    // A learner who has set up: with nobody enrolled, a link opens setup
    // (#674), which its own group tests.
    final enrolled = RouteGuards(
      hasExamAttempt: (_) async => true,
      isEnrolled: () async => true,
    );

    Future<void> pumpApp(
      WidgetTester tester, {
      List<Override> extra = const <Override>[],
      RouteGuards? guards,
    }) async {
      router = buildRouter(guards: guards ?? enrolled);
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
      await openLink(tester, 'sogda://learn/A2.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);

      await openLink(tester, 'sogda://today');

      expect(location(), '/today');
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('a step link opens the step', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://learn/A2.1');

      expect(location(), '/learn/step/A2.1');
      expect(find.byType(StepDetailScreen), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a word link opens the word', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://word/uid-haus');

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
          fakeVoice(tts),
        ],
      );
      await openLink(tester, 'sogda://word/uid-haus?speak=1');

      expect(location(), '/word/uid-haus?speak=1&arrival=1');
      expect(
        tester.widget<WordDetailScreen>(find.byType(WordDetailScreen)).speak,
        isTrue,
      );
      // Once, with its article, and not again as the page settles.
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['die Straße']);
    });

    testWidgets('FR-X1-02 #442 Pronounce speaks on the word already open, '
        'and again on a second Pronounce', (tester) async {
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
          fakeVoice(tts),
        ],
      );
      // agent-3's steps: the widget's word opens W1, then *Pronounce*.
      await openLink(tester, 'sogda://word/uid-haus');
      expect(tts.spoken, isEmpty);
      await openLink(tester, 'sogda://word/uid-haus?speak=1');
      expect(tts.spoken, <String>['die Straße']);

      // The same link again: a new arrival, so it speaks again.
      await openLink(tester, 'sogda://word/uid-haus?speak=1');
      expect(location(), '/word/uid-haus?speak=1&arrival=2');
      expect(tts.spoken, <String>['die Straße', 'die Straße']);
      expect(find.byType(WordDetailScreen), findsOneWidget);
    });

    testWidgets('FR-S1-04 a word link opened cold: back goes to Today, not '
        'out of the app', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://word/uid-haus');
      expect(location(), '/word/uid-haus');

      await tester.tap(find.byType(AdaptiveBackButton));
      await tester.pumpAndSettle();
      expect(location(), '/today');

      await openLink(tester, 'sogda://word/uid-haus');
      // Android's back, which a lone page would otherwise answer by leaving.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(location(), '/today');
    });

    testWidgets('the same link without it does not', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://word/uid-haus');

      expect(
        tester.widget<WordDetailScreen>(find.byType(WordDetailScreen)).speak,
        isFalse,
      );
    });

    testWidgets('an exam link opens the step"s exams tab', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://exam/A1.2');

      expect(location(), '/learn/step/A1.2?tab=exams');
      expect(find.byType(StepDetailScreen), findsOneWidget);
      expect(
        tester.widget<StepDetailScreen>(find.byType(StepDetailScreen)).tab,
        StepTab.exams,
      );
    });

    testWidgets("#747 a launch link that isn't a URI at all opens where "
        'bootstrap says, not a failed start', (tester) async {
      // go_router parsed it with Uri.parse and threw, inside bootstrap's
      // settings step, so Retry failed the same way until the app was killed.
      tester.platformDispatcher.defaultRouteNameTestValue = 'sogda://[::1/x';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await pumpApp(tester);

      expect(location(), '/today');
    });

    // It parses, and throws once its path or query is decoded. A push of one
    // is BootstrapHost's, the first observer (widget_test.dart).
    for (final link in <String>['sogda://word/%FF', 'sogda://today?x=%FF']) {
      testWidgets("#980 a launch link whose escape isn't UTF-8 opens where "
          'bootstrap says: $link', (tester) async {
        tester.platformDispatcher.defaultRouteNameTestValue = link;
        addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
        await pumpApp(tester);

        expect(location(), '/today');
      });
    }

    test(
      '#980 readable: a link whose escape decodes, and one whose does not',
      () {
        expect(readable(Uri.parse('sogda://word/b%C3%A4r?speak=1')), isTrue);
        expect(readable(Uri.parse('sogda://word/%FF')), isFalse);
        expect(readable(Uri.parse('sogda://today?x=%FF')), isFalse);
      },
    );

    testWidgets('an unknown link lands on Today, not on an error', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLink(tester, 'sogda://nonsense/from/an/old/build');

      expect(location(), fallbackLocation);
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    group('#613 a URI from another app', () {
      // MainActivity is exported, and Flutter hands any intent's data over
      // as the route. Only `sogda://` is ours: anything else lands on Today,
      // however well its path matches a route.
      for (final link in const <String>[
        'x://h/onboarding/2?restart=true',
        'x://learn/A2.1', // a sogda-shaped link, but not sogda
        'https://example.com/exam/7',
        '//h/onboarding/2?restart=true',
      ]) {
        testWidgets('$link lands on Today', (tester) async {
          await pumpApp(tester);
          router.go('/sentences');
          await tester.pumpAndSettle();

          await openLink(tester, link);

          expect(location(), fallbackLocation);
          expect(find.byType(TodayScreen), findsOneWidget);
        });
      }

      testWidgets('and does not take over a running exam either', (
        tester,
      ) async {
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

        await openLink(tester, 'x://h/today');

        expect(location(), '/exam/7');
        expect(find.byType(ExamRunnerScreen), findsOneWidget);
      });
    });

    group('#674 FR-S1-01 nobody enrolled yet', () {
      final notEnrolled = RouteGuards(
        hasExamAttempt: (_) async => true,
        isEnrolled: () async => false,
      );

      Future<void> start(WidgetTester tester, {required String at}) async {
        router = buildRouter(initialLocation: at, guards: notEnrolled);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ...todayStub(),
              // Setup's page 1 picks the app language (#1078, #1127).
              languagesProvider.overrideWith(_English.new),
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

      testWidgets("a cold start from the widget's link opens setup, not an "
          'empty Today', (tester) async {
        // The platform's first route, the intent's link, wins over
        // bootstrap's `initialLocation` (go_router).
        tester.platformDispatcher.defaultRouteNameTestValue = 'sogda://today';
        addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
        await start(tester, at: const OnboardingRoute(page: '1').location);

        expect(location(), '/onboarding/1');
      });

      // As setup goes page to page: pushed over page 1, so the
      // configuration's own uri stays `/onboarding/1`.
      Future<void> onPage3(WidgetTester tester) async {
        await start(tester, at: const OnboardingRoute(page: '1').location);
        unawaited(router.push(const OnboardingRoute(page: '3').location));
        await tester.pumpAndSettle();
      }

      testWidgets('a link during setup leaves the learner on their page', (
        tester,
      ) async {
        await onPage3(tester);
        await openLink(tester, 'sogda://learn/A2.1');

        expect(router.state.uri.path, '/onboarding/3');
      });

      testWidgets("so does another app's", (tester) async {
        await onPage3(tester);
        await openLink(tester, 'x://h/today');

        expect(router.state.uri.path, '/onboarding/3');
      });
    });

    group('#1227 FR-D1-01 "Share → Sogda"', () {
      // R1 is built under D1, and it reads the settings.
      Future<Override> loadedSettings(WidgetTester tester) async {
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
        return settingsProvider.overrideWithValue(settings);
      }

      testWidgets('opens D1, and each share is a new arrival', (tester) async {
        final shared = _SharedTexts();
        await pumpApp(
          tester,
          extra: <Override>[
            await loadedSettings(tester),
            sharedTextProvider.overrideWithValue(shared),
          ],
        );
        await openLink(tester, 'sogda://import');
        expect(find.byType(DocImportScreen), findsOneWidget);
        expect(location(), '$shareLocation?$arrivalParameter=1');
        expect(shared.taken, 1, reason: 'D1 takes the text');

        await openLink(tester, 'sogda://import');
        expect(location(), '$shareLocation?$arrivalParameter=2');
        expect(shared.taken, 2, reason: 'a second share onto D1 is read too');
      });

      testWidgets('even mid-session, but never over a running exam', (
        tester,
      ) async {
        await pumpApp(
          tester,
          extra: <Override>[
            await loadedSettings(tester),
            sharedTextProvider.overrideWithValue(_SharedTexts()),
          ],
        );
        router.go('/learn/step/A1.2');
        await tester.pumpAndSettle();
        unawaited(router.push(const ExamRoute(attemptId: 7).location));
        await tester.pumpAndSettle();
        await openLink(tester, 'sogda://import');

        expect(find.byType(ExamRunnerScreen), findsOneWidget);
        expect(router.state.uri.path, '/exam/7');
      });
    });

    group('#676 FR-L12-04 an exam pushed over its step', () {
      // As the hub opens one (`ExamRoute.open`): the configuration's own uri
      // stays the step's, and only the top route is the exam.
      Future<void> examOverStep(
        WidgetTester tester, {
        RouteGuards? guards,
      }) async {
        await pumpApp(tester, guards: guards);
        router.go('/learn/step/A1.2');
        await tester.pumpAndSettle();
        unawaited(router.push(const ExamRoute(attemptId: 7).location));
        await tester.pumpAndSettle();
        expect(find.byType(ExamRunnerScreen), findsOneWidget);
      }

      testWidgets('a widget link does not take it over', (tester) async {
        await examOverStep(tester);
        await openLink(tester, 'sogda://today');

        expect(find.byType(ExamRunnerScreen), findsOneWidget);
        expect(router.state.uri.path, '/exam/7');
      });

      testWidgets("nor does a tapped reminder's, which goes to the router "
          'as it is', (tester) async {
        await examOverStep(tester);
        router.go('sogda://today');
        await tester.pumpAndSettle();

        expect(find.byType(ExamRunnerScreen), findsOneWidget);
        expect(router.state.uri.path, '/exam/7');
      });

      testWidgets('once it is left, a link works again', (tester) async {
        await examOverStep(tester);
        router.pop();
        await tester.pumpAndSettle();
        await openLink(tester, 'sogda://today');

        expect(location(), '/today');
      });

      group('#935 submitted: its results (L13) and review (L14), the same '
          'route, have nothing a link could cost', () {
        final submitted = RouteGuards(
          hasExamAttempt: (_) async => true,
          isEnrolled: () async => true,
          isExamRunning: (_) async => false,
        );

        testWidgets('a widget link opens where it says', (tester) async {
          await examOverStep(tester, guards: submitted);
          await openLink(tester, 'sogda://today');

          expect(location(), '/today');
        });

        testWidgets('and so does a tapped reminder', (tester) async {
          await examOverStep(tester, guards: submitted);
          router.go('sogda://today');
          await tester.pumpAndSettle();

          expect(router.state.uri.path, '/today');
        });
      });
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

      await openLink(tester, 'sogda://today');

      expect(location(), '/exam/7');
      expect(find.byType(ExamRunnerScreen), findsOneWidget);
    });

    testWidgets('and works again once the exam is done', (tester) async {
      // Dropped, not queued — but not disabled either.
      await pumpApp(tester);
      await openLink(tester, 'sogda://today');
      expect(location(), '/today');
    });

    testWidgets('only the exam is protected', (tester) async {
      // A link interrupting a study session or a quiz is fine: neither is
      // timed, and both are resumable.
      await pumpApp(tester);
      router.go('/sentences');
      await tester.pumpAndSettle();
      expect(find.byType(SentencesScreen), findsOneWidget);

      await openLink(tester, 'sogda://today');
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

      await openLink(tester, 'sogda://today');
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

    test('#613 Android drops another app\'s data before Flutter reads it', () {
      // An explicit intent skips the manifest's filter, and its scheme-less
      // `/exam/7` would reach the router as one of the app's own locations.
      final activity = File(
        'android/app/src/main/kotlin/de/sogda/app/MainActivity.kt',
      ).readAsStringSync();

      expect(
        RegExp(r'ownLinksOnly\(intent\)\s+super\.onCreate').hasMatch(activity),
        isTrue,
        reason: 'the first intent, before FlutterActivity reads it',
      );
      expect(
        RegExp(r'ownLinksOnly\(intent\)\s+super\.onNewIntent')
            .hasMatch(activity),
        isTrue,
        reason: 'a link to the running app',
      );
      expect(
        activity,
        contains(
          'intent.data?.scheme != "$deepLinkScheme") intent.data = null',
        ),
      );
      expect(
        activity,
        contains('override fun getInitialRoute(): String? = null'),
        reason: 'a `route` extra would be the first route otherwise',
      );
    });

    test('#1227 Android takes a share in the app\'s own task, its text as '
        'an extra, never as data', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final filter = RegExp(
        r'android:name="\.ShareActivity"[\s\S]*?</activity>',
      ).firstMatch(manifest)![0]!;
      expect(filter, contains('android.intent.action.SEND"'));
      expect(filter, contains('android:mimeType="text/plain"'));
      expect(filter, contains('android:noHistory="true"'));

      final share = File(
        'android/app/src/main/kotlin/de/sogda/app/ShareActivity.kt',
      ).readAsStringSync();
      // As the widget opens it: one task, one engine (SogdaWidget.kt).
      expect(
        share,
        contains('FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP'),
      );
      expect(share, contains('.setData(Uri.parse(MainActivity.SHARE_LINK))'));
      expect(
        share,
        contains('.putExtra(MainActivity.EXTRA_SHARED_TEXT, text)'),
      );

      final activity = File(
        'android/app/src/main/kotlin/de/sogda/app/MainActivity.kt',
      ).readAsStringSync();
      expect(activity, contains('const val SHARE_LINK = "sogda://import"'));
      expect(
        activity,
        contains('if (keep && intent.dataString == SHARE_LINK)'),
        reason: "another intent's extra is dropped unread",
      );
      expect(
        RegExp(r'takeShare\(intent, keep = savedInstanceState == null\)')
            .hasMatch(activity),
        isTrue,
        reason: 'a launch restored from recents shares nothing twice',
      );
    });

    test('iOS declares the scheme', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('CFBundleURLSchemes'));
      expect(plist, contains('<string>$deepLinkScheme</string>'));
    });

    test('both name the same scheme the resolver answers to', () {
      // Three places, one string. A rename in one of them would be a link
      // the OS delivers and the app throws away, or the reverse.
      expect(deepLinkScheme, 'sogda');

      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(manifest, contains(deepLinkScheme));
      expect(plist, contains(deepLinkScheme));
      expect(resolveDeepLink(Uri.parse('$deepLinkScheme://today')), '/today');
    });
  });
}

/// English screens with English and Bangla meanings: the defaults.
class _English extends Languages {
  @override
  ({MeaningChoice meaning, UiLanguage ui}) build() =>
      (meaning: const MeaningChoice('en', 'bn'), ui: UiLanguage.english);
}

/// "Share → Sogda"'s text, counted as D1 takes it.
class _SharedTexts implements SharedText {
  int taken = 0;

  @override
  Future<String?> take() async {
    taken++;
    return null;
  }
}
