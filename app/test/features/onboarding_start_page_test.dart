@TestOn('vm')
library;

import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 3 · Starting point — #89.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  // The shipped counts, deliberately not the artboard's round numbers: the
  // screen has to show what content.db says, and 637 is not 480.
  const course = <CourseStep>[
    (code: 'A1.1', levelCode: 'A1', wordCount: 637),
    (code: 'A1.2', levelCode: 'A1', wordCount: 679),
    (code: 'A2.1', levelCode: 'A2', wordCount: 540),
    (code: 'A2.2', levelCode: 'A2', wordCount: 498),
    (code: 'B1.1', levelCode: 'B1', wordCount: 194),
    (code: 'B1.2', levelCode: 'B1', wordCount: 185),
    (code: 'B2.1', levelCode: 'B2', wordCount: 594),
    (code: 'B2.2', levelCode: 'B2', wordCount: 625),
    (code: 'C1.1', levelCode: 'C1', wordCount: 494),
    (code: 'C1.2', levelCode: 'C1', wordCount: 469),
    (code: 'C2.1', levelCode: 'C2', wordCount: 342),
    (code: 'C2.2', levelCode: 'C2', wordCount: 1),
  ];

  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    List<CourseStep> steps = course,
    DpMode mode = DpMode.light,
    Future<String?> Function()? onPlacement,
    VoidCallback? onContinue,
    VoidCallback? onBack,
    VoidCallback? onSkip,
    double textScale = 1,
    bool fresh = true,
  }) async {
    // The phone frame the artboard is drawn at. The default 800 × 600 test
    // surface puts the lower rows and the link below the fold, where a tap
    // lands on nothing.
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    if (fresh) {
      container = ProviderContainer(
        overrides: <Override>[
          courseStepsProvider.overrideWith((ref) async => steps),
        ],
      );
      addTearDown(container.dispose);
    }

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
          home: OnboardingStartPage(
            onPlacement: onPlacement,
            onContinue: onContinue,
            onBack: onBack,
            onSkip: onSkip,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder chip(String code) =>
      find.ancestor(of: find.text(code), matching: find.byType(DpSurface));

  List<String> picked(WidgetTester tester) => <String>[
    for (final step in course)
      if (tester.widget<DpSurface>(chip(step.code)).selected) step.code,
  ];

  group('the twelve steps', () {
    testWidgets('BR-COURSE-01 in course order, two to a level', (tester) async {
      await pump(tester);

      // Top to bottom, then left to right — the order a learner reads them.
      final positions = <String, Offset>{
        for (final step in course) step.code: tester.getCenter(chip(step.code)),
      };
      final reading = course.map((s) => s.code).toList()
        ..sort((a, b) {
          final dy = positions[a]!.dy.compareTo(positions[b]!.dy);
          return dy != 0 ? dy : positions[a]!.dx.compareTo(positions[b]!.dx);
        });
      expect(reading, course.map((s) => s.code).toList());

      for (final level in <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2']) {
        expect(find.text(level), findsOneWidget, reason: level);
        // Both of a level's chips sit on its label's line.
        final label = tester.getCenter(find.text(level)).dy;
        expect(tester.getCenter(chip('$level.1')).dy, closeTo(label, 1));
        expect(tester.getCenter(chip('$level.2')).dy, closeTo(label, 1));
      }
    });

    testWidgets('show the word counts content.db has', (tester) async {
      // "Word counts read from c.sublevels, never hard-coded."
      await pump(tester);

      expect(find.text(l10n.onboardingStepWords(637)), findsOneWidget);
      expect(find.text(l10n.onboardingStepWords(185)), findsOneWidget);
      // And the plural is the ARB's, not an `s` stuck on the end.
      expect(find.text('1 word'), findsOneWidget);
    });

    testWidgets('and follow a content update that changes one', (tester) async {
      await pump(
        tester,
        steps: <CourseStep>[
          for (final step in course)
            step.code == 'A1.1'
                ? (code: step.code, levelCode: step.levelCode, wordCount: 999)
                : step,
        ],
      );

      expect(find.text(l10n.onboardingStepWords(999)), findsOneWidget);
      expect(find.text(l10n.onboardingStepWords(637)), findsNothing);
    });
  });

  group('the pick', () {
    testWidgets('starts on A1.1', (tester) async {
      await pump(tester);

      expect(picked(tester), <String>['A1.1']);
      expect(container.read(onboardingProvider).step, 'A1.1');
    });

    testWidgets('moves with the tap, and there is only ever one', (
      tester,
    ) async {
      await pump(tester);

      for (final code in <String>['B2.1', 'C2.2', 'A1.2']) {
        await tester.tap(chip(code));
        await tester.pump();

        expect(picked(tester), <String>[code]);
        expect(container.read(onboardingProvider).step, code);
      }
    });

    testWidgets('FR-S2-02 is still there when the page comes back', (
      tester,
    ) async {
      // Back to page 2 and forward again builds a new page 3. The pick lives
      // in the draft, not in the page, so the new one shows it.
      await pump(tester);
      await tester.tap(chip('B1.2'));
      await tester.pump();

      // That the draft itself survives the page going is
      // onboarding_notifier_test's to show — a widget test's container never
      // gets round to disposing it. This is the other half: a new page reads
      // the draft rather than starting over.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, fresh: false);

      expect(picked(tester), <String>['B1.2']);
    });

    testWidgets('writes nothing until the finish', (tester) async {
      // A draft, as onboarding.md says: the pick is in the notifier and
      // nowhere else. There is no database in this scope to write to, and a
      // write would have thrown for want of one.
      await pump(tester);
      await tester.tap(chip('C1.1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(onboardingProvider).step, 'C1.1');
    });
  });

  group('Not sure? Take a 3-minute check', () {
    testWidgets('opens S3 and comes back with its suggestion picked', (
      tester,
    ) async {
      final answer = Completer<String?>();
      var opened = 0;
      await pump(
        tester,
        onPlacement: () {
          opened++;
          return answer.future;
        },
      );

      await tester.tap(find.text(l10n.onboardingPlacementLink));
      await tester.pump();
      expect(opened, 1);
      expect(picked(tester), <String>['A1.1'], reason: 'nothing back yet');

      // One frame for the await to resume and pick, one to draw the pick.
      answer.complete('B2.1');
      await tester.pump();
      await tester.pump();

      expect(picked(tester), <String>['B2.1']);
      expect(container.read(onboardingProvider).step, 'B2.1');
    });

    testWidgets('and coming back without one leaves the pick alone', (
      tester,
    ) async {
      await pump(tester, onPlacement: () async => null);
      await tester.tap(chip('A2.2'));
      await tester.pump();

      await tester.tap(find.text(l10n.onboardingPlacementLink));
      await tester.pump();

      expect(picked(tester), <String>['A2.2']);
    });

    testWidgets('is a link, and a big enough target', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, onPlacement: () async => null);

      expect(
        tester.getSemantics(find.text(l10n.onboardingPlacementLink)),
        matchesSemantics(
          isLink: true,
          hasTapAction: true,
          label: l10n.onboardingPlacementLink,
        ),
      );
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(l10n.onboardingPlacementLink),
                matching: find.byType(GestureDetector),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      handle.dispose();
    });
  });

  group('the actions', () {
    testWidgets('Continue and Back call back', (tester) async {
      var continued = 0;
      var back = 0;
      await pump(tester, onContinue: () => continued++, onBack: () => back++);

      await tester.tap(find.widgetWithText(DpButton, l10n.continueAction));
      await tester.tap(find.widgetWithText(DpButton, l10n.back));
      await tester.pump();

      expect(<int>[continued, back], <int>[1, 1]);
    });

    testWidgets('page 3 is where Skip appears, in ink on the header', (
      tester,
    ) async {
      await pump(tester, onSkip: () {});
      final tokens = tester.element(find.byType(OnboardingStartPage)).tokens;

      final skip = tester.widget<DpButton>(
        find.widgetWithText(DpButton, l10n.skip),
      );
      expect(skip.colour, tokens.color.onPrimary);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    // One mode per test: swapping containers inside a test leaves Riverpod's
    // dispose timer for the old one pending when the test ends.
    for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
      testWidgets('and ${mode.name} renders it', (tester) async {
        await pump(tester, mode: mode);
        expect(picked(tester), <String>['A1.1']);
      });
    }
  });

  group('accessibility', () {
    testWidgets('the chips grow at 200 % text rather than clip', (
      tester,
    ) async {
      // #36: 200 % text scaling. The artboard's 52 dp is a floor.
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(chip('A1.1')).height, greaterThan(52));
    });

    testWidgets('the chips are one group, and the picked one says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(find.text('A1.1')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          label: 'A1.1\n${l10n.onboardingStepWords(637)}',
        ),
      );

      handle.dispose();
    });
  });
}
