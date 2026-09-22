@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/back_behaviour.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Back behaviour — #69.
///
/// `navigation.md`: "Android back pops the current route; on a tab root
/// returns to Today; on Today exits (predictive back enabled). iOS: edge
/// swipe on pushed routes; none on tab roots." The exam runner asks instead.
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
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// A system back press, as the platform delivers it.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// Whether the app would close on the next back press.
  ///
  /// `canPop` is exactly what predictive back reads to decide whether to draw
  /// the preview of the app closing, so this is the criterion as well as the
  /// behaviour.
  bool wouldExit(WidgetTester tester) {
    // Scoped to *our* handler, not to every `PopScope` in the tree: a pushed
    // route brings its own, always false, so an `every` over all of them
    // answered the route's question rather than the shell's — and the shell
    // could have said anything.
    //
    // Found by predicate rather than by type, because `PopScope` is generic
    // and the instantiations in the tree are `PopScope<Object>` and
    // `PopScope<dynamic>`; `find.byType(PopScope<Object?>)` matches neither,
    // and `every` on an empty list is `true`.
    final ours = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is ShellBackHandler || widget is ExamBackGuard,
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().startsWith('PopScope'),
      ),
    );

    final canPop = <bool>[
      for (final element in ours.evaluate().take(1)) _canPopOf(element.widget),
    ];

    expect(canPop, isNotEmpty, reason: 'our PopScope is not in the tree');
    return canPop.single;
  }

  group('Android back inside the shell', () {
    testWidgets('pops a pushed route', (tester) async {
      await pumpApp(tester, at: '/today/backlog');
      expect(find.text('T4'), findsOneWidget);

      await pressBack(tester);

      expect(find.text('T1'), findsOneWidget);
      expect(location(), '/today');
    });

    testWidgets('returns to Today from another tab root', (tester) async {
      await pumpApp(tester, at: '/me');
      expect(find.text('M1'), findsOneWidget);

      await pressBack(tester);

      expect(find.text('T1'), findsOneWidget);
    });

    testWidgets('pops within the tab before leaving it', (tester) async {
      // Two presses from a pushed route in another tab: the first pops, the
      // second goes to Today. Not one press for both.
      await pumpApp(tester, at: '/me/settings');
      expect(find.text('M3'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('M1'), findsOneWidget, reason: 'it left the tab early');

      await pressBack(tester);
      expect(find.text('T1'), findsOneWidget);
    });

    testWidgets('a deep stack unwinds one route at a time', (tester) async {
      await pumpApp(tester, at: '/me/settings/reminder');
      expect(find.text('M5'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('M3'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('M1'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('T1'), findsOneWidget);
    });
  });

  group('predictive back', () {
    testWidgets('is on when the press would close the app', (tester) async {
      // Today with nothing pushed: the next back press exits, so the system
      // should draw the preview of it.
      await pumpApp(tester);
      expect(wouldExit(tester), isTrue);
    });

    testWidgets('is off when the press has somewhere to go', (tester) async {
      await pumpApp(tester, at: '/today/backlog');
      expect(wouldExit(tester), isFalse);

      await pumpApp(tester, at: '/search');
      expect(
        wouldExit(tester),
        isFalse,
        reason: 'a tab root that is not Today still has Today to go to',
      );
    });

    testWidgets('comes back once the stack is empty again', (tester) async {
      await pumpApp(tester, at: '/today/backlog');
      expect(wouldExit(tester), isFalse);

      await pressBack(tester);
      expect(wouldExit(tester), isTrue);
    });

    test('is enabled in the Android manifest', () {
      // The Flutter side cannot turn it on alone: without this attribute
      // Android 13+ runs the legacy back handler and the gesture shows no
      // preview however `canPop` is written.
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    });
  });

  group('the exam runner', () {
    testWidgets('back asks instead of popping', (tester) async {
      await pumpApp(tester, at: '/exam/7');
      expect(find.text('L12'), findsOneWidget);

      await pressBack(tester);

      expect(find.text(l10n.examLeaveTitle), findsOneWidget);
      expect(find.text('L12'), findsOneWidget, reason: 'it popped anyway');
      expect(location(), '/exam/7');
    });

    testWidgets('*Keep going* returns to the question', (tester) async {
      await pumpApp(tester, at: '/exam/7');
      await pressBack(tester);

      await tester.tap(find.text(l10n.examLeaveCancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.examLeaveTitle), findsNothing);
      expect(location(), '/exam/7');
    });

    testWidgets('*Leave* leaves', (tester) async {
      await pumpApp(tester, at: '/exam/7');
      await pressBack(tester);

      await tester.tap(find.text(l10n.examLeaveConfirm));
      await tester.pumpAndSettle();

      expect(location(), examFallback);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('the dialog says what is kept and what is lost', (
      tester,
    ) async {
      // FR-L12-04 saves the answers and stops the timer. A dialog that did
      // not say so would read as "lose everything".
      await pumpApp(tester, at: '/exam/7');
      await pressBack(tester);

      expect(find.text(l10n.examLeaveMessage), findsOneWidget);
      expect(l10n.examLeaveMessage, contains('saved'));
      expect(l10n.examLeaveMessage, contains('timer'));
    });

    testWidgets('two quick back presses ask once, not twice', (tester) async {
      // The handler is async and shows a dialog, so a second press arriving
      // while the first is still opening used to reach `ModalRoute.willPop`
      // mid-transition and trip a framework assertion. Two fast presses in a
      // timed exam is an ordinary input.
      await pumpApp(tester, at: '/exam/7');

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(l10n.examLeaveTitle), findsOneWidget);

      await tester.tap(find.text(l10n.examLeaveCancel));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.examLeaveTitle),
        findsNothing,
        reason: 'a second dialog was waiting behind the first',
      );
      expect(location(), '/exam/7');
    });

    testWidgets('and back still works afterwards', (tester) async {
      // The re-entrancy flag has to clear, or one double-press would leave
      // back dead for the rest of the exam.
      await pumpApp(tester, at: '/exam/7');

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.examLeaveCancel));
      await tester.pumpAndSettle();

      await pressBack(tester);
      expect(find.text(l10n.examLeaveTitle), findsOneWidget);
    });

    testWidgets('predictive back and the edge swipe are both off', (
      tester,
    ) async {
      // One mechanism for both: `canPop: false` stops the system drawing a
      // close preview *and* stops the iOS swipe starting.
      await pumpApp(tester, at: '/exam/7');
      expect(wouldExit(tester), isFalse);
    });
  });

  group('the iOS edge swipe', () {
    testWidgets('a tab root has nothing to swipe back to', (tester) async {
      // Not a rule to implement — a branch navigator with one route has no
      // previous page, so Flutter never starts the gesture. This is the
      // assertion that it really is the first route.
      await pumpApp(tester, at: '/learn');

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('a pushed route does', (tester) async {
      await pumpApp(tester, at: '/learn/grammar');

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      expect(navigator.canPop(), isTrue);
    });
  });
}

/// `PopScope.canPop` without knowing the type argument.
///
/// `PopScope<Object>` and `PopScope<dynamic>` are both in the tree and
/// neither is a subtype of the other, so there is no single cast that reaches
/// both.
// ignore: avoid_dynamic_calls
bool _canPopOf(Widget widget) => (widget as dynamic).canPop as bool;
