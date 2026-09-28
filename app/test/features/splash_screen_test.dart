@TestOn('vm')
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/bootstrap.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_mark.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/splash/splash_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show BootstrapHost, appLocalizationsDelegates, supportedLocales;

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
    SgMode mode = SgMode.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: mode == SgMode.dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: child,
      ),
    );
    await tester.pump();
  }

  /// The tokens the screen resolved, read back out of its own tree.
  SgTokens tokensOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SplashScreen)))
          .extension<SgTokens>()!;

  /// Whether two rects share more than an edge: a lockup scaled to fit its
  /// slot ends where the caption starts, give or take a rounding.
  bool overlap(Rect a, Rect b) => a.deflate(0.01).overlaps(b.deflate(0.01));

  /// A phone of [size] dp at 3×, with a navigation bar of [bottom] dp.
  void phone(WidgetTester tester, Size size, {double bottom = 0}) {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3
      // Physical pixels, like the size.
      ..padding = FakeViewPadding(bottom: bottom * 3);
    addTearDown(tester.view.reset);
  }

  group('the composition', () {
    testWidgets('#602 shows the tiles, the wordmark and the caption', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(SgMark), findsOneWidget);
      expect(find.byType(SgWordmark), findsOneWidget);
      // Twice: the caption, and its twin over the lockup, which only holds
      // the space that centres it, unseen and unread.
      expect(find.text(l10n.splashPreparing), findsNWidgets(2));
      final twin = find.ancestor(
        of: find.text(l10n.splashPreparing).first,
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(twin.first).opacity, 0);
    });

    testWidgets('FR-S1-05 #602 the tiles are the size and place Android 12 '
        'draws its splash icon: its 108 grid on 288 dp, at the centre', (
      tester,
    ) async {
      // `splash_icon.xml` is the kit's grid on a 288 dp canvas, which the
      // platform centres on the screen. The kit's lockup frames the grid at
      // 1.32× in its square, so the square is 288 / 1.32.
      phone(tester, const Size(390, 844));
      await pump(tester);
      final mark = tester.getRect(find.byType(SgMark));

      expect(mark.width * 1.32, moreOrLessEquals(288));
      expect(mark.center, const Offset(195, 422));
    });

    testWidgets('FR-S1-05 #602 and a navigation bar leaves them at the '
        'screen’s centre, not the body’s', (tester) async {
      // The scaffold keeps the body above the bar; the platform's splash
      // centres its icon on the whole screen.
      phone(tester, const Size(390, 844), bottom: 48);
      await pump(tester);

      expect(
        tester.getRect(find.byType(SgMark)).center,
        const Offset(195, 422),
      );
    });

    testWidgets('FR-S1-05 #602 on a short phone at 200 % text the lockup '
        'shrinks clear of the caption', (tester) async {
      phone(tester, const Size(360, 640), bottom: 48);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, child: const SplashScreen(showProgress: true));

      final caption = tester.getRect(find.text(l10n.splashPreparing).last);
      expect(
        overlap(caption, tester.getRect(find.byType(SgWordmark))),
        isFalse,
      );
      expect(
        overlap(caption, tester.getRect(find.byType(LinearProgressIndicator))),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    for (final size in <Size>[const Size(360, 640), const Size(320, 568)]) {
      for (final scale in <double>[1, 2]) {
        testWidgets('#744 FR-S1-05 on a ${size.width.round()} × '
            '${size.height.round()} phone at ${(scale * 100).round()} % the '
            'lockup keeps 16 dp from the caption, the mark at the centre', (
          tester,
        ) async {
          phone(tester, size, bottom: 48);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, child: const SplashScreen(showProgress: true));

          final caption = tester.getRect(find.text(l10n.splashPreparing).last);
          final lockup = tester.getRect(find.byType(SplashLockup));
          expect(caption.top - lockup.bottom, greaterThanOrEqualTo(16 - 0.01));
          final mark = tester.getRect(find.byType(SgMark)).center;
          expect(mark.dx, moreOrLessEquals(size.width / 2));
          expect(mark.dy, moreOrLessEquals(size.height / 2));
        });
      }
    }

    testWidgets('FR-S1-05 #602 and a 1024 × 600 tablet on its side, with a '
        'navigation bar, does not overflow', (tester) async {
      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(2048, 1200)
        ..padding = const FakeViewPadding(bottom: 96);
      addTearDown(tester.view.reset);
      await pump(tester, child: const SplashScreen(showProgress: true));

      expect(tester.takeException(), isNull);
      expect(
        overlap(
          tester.getRect(find.text(l10n.splashPreparing).last),
          tester.getRect(find.byType(LinearProgressIndicator)),
        ),
        isFalse,
      );
    });

    testWidgets('#602 and the tiles and the wordmark are the kit’s in dark '
        'too, Ink on the lifted Lagoon', (tester) async {
      await pump(tester, mode: SgMode.dark);

      expect(tester.widget<SgMark>(find.byType(SgMark)).square, isFalse);
      expect(
        tester.widget<SgWordmark>(find.byType(SgWordmark)).colour,
        SgBrand.ink,
      );
    });

    testWidgets('#602 and neither grows with the text size: they are the '
        'logo', (tester) async {
      await pump(tester);
      final mark = tester.getSize(find.byType(SgMark));
      final wordmark = tester.getSize(find.byType(SgWordmark));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SplashScreen(),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SgMark)), mark);
      expect(tester.getSize(find.byType(SgWordmark)), wordmark);
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
      await pump(tester, mode: SgMode.dark);
      final tokens = tokensOf(tester);

      expect(tokens.color.primary, const Color(0xFF2EE6D6));
      expect(tokens.color.accent, const Color(0xFFFFD54A));
    });

    // One test per mode: MaterialApp animates a theme change, so a second
    // pump in the same test would still read the first mode's colours.
    for (final mode in <SgMode>[SgMode.light, SgMode.dark]) {
      testWidgets('#605 the caption reaches 4.5:1 and the progress line 3:1 '
          'on the field, ${mode.name}', (tester) async {
        // The dark page's light ink was about 1.4:1 on the lifted Lagoon;
        // they are the kit's Ink now, as the wordmark is.
        double ratio(Color a, Color b) {
          final (x, y) = (a.computeLuminance(), b.computeLuminance());
          return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
        }

        await pump(
          tester,
          mode: mode,
          child: const SplashScreen(showProgress: true),
        );
        final field = tokensOf(tester).color.primary;
        expect(
          field,
          mode == SgMode.dark
              ? const Color(0xFF2EE6D6)
              : const Color(0xFF00C2B2),
          reason: "the field is the mode's",
        );
        final caption = tester
            .widget<Text>(find.text(l10n.splashPreparing).last)
            .style!
            .color!;
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final value = bar.valueColor!.value!;
        final track = Color.alphaBlend(bar.backgroundColor!, field);

        expect(ratio(caption, field), greaterThanOrEqualTo(4.5));
        expect(ratio(value, field), greaterThanOrEqualTo(3));
        expect(ratio(value, track), greaterThanOrEqualTo(3));
        expect(
          bar.backgroundColor,
          SgSurfaceTokens.light.track,
          reason: 'the same rule in both modes: Ink over its light track',
        );
      });
    }
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
      final before = tester.getCenter(find.byType(SgMark));

      await pump(tester, child: const SplashScreen(showProgress: true));

      expect(tester.getCenter(find.byType(SgMark)), before);
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
      // #449: what is not loaded yet reaches 3:1 on the paper.
      expect(bar.backgroundColor, SgTokens.light().surface.track);
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

    testWidgets('#602 puts the mark on its Lagoon square over the aurora', (
      tester,
    ) async {
      // The glass artboard replaces the flat Lagoon field with the aurora
      // paper. The kit's rule for any ground but Lagoon: the tiles on their
      // square. No panel: the square is the mark's own ground.
      await pumpGlass(tester);

      expect(find.byType(AuroraBackdrop), findsOneWidget);
      expect(tester.widget<SgMark>(find.byType(SgMark)).square, isTrue);
      expect(find.byType(SgSurface), findsNothing);
    });

    testWidgets('and the solid modes use neither', (tester) async {
      for (final mode in <SgMode>[SgMode.light, SgMode.dark]) {
        await pump(tester, mode: mode);

        expect(find.byType(AuroraBackdrop), findsNothing, reason: mode.name);
        expect(
          tester.widget<SgMark>(find.byType(SgMark)).square,
          isFalse,
          reason: mode.name,
        );
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
          run: ({
            void Function(UiLanguage)? onUiLanguage,
            void Function()? onCourseUpdate,
          }) => finished.future,
        ),
      );
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text(l10n.splashPreparing), findsNWidgets(2));

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

    testWidgets('and it switches to the learner’s language once read', (
      tester,
    ) async {
      // The splash starts in the phone's language — nothing else is known —
      // and moves to `ui_language` as soon as bootstrap has read it, rather
      // than waiting for the app to take over and switching then.
      final finished = Completer<BootstrapResult>();
      void Function(UiLanguage)? tell;

      await tester.pumpWidget(
        BootstrapHost(
          run:
              ({
                void Function(UiLanguage)? onUiLanguage,
                void Function()? onCourseUpdate,
              }) {
                tell = onUiLanguage;
                return finished.future;
              },
        ),
      );
      await tester.pump();
      expect(find.text(l10n.splashPreparing), findsNWidgets(2));

      tell!(UiLanguage.bangla);
      await tester.pump();

      final bn = await AppLocalizations.delegate.load(const Locale('bn'));
      expect(find.text(bn.splashPreparing), findsNWidgets(2));
      expect(tester.takeException(), isNull);

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

    testWidgets('#686 ST-9 and it says the course is updating once an app '
        "update starts copying one in, in the learner's language", (
      tester,
    ) async {
      final finished = Completer<BootstrapResult>();
      void Function(UiLanguage)? tell;
      void Function()? updating;

      await tester.pumpWidget(
        BootstrapHost(
          run:
              ({
                void Function(UiLanguage)? onUiLanguage,
                void Function()? onCourseUpdate,
              }) {
                tell = onUiLanguage;
                updating = onCourseUpdate;
                return finished.future;
              },
        ),
      );
      await tester.pump();
      expect(find.text(l10n.splashPreparing), findsNWidgets(2));

      tell!(UiLanguage.bangla);
      updating!();
      await tester.pump(const Duration(milliseconds: 601));

      final bn = await AppLocalizations.delegate.load(const Locale('bn'));
      expect(find.text(bn.splashUpdating), findsNWidgets(2));
      expect(find.text(bn.splashPreparing), findsNothing);
      // The same gate: its progress line keeps its own timing.
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

    testWidgets('and the progress line appears on a slow one', (tester) async {
      final finished = Completer<BootstrapResult>();

      await tester.pumpWidget(
        BootstrapHost(
          run: ({
            void Function(UiLanguage)? onUiLanguage,
            void Function()? onCourseUpdate,
          }) => finished.future,
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

    testWidgets('#602 and the mark is decorative, not read out', (
      tester,
    ) async {
      // "Sogda" says nothing about the wait. The caption does.
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel(RegExp(r'^(Sogda|a|Ä)$')), findsNothing);
      expect(
        find.ancestor(
          of: find.byType(SplashMark),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );

      handle.dispose();
    });
  });
}
