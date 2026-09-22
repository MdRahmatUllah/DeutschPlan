@TestOn('vm')
library;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/onboarding_welcome_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S2 · the onboarding shell and page 1 — #87.
///
/// The shell is the frame all five pages share, so its rules are asserted once
/// here rather than five times over: the header colour per page, "Step n of
/// 5", *Back* from page 2 and *Skip* from page 3.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    required OnboardingPage page,
    VoidCallback? onPrimary,
    VoidCallback? onBack,
    VoidCallback? onSkip,
    DpMode mode = DpMode.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: switch (mode) {
          DpMode.light => AppTheme.light(),
          DpMode.dark => AppTheme.dark(),
          DpMode.glass => AppTheme.glass(),
        },
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        home: OnboardingShell(
          page: page,
          headline: 'A headline',
          primaryLabel: 'Continue',
          onPrimary: onPrimary,
          onBack: onBack,
          onSkip: onSkip,
          child: const SizedBox(height: 40),
        ),
      ),
    );
    // `pump`, not `pumpAndSettle`: the glass backdrop's aurora animates
    // forever, so settling never returns.
    await tester.pump();
  }

  DpTokens tokensOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(OnboardingShell)))
          .extension<DpTokens>()!;

  group('the five pages', () {
    test('are numbered 1 to 5, in order', () {
      expect(OnboardingPage.values.map((page) => page.step), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(OnboardingPage.count, 5);
    });

    test('parse from the route slug, and refuse anything else', () {
      for (final page in OnboardingPage.values) {
        expect(OnboardingPage.parse(page.slug), page);
      }

      // A bad `:page` must not index past the end — the route renders a
      // fallback rather than throwing on a typo in a deep link.
      for (final slug in <String>['0', '6', '', 'x', '-1', 'placement']) {
        expect(OnboardingPage.parse(slug), isNull, reason: slug);
      }
    });

    test('walk forwards and back, and stop at the ends', () {
      expect(OnboardingPage.welcome.previous, isNull);
      expect(OnboardingPage.welcome.next, OnboardingPage.meaningLanguage);
      expect(OnboardingPage.reminderAndVoice.next, isNull);
      expect(
        OnboardingPage.reminderAndVoice.previous,
        OnboardingPage.dailyPace,
      );
    });
  });

  group('the header block', () {
    testWidgets('carries the spec colour for each page', (tester) async {
      // "Lagoon, Sun, Raspberry, Cobalt, Emerald" — read off the palette so
      // the block follows the theme, rather than written as five hex values.
      await pumpShell(tester, page: OnboardingPage.welcome);
      final tokens = tokensOf(tester);

      expect(
        <Color>[
          for (final page in OnboardingPage.values) page.headerColour(tokens),
        ],
        <Color>[
          tokens.color.primary,
          tokens.color.accent,
          tokens.color.die,
          tokens.color.der,
          tokens.color.das,
        ],
      );
    });

    testWidgets('and they are five different colours', (tester) async {
      // A copy-paste in the switch would give two pages the same header and
      // nothing above would notice.
      await pumpShell(tester, page: OnboardingPage.welcome);
      final tokens = tokensOf(tester);

      final colours = <Color>[
        for (final page in OnboardingPage.values) page.headerColour(tokens),
      ];
      expect(colours.toSet(), hasLength(5));
    });

    testWidgets('shows "STEP n OF 5", uppercase as drawn', (tester) async {
      for (final page in OnboardingPage.values) {
        await pumpShell(tester, page: page);

        expect(
          find.text(l10n.onboardingStepOf(page.step, 5).toUpperCase()),
          findsOneWidget,
          reason: 'page ${page.step}',
        );
      }
    });

    // Two tests, not one pumping light then glass: `MaterialApp` animates a
    // theme change, and one frame after the swap it is still drawing light.
    //
    // Behind the headline, not anywhere: the aurora paints its own blob of the
    // leading colour, and that one is meant to be there.
    ColoredBox? solidHeader(WidgetTester tester) {
      final colour = OnboardingPage.welcome.headerColour(tokensOf(tester));
      return tester
          .widgetList<ColoredBox>(
            find.ancestor(
              of: find.text('A headline'),
              matching: find.byType(ColoredBox),
            ),
          )
          .where((box) => box.color == colour)
          .firstOrNull;
    }

    testWidgets('is a solid block on paper', (tester) async {
      await pumpShell(tester, page: OnboardingPage.welcome);

      expect(solidHeader(tester), isNotNull);
    });

    testWidgets('and a tinted pane under glass', (tester) async {
      // The glass artboards lay the page colour at 22 % over frosted white. A
      // solid block there would hide the aurora the whole mode is for.
      await pumpShell(tester, page: OnboardingPage.welcome, mode: DpMode.glass);

      expect(solidHeader(tester), isNull);
      expect(
        find.ancestor(
          of: find.text('A headline'),
          matching: find.byType(DpSurface),
        ),
        findsOneWidget,
      );
    });
  });

  group('the dots', () {
    testWidgets('fill in as the pages are done', (tester) async {
      // Behind, filled ink; here, the Sun pill; ahead, an outline and no
      // fill. Page 3 is the one that shows all three at once.
      await pumpShell(tester, page: OnboardingPage.startingPoint);
      final tokens = tokensOf(tester);

      final pips = tester
          .widgetList<Container>(
            find.descendant(
              of: find.bySemanticsLabel(l10n.onboardingStepOf(3, 5)).last,
              matching: find.byType(Container),
            ),
          )
          .map((pip) => (pip.decoration! as BoxDecoration).color)
          .toList();

      expect(pips, <Color?>[
        tokens.color.ink,
        tokens.color.ink,
        tokens.color.accent,
        null,
        null,
      ]);
    });
  });

  group('the actions', () {
    testWidgets('Back appears from page 2, never on page 1', (tester) async {
      await pumpShell(tester, page: OnboardingPage.welcome);
      expect(find.widgetWithText(DpButton, l10n.back), findsNothing);

      for (final page in OnboardingPage.values.skip(1)) {
        await pumpShell(tester, page: page, onBack: () {});
        expect(
          find.widgetWithText(DpButton, l10n.back),
          findsOneWidget,
          reason: 'page ${page.step}',
        );
      }
    });

    testWidgets('FR-S2-01 Skip appears from page 3', (tester) async {
      // FR-S2-01's affordance. Pages 1 and 2 have nothing to default: page 1
      // writes no setting, and the meaning language is the one choice that
      // should be made deliberately.
      for (final page in OnboardingPage.values) {
        await pumpShell(tester, page: page, onSkip: () {});

        expect(
          find.widgetWithText(DpButton, l10n.skip),
          page.step >= 3 ? findsOneWidget : findsNothing,
          reason: 'page ${page.step}',
        );
      }
    });

    testWidgets('Back is a link at the start edge, not a second button', (
      tester,
    ) async {
      await pumpShell(
        tester,
        page: OnboardingPage.meaningLanguage,
        onBack: () {},
      );

      final back = find.widgetWithText(DpButton, l10n.back);
      expect(tester.widget<DpButton>(back).expand, isFalse);
      expect(
        tester.getTopLeft(back).dx,
        lessThan(tester.getCenter(find.byType(OnboardingShell)).dx),
      );
    });

    testWidgets('the primary action calls back', (tester) async {
      var advanced = 0;
      await pumpShell(
        tester,
        page: OnboardingPage.welcome,
        onPrimary: () => advanced++,
      );

      await tester.tap(find.widgetWithText(DpButton, 'Continue'));
      await tester.pump();

      expect(advanced, 1);
    });

    testWidgets('and Back and Skip do too', (tester) async {
      var back = 0;
      var skip = 0;
      await pumpShell(
        tester,
        page: OnboardingPage.startingPoint,
        onBack: () => back++,
        onSkip: () => skip++,
      );

      await tester.tap(find.widgetWithText(DpButton, l10n.back));
      await tester.tap(find.widgetWithText(DpButton, l10n.skip));
      await tester.pump();

      expect(<int>[back, skip], <int>[1, 1]);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pumpShell(tester, page: OnboardingPage.welcome);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('and glass still renders every page', (tester) async {
      for (final page in OnboardingPage.values) {
        await pumpShell(tester, page: page, mode: DpMode.glass);
        expect(find.byType(OnboardingShell), findsOneWidget);
      }
    });
  });

  group('accessibility', () {
    testWidgets('the dots announce the step rather than five anonymous pips', (
      tester,
    ) async {
      // Two nodes carry it: the header's "Step 3 of 5" text, and the row of
      // dots, which labels itself and hides its five children. Asserting the
      // count rather than `findsOneWidget` is what makes the second one
      // required — otherwise the header alone would satisfy the finder.
      final handle = tester.ensureSemantics();
      await pumpShell(tester, page: OnboardingPage.startingPoint);

      final label = l10n.onboardingStepOf(3, OnboardingPage.count);
      expect(find.bySemanticsLabel(label), findsNWidgets(2));

      handle.dispose();
    });
  });

  group('page 1 · Welcome', () {
    Future<void> pumpWelcome(WidgetTester tester, {VoidCallback? onStart}) =>
        tester
            .pumpWidget(
              MaterialApp(
                theme: AppTheme.light(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: supportedLocales,
                home: OnboardingWelcomePage(onStart: onStart),
              ),
            )
            .then((_) => tester.pump());

    testWidgets('states the three promises', (tester) async {
      await pumpWelcome(tester);

      expect(find.text(l10n.onboardingPromiseOffline), findsOneWidget);
      expect(find.text(l10n.onboardingPromiseSteps), findsOneWidget);
      expect(find.text(l10n.onboardingPromisePrivate), findsOneWidget);
    });

    testWidgets('and its button says Let\'s start, not Continue', (
      tester,
    ) async {
      // Page 1 and page 5 name their own action; only the middle three
      // continue.
      await pumpWelcome(tester);

      expect(
        find.widgetWithText(DpButton, l10n.onboardingWelcomeStart),
        findsOneWidget,
      );
    });

    testWidgets('starting moves on', (tester) async {
      var started = 0;
      await pumpWelcome(tester, onStart: () => started++);

      await tester.tap(
        find.widgetWithText(DpButton, l10n.onboardingWelcomeStart),
      );
      await tester.pump();

      expect(started, 1);
    });

    testWidgets('it writes no setting, so it offers no Skip', (tester) async {
      await pumpWelcome(tester);

      expect(find.widgetWithText(DpButton, l10n.skip), findsNothing);
      expect(find.widgetWithText(DpButton, l10n.back), findsNothing);
    });
  });
}
