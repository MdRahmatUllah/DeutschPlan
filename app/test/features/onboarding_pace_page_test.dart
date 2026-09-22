@TestOn('vm')
library;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_slider.dart';
import 'package:deutschplan/core/components/dp_stepper.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_pace_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 4 · Daily pace — #90.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const course = <CourseStep>[
    (code: 'A1.1', levelCode: 'A1', wordCount: 637),
    (code: 'B1.2', levelCode: 'B1', wordCount: 185),
  ];

  late ProviderContainer container;

  OnboardingDraft draft() => container.read(onboardingProvider);

  Future<void> pump(
    WidgetTester tester, {
    DpMode mode = DpMode.light,
    double textScale = 1,
    VoidCallback? onContinue,
    VoidCallback? onBack,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: <Override>[
        courseStepsProvider.overrideWith((ref) async => course),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: switch (mode) {
            DpMode.light => AppTheme.light(),
            DpMode.dark => AppTheme.dark(),
            DpMode.glass => AppTheme.glass(),
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: OnboardingPacePage(onContinue: onContinue, onBack: onBack),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  String estimate(int days, String step, int dailyNew) =>
      l10n.onboardingPaceEstimate(days, step, dailyNew);

  group('FR-S2-04 the estimate', () {
    testWidgets("starts on the defaults and the step's own words", (
      tester,
    ) async {
      // 637 words at 7 a day, every day: 91. Read from content.db, not the
      // artboard's 480.
      await pump(tester);

      expect(find.text(estimate(91, 'A1.1', 7)), findsOneWidget);
    });

    testWidgets('moves with the slider', (tester) async {
      await pump(tester);

      container.read(onboardingProvider.notifier).setDailyNew(10);
      await tester.pump();

      expect(find.text(estimate(64, 'A1.1', 10)), findsOneWidget);
    });

    testWidgets('and with a preset', (tester) async {
      await pump(tester);

      await tester.tap(find.text(l10n.onboardingPaceIntensive(15)));
      await tester.pump();

      expect(draft().dailyNew, 15);
      expect(find.text(estimate(43, 'A1.1', 15)), findsOneWidget);
    });

    testWidgets('and with the study days', (tester) async {
      // Weekends off: 637 × 7 ÷ (7 × 5) = 127.4, so 128.
      await pump(tester);

      await tester.tap(find.text(l10n.weekdayShortSat));
      await tester.pump();
      await tester.tap(find.text(l10n.weekdayShortSun));
      await tester.pump();

      expect(find.text(estimate(128, 'A1.1', 7)), findsOneWidget);
    });

    testWidgets('and follows the step chosen on page 3', (tester) async {
      await pump(tester);

      container.read(onboardingProvider.notifier).chooseStep('B1.2');
      await tester.pump();

      expect(find.text(estimate(27, 'B1.2', 7)), findsOneWidget);
    });
  });

  group('new words per day', () {
    testWidgets('is a 3–30 slider showing the value beside its label', (
      tester,
    ) async {
      await pump(tester);

      final slider = tester.widget<DpSlider>(find.byType(DpSlider));
      expect(<int>[slider.min, slider.value, slider.max], <int>[3, 7, 30]);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('dragging it to the far end gives 30, not more', (
      tester,
    ) async {
      await pump(tester);

      await tester.drag(find.byType(DpSlider), const Offset(2000, 0));
      await tester.pump();

      expect(draft().dailyNew, 30);
    });

    testWidgets('and the presets are Relaxed 5, Steady 7, Intensive 15', (
      tester,
    ) async {
      await pump(tester);

      final chips = tester
          .widgetList<DpChip>(find.byType(DpChip))
          .map((chip) => (chip.label, chip.selected))
          .toList();
      expect(chips, <(String, bool)>[
        (l10n.onboardingPaceRelaxed(5), false),
        (l10n.onboardingPaceSteady(7), true),
        (l10n.onboardingPaceIntensive(15), false),
      ]);
    });

    testWidgets('a value between presets picks none of them', (tester) async {
      await pump(tester);

      container.read(onboardingProvider.notifier).setDailyNew(9);
      await tester.pump();

      expect(
        tester.widgetList<DpChip>(find.byType(DpChip)).where((c) => c.selected),
        isEmpty,
      );
    });
  });

  group('revisions per day', () {
    testWidgets('steps up and down from 10', (tester) async {
      await pump(tester);
      expect(draft().reviseCount, 10);

      await tester.tap(
        find.bySemanticsLabel(l10n.onboardingPaceRevisionsIncrease),
      );
      await tester.pump();
      expect(draft().reviseCount, 11);

      // A frame between taps, as a finger allows: the buttons act on the
      // value they were built with.
      for (var i = 0; i < 2; i++) {
        await tester.tap(
          find.bySemanticsLabel(l10n.onboardingPaceRevisionsDecrease),
        );
        await tester.pump();
      }
      expect(draft().reviseCount, 9);
    });

    testWidgets('carries the note BR-PLAN-03 needs', (tester) async {
      // "It never exceeds revise_count; excess due cards wait."
      await pump(tester);

      expect(find.text(l10n.onboardingPaceRevisionsNote), findsOneWidget);
    });

    testWidgets('and stops at 0 and 100', (tester) async {
      await pump(tester);
      final notifier = container.read(onboardingProvider.notifier)
        ..setReviseCount(0);
      await tester.pump();

      expect(tester.widget<DpStepper>(find.byType(DpStepper)).value, 0);
      await tester.tap(
        find.bySemanticsLabel(l10n.onboardingPaceRevisionsDecrease),
      );
      await tester.pump();
      expect(draft().reviseCount, 0);

      notifier.setReviseCount(250);
      expect(draft().reviseCount, 100);
    });
  });

  group('study days', () {
    testWidgets('start as every day, Monday first', (tester) async {
      await pump(tester);

      expect(draft().studyDaysMask, 127);
      final labels = <String>[
        l10n.weekdayShortMon,
        l10n.weekdayShortTue,
        l10n.weekdayShortWed,
        l10n.weekdayShortThu,
        l10n.weekdayShortFri,
        l10n.weekdayShortSat,
        l10n.weekdayShortSun,
      ];
      final xs = labels.map((l) => tester.getCenter(find.text(l)).dx).toList();
      expect(xs, List<double>.of(xs)..sort(), reason: 'left to right');
    });

    testWidgets("toggle the day's own bit, Monday at bit 0", (tester) async {
      // The same bit `PlanEngine.isStudyDay` reads. A chip wired to the
      // wrong one would plan the learner's Tuesdays off when they untick
      // Wednesday.
      await pump(tester);

      await tester.tap(find.text(l10n.weekdayShortWed));
      await tester.pump();

      expect(draft().studyDaysMask, 127 & ~(1 << 2));
    });

    testWidgets('and the last one cannot be turned off', (tester) async {
      // A week with no study days is a plan that never runs, and the
      // estimate would divide by zero.
      await pump(tester);
      for (final day in <String>[
        l10n.weekdayShortMon,
        l10n.weekdayShortTue,
        l10n.weekdayShortWed,
        l10n.weekdayShortThu,
        l10n.weekdayShortFri,
        l10n.weekdayShortSat,
        l10n.weekdayShortSun,
      ]) {
        await tester.tap(find.text(day));
        await tester.pump();
      }

      expect(draft().studyDaysMask, 1 << 6, reason: 'Sunday stays on');
      expect(find.text(estimate(637, 'A1.1', 7)), findsOneWidget);
    });
  });

  group('the draft', () {
    testWidgets('holds daily_new, revise_count and study_days_mask', (
      tester,
    ) async {
      // Written when the finish commits it (#92); until then, here and only
      // here — there is no database in this scope to write to.
      await pump(tester);

      await tester.tap(find.text(l10n.onboardingPaceRelaxed(5)));
      await tester.tap(
        find.bySemanticsLabel(l10n.onboardingPaceRevisionsIncrease),
      );
      await tester.tap(find.text(l10n.weekdayShortMon));
      await tester.pump();

      expect(
        (draft().dailyNew, draft().reviseCount, draft().studyDaysMask),
        (5, 11, 127 & ~1),
      );
    });
  });

  group('the actions', () {
    testWidgets('Continue and Back call back', (tester) async {
      var continued = 0;
      var back = 0;
      await pump(tester, onContinue: () => continued++, onBack: () => back++);

      await tester.tap(find.text(l10n.continueAction));
      await tester.tap(find.text(l10n.back));
      await tester.pump();

      expect(<int>[continued, back], <int>[1, 1]);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
      testWidgets('and ${mode.name} renders it', (tester) async {
        await pump(tester, mode: mode);
        expect(find.text(estimate(91, 'A1.1', 7)), findsOneWidget);
      });
    }
  });

  group('accessibility', () {
    testWidgets('the slider says what it is and where it stands', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      // The node the slider's own Semantics makes — found through its gesture
      // detector, which sits inside it; the DpSlider widget itself is above.
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byType(DpSlider),
            matching: find.byType(GestureDetector),
          ),
        ),
        matchesSemantics(
          isSlider: true,
          label: l10n.onboardingPaceNewWords,
          value: '7',
          increasedValue: '8',
          decreasedValue: '6',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('the days read as whole names, and whether they are on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(find.text(l10n.weekdayShortMon)),
        matchesSemantics(
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
          label: l10n.weekdayMon,
        ),
      );

      handle.dispose();
    });

    testWidgets('and it holds together at 200 % text', (tester) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}
