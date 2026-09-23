import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_coach_mark.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// FR-S2-03's one-time coach mark on Today's primary button — #92.
///
/// T1 (#95) is where it is mounted; these hold the mark and the rule that it
/// appears once, so #95 only has to put it round its `PrimaryActionBar`.
void main() {
  const message = 'Start here · today\'s words are ready';

  Widget harness({
    required bool visible,
    VoidCallback? onDismissed,
    VoidCallback? onShown,
  }) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DpCoachMark(
            message: message,
            visible: visible,
            onDismissed: onDismissed ?? () {},
            onShown: onShown,
            child: DpButton(label: 'Start today', onPressed: () {}),
          ),
        ),
      ),
    ),
  );

  group('DpCoachMark', () {
    testWidgets('shows above its target, and says so once', (tester) async {
      var shown = 0;
      await tester.pumpWidget(harness(visible: true, onShown: () => shown++));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text(message)).dy,
        lessThan(tester.getTopLeft(find.byType(DpButton)).dy),
        reason: 'above the button, not over it',
      );

      await tester.pump();
      await tester.pump();
      expect(shown, 1);
    });

    testWidgets('and a tap on it dismisses it', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        harness(visible: true, onDismissed: () => dismissed++),
      );
      await tester.pump();

      await tester.tap(find.text(message));
      expect(dismissed, 1);
    });

    testWidgets('is absent when not asked for, and goes when told', (
      tester,
    ) async {
      await tester.pumpWidget(harness(visible: false));
      await tester.pump();
      expect(find.text(message), findsNothing);

      await tester.pumpWidget(harness(visible: true));
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      await tester.pumpWidget(harness(visible: false));
      await tester.pump();
      expect(find.text(message), findsNothing);
    });

    testWidgets('and the target underneath still works', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: DpCoachMark(
                message: message,
                visible: true,
                onDismissed: () {},
                child: DpButton(
                  label: 'Start today',
                  onPressed: () => pressed++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Start today'));
      expect(pressed, 1);
    });
  });

  group('shown once and never again', () {
    testWidgets('the first Today after setup shows it; the next does not', (
      tester,
    ) async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);

      Future<void> openToday() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[settingsProvider.overrideWithValue(settings)],
            child: Consumer(
              builder: (context, ref, _) => harness(
                visible: ref.watch(coachMarkProvider),
                onShown: () => ref.read(coachMarkProvider.notifier).markShown(),
                onDismissed: () =>
                    ref.read(coachMarkProvider.notifier).dismiss(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      await openToday();
      expect(find.text(message), findsOneWidget);
      expect(settings.read(SettingKeys.coachMarkSeen), isTrue);

      // Marked as shown, and still there — it stays until the learner is done
      // with it, however many frames that takes.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.text(message));
      await tester.pump();
      await tester.pump();
      expect(find.text(message), findsNothing, reason: 'dismissed');

      // A new launch: a fresh scope over the same settings.
      await tester.pumpWidget(const SizedBox());
      await openToday();
      expect(find.text(message), findsNothing);
    });
  });
}
