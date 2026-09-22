@TestOn('vm')
library;

import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/features/bootstrap/bootstrap_error_screen.dart';
import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S1 · the bootstrap error state — #86.
///
/// FR-S1-03: "on bootstrap failure show a full-screen error with *Retry* and
/// *Export progress* — never a blank screen." The goldens live in
/// `test/golden/bootstrap_error_golden_test.dart`; this is the behaviour an
/// image cannot show.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  BootstrapFailure failureOf(BootstrapStep step, {bool canExport = false}) =>
      BootstrapFailure(
        step: step,
        error: 'something went wrong',
        stackTrace: StackTrace.empty,
        // `canExport` is derived from whether the database opened, and the only
        // way to make it true is to hand over a database.
        db: canExport ? AppDatabase.memory() : null,
      );

  Future<void> pump(
    WidgetTester tester, {
    required BootstrapFailure failure,
    VoidCallback? onRetry,
    VoidCallback? onExport,
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
        home: BootstrapErrorScreen(
          failure: failure,
          onRetry: onRetry,
          onExport: onExport,
        ),
      ),
    );
    await tester.pump();
  }

  final Finder retry = find.widgetWithText(DpButton, 'Retry');
  final Finder export = find.widgetWithText(DpButton, 'Export progress');

  group('FR-S1-03 — never a blank screen', () {
    testWidgets('every failure step says what went wrong', (tester) async {
      // A step with no message would render an empty screen, which is the one
      // outcome the rule forbids.
      for (final (step, message) in <(BootstrapStep, String)>[
        (BootstrapStep.database, l10n.bootstrapErrorDatabase),
        (BootstrapStep.content, l10n.bootstrapErrorContent),
        (BootstrapStep.settings, l10n.bootstrapErrorSettings),
      ]) {
        await pump(tester, failure: failureOf(step));

        expect(find.text(message), findsOneWidget, reason: step.name);
      }
    });

    testWidgets('and the mark stays, so it is still this app', (tester) async {
      // The learner is looking at S1 when bootstrap fails. Losing the mark
      // makes the failure read as a crash into something else.
      await pump(tester, failure: failureOf(BootstrapStep.content));

      expect(find.byType(SplashMark), findsOneWidget);
    });

    testWidgets('Retry is always offered', (tester) async {
      await pump(tester, failure: failureOf(BootstrapStep.database));

      expect(retry, findsOneWidget);
    });
  });

  group('FR-S1-03 — Export progress', () {
    testWidgets('is offered when the database opened', (tester) async {
      await pump(
        tester,
        failure: failureOf(BootstrapStep.content, canExport: true),
      );

      expect(export, findsOneWidget);
    });

    testWidgets('and is absent when it did not', (tester) async {
      // A button that cannot do what it says is worse than no button — the
      // learner taps it precisely because their data is what worries them.
      await pump(tester, failure: failureOf(BootstrapStep.database));

      expect(export, findsNothing);
    });

    testWidgets('exporting works from here, with no shell running', (
      tester,
    ) async {
      // The criterion: "export from here works even when the normal shell
      // failed to start". There is no router and no provider scope on this
      // screen, so the callback is the whole mechanism.
      var exported = 0;
      await pump(
        tester,
        failure: failureOf(BootstrapStep.content, canExport: true),
        onExport: () => exported++,
      );

      await tester.tap(export);
      await tester.pump();

      expect(exported, 1);
    });
  });

  group('the buttons', () {
    testWidgets('Retry calls back', (tester) async {
      var retried = 0;
      await pump(
        tester,
        failure: failureOf(BootstrapStep.content),
        onRetry: () => retried++,
      );

      await tester.tap(retry);
      await tester.pump();

      expect(retried, 1);
    });

    testWidgets('a retry already running disables rather than hides it', (
      tester,
    ) async {
      // A button that vanishes under the finger reads as a crash. Disabled
      // says "I heard you".
      await pump(tester, failure: failureOf(BootstrapStep.content));

      expect(retry, findsOneWidget);
      expect(tester.widget<DpButton>(retry).onPressed, isNull);
    });

    testWidgets('Retry is the primary action and export is not', (
      tester,
    ) async {
      // Two buttons of equal weight would leave the learner choosing between
      // them. Retry is what fixes it; export is the escape hatch.
      await pump(
        tester,
        failure: failureOf(BootstrapStep.content, canExport: true),
      );

      expect(tester.widget<DpButton>(retry).kind, DpButtonKind.primary);
      expect(tester.widget<DpButton>(export).kind, DpButtonKind.text);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome, no raw colours', (tester) async {
      // The criterion, asserted rather than assumed: the architecture guards
      // cover the source, this covers what is actually on screen.
      await pump(tester, failure: failureOf(BootstrapStep.content));

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('the field is the primary token', (tester) async {
      await pump(tester, failure: failureOf(BootstrapStep.content));

      final tokens = Theme.of(tester.element(find.byType(BootstrapErrorScreen)))
          .extension<DpTokens>()!;

      expect(
        tester
            .widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold))
            .backgroundColor,
        tokens.color.primary,
      );
    });

    testWidgets('and glass puts it on the aurora', (tester) async {
      await pump(
        tester,
        failure: failureOf(BootstrapStep.content),
        mode: DpMode.glass,
      );

      expect(find.byType(AuroraBackdrop), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the message is read, the mark is not', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, failure: failureOf(BootstrapStep.content));

      expect(find.bySemanticsLabel(l10n.bootstrapErrorContent), findsOneWidget);
      expect(find.bySemanticsLabel('D'), findsNothing);

      handle.dispose();
    });
  });
}
