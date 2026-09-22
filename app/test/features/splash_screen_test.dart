@TestOn('vm')
library;

import 'package:deutschplan/core/theme/aurora_backdrop.dart';

import 'dart:async';

import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show BootstrapHost, appLocalizationsDelegates, supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S1 · Splash — #85.
///
/// The goldens live in `test/golden/splash_golden_test.dart`; this is the
/// behaviour the artboards cannot show — when the progress line appears, what
/// a screen reader is told, and that the composition is built from tokens
/// rather than the hex values the artboards happen to use.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget child = const SplashScreen(),
    DpMode mode = DpMode.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: mode == DpMode.dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: child,
      ),
    );
    await tester.pump();
  }

  /// The tokens the screen resolved, read back out of its own tree.
  DpTokens tokensOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SplashScreen)))
          .extension<DpTokens>()!;

  group('the composition', () {
    testWidgets('shows the wordmark, the mark and the caption', (tester) async {
      await pump(tester);

      expect(find.text('DeutschPlan'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text(l10n.splashPreparing), findsOneWidget);
    });

    testWidgets('the field is the primary token, not a hex value', (
      tester,
    ) async {
      // The artboards' background is #00C2B2 light and #2EE6D6 dark, which are
      // exactly `primary` in each palette. Reading the token is what makes one
      // widget produce both artboards.
      await pump(tester);
      final tokens = tokensOf(tester);

      final scaffold = tester.widget<AdaptiveScaffold>(
        find.byType(AdaptiveScaffold),
      );

      expect(scaffold.backgroundColor, tokens.color.primary);
      expect(tokens.color.primary, const Color(0xFF00C2B2));
    });

    testWidgets('and dark resolves to the lifted palette', (tester) async {
      await pump(tester, mode: DpMode.dark);
      final tokens = tokensOf(tester);

      expect(tokens.color.primary, const Color(0xFF2EE6D6));
      expect(tokens.color.accent, const Color(0xFFFFD54A));
      expect(
        tokens.color.ink,
        const Color(0xFFF4F1FF),
        reason: 'the dark artboard draws the mark border in light ink',
      );
    });
  });

  group('FR-S1: the progress line', () {
    testWidgets('is absent on a fast start', (tester) async {
      await pump(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('appears once bootstrap is slow', (tester) async {
      await pump(tester, child: const SplashScreen(showProgress: true));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('and the mark does not move when it appears', (tester) async {
      // The line's space is held whether or not it is drawn. Without that the
      // whole composition jumps 3 px at 600 ms, which is exactly the moment
      // the learner is looking at it.
      await pump(tester);
      final before = tester.getCenter(find.text('DeutschPlan'));

      await pump(tester, child: const SplashScreen(showProgress: true));

      expect(tester.getCenter(find.text('DeutschPlan')), before);
    });

    testWidgets('holds still under reduce-motion (#Y03)', (tester) async {
      // An indefinite animation here is both an accessibility problem and the
      // thing that hangs any `pumpAndSettle` landing on this screen.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: SplashScreen(showProgress: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNotNull, reason: 'it was still animating');
    });

    testWidgets('and is indeterminate otherwise', (tester) async {
      await pump(tester, child: const SplashScreen(showProgress: true));

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(
        bar.value,
        isNull,
        reason: 'bootstrap cannot say how far through it is',
      );
    });

    testWidgets('the gate holds it back for 600 ms', (tester) async {
      await pump(tester, child: const SplashProgressGate());
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 599));
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'it showed before the threshold',
      );

      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('and a gate disposed early leaves no timer behind', (
      tester,
    ) async {
      // Bootstrap usually wins the race, so the screen is gone before the
      // threshold. A `Future.delayed` cannot be cancelled, so it outlives the
      // widget on every fast start — `mounted` hides the symptom and keeps
      // the leak. The framework fails the test if a timer is still pending
      // when the tree is torn down, which is what makes this assertable.
      await pump(tester, child: const SplashProgressGate());
      await pump(tester, child: const SizedBox());

      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    });
  });

  group('glass', () {
    Future<void> pumpGlass(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.glass(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const SplashScreen(),
        ),
      );
      await tester.pump();
    }

    testWidgets('puts the mark on a panel over the aurora', (tester) async {
      // The glass artboard replaces the flat Lagoon field with the aurora
      // paper and lifts the mark onto a blurred panel.
      await pumpGlass(tester);

      expect(find.byType(AuroraBackdrop), findsOneWidget);
      expect(find.byType(DpSurface), findsOneWidget);
    });

    testWidgets('and the solid modes use neither', (tester) async {
      for (final mode in <DpMode>[DpMode.light, DpMode.dark]) {
        await pump(tester, mode: mode);

        expect(find.byType(AuroraBackdrop), findsNothing, reason: mode.name);
        expect(find.byType(DpSurface), findsNothing, reason: mode.name);
      }
    });
  });

  group('it is what the app shows while bootstrap runs', () {
    testWidgets('S1 is on screen until bootstrap answers', (tester) async {
      // The whole point of the route existing. Before this, `main` awaited
      // bootstrap before `runApp`, so the native window covered the wait and
      // this screen could never render — nothing reached `/splash`, and the
      // 600 ms progress line had no moment in which to appear.
      final finished = Completer<BootstrapResult>();

      await tester.pumpWidget(
        BootstrapHost(
          run: ({Brightness platformBrightness = Brightness.light}) =>
              finished.future,
        ),
      );
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text(l10n.splashPreparing), findsOneWidget);

      finished.complete(
        BootstrapFailed(
          BootstrapFailure(
            step: BootstrapStep.content,
            error: 'no content',
            stackTrace: StackTrace.empty,
            db: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(SplashScreen),
        findsNothing,
        reason: 'it stayed up after bootstrap answered',
      );
    });

    testWidgets('and the progress line appears on a slow one', (tester) async {
      final finished = Completer<BootstrapResult>();

      await tester.pumpWidget(
        BootstrapHost(
          run: ({Brightness platformBrightness = Brightness.light}) =>
              finished.future,
        ),
      );
      await tester.pump(const Duration(milliseconds: 601));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      finished.complete(
        BootstrapFailed(
          BootstrapFailure(
            step: BootstrapStep.content,
            error: 'no content',
            stackTrace: StackTrace.empty,
            db: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  group('accessibility', () {
    testWidgets('the caption is what a reader announces', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel(l10n.splashPreparing), findsOneWidget);

      handle.dispose();
    });

    testWidgets('and the mark is decorative, not read out', (tester) async {
      // "D, DeutschPlan" says nothing about the wait. The caption does.
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('D'), findsNothing);
      expect(find.bySemanticsLabel('DeutschPlan'), findsNothing);

      handle.dispose();
    });
  });
}
