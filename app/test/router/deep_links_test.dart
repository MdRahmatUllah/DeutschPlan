@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/deep_links.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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

    Future<void> pumpApp(WidgetTester tester) async {
      router = buildRouter(guards: RouteGuards.permissive());
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
      expect(find.text('L2'), findsOneWidget);

      await openLink(tester, 'deutschplan://today');

      expect(location(), '/today');
      expect(find.text('T1'), findsOneWidget);
    });

    testWidgets('a step link opens the step', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://learn/A2.1');

      expect(location(), '/learn/step/A2.1');
      expect(find.text('L2'), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('a word link opens the word', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus');

      expect(location(), '/word/uid-haus');
      expect(find.text('W1'), findsOneWidget);
      expect(find.text('uid-haus'), findsOneWidget);
    });

    testWidgets('the widget"s Pronounce link asks for speech', (tester) async {
      // FR-X1-02: "the app plays on open". The route has to see the query,
      // not just keep it in the URL.
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus?speak=1');

      expect(location(), '/word/uid-haus?speak=1');
      expect(find.text('uid-haus speak'), findsOneWidget);
    });

    testWidgets('the same link without it does not', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://word/uid-haus');

      expect(find.text('uid-haus'), findsOneWidget);
      expect(find.text('uid-haus speak'), findsNothing);
    });

    testWidgets('an exam link opens the step"s exams tab', (tester) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://exam/A1.2');

      expect(location(), '/learn/step/A1.2?tab=exams');
      expect(find.text('L2'), findsOneWidget);
      expect(find.text('exams'), findsOneWidget);
    });

    testWidgets('an unknown link lands on Today, not on an error', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLink(tester, 'deutschplan://nonsense/from/an/old/build');

      expect(location(), fallbackLocation);
      expect(find.text('T1'), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
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
        MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: supportedLocales,
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
