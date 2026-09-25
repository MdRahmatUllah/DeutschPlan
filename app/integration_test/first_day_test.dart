// #169, flow 1 of 2: a fresh install, set up, studies its first day and is
// told the day is done. Run by `tools/smoke.py`, which uninstalls first.

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'smoke.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'FR-S2-03 FR-T1-03 FR-T2-02 FR-T5-04 FR-T6-01: a fresh install sets up, '
    'studies day 1 and reaches T6',
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      final l10n = await launch(tester);
      expect(
        await startsInSetup(tester, l10n),
        isTrue,
        reason:
            'a fresh install opens S2 (splash.md): run tools/smoke.py, '
            'which uninstalls the app first',
      );
      await onboard(tester, l10n);

      // FR-S2-03: Today opens on day 1, planned; FR-T1-03: its button
      // studies every open block.
      await tapOn(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is PrimaryActionBar && widget.action == TodayAction.start,
        ),
      );
      await _studyTheDay(tester, l10n);

      expect(find.text(l10n.dayCompleteTitle), findsOneWidget);
      expect(find.text(l10n.dayCompleteBack), findsOneWidget);
      // T6 leads to T1 by itself after 4 s, where the day reads as done.
      await pumpUntil(
        tester,
        find.text(l10n.todayAllDone),
        timeout: const Duration(seconds: 15),
      );
    },
  );
}

/// T2 → T3 → T5 → T6, whichever of them the day has, until T6 shows.
///
/// Day 1 is new words only: no revisions yet, no grammar due (grammar_state is
/// empty), and every card plain — `card_mode` turns cloze only after two
/// Good ratings, so no cloze card can come up today. Once the words are
/// learned, `SentencePicker.forDay` may find sentences for them, and T3 then
/// leads to T5 before T6; with none, T2 goes straight to T6.
Future<void> _studyTheDay(WidgetTester tester, AppLocalizations l10n) async {
  final dayComplete = find.text(l10n.dayCompleteTitle);
  final summary = find.byType(StudySummarySheet);
  final moves = <Finder>[
    // T2 face down: turn it over (FR-T2-01).
    find.text(l10n.studyShowMeaning),
    // T2 face up: Good (FR-T2-02). Disabled until the intervals load, so a
    // tap that did nothing is simply tried again.
    find.text(l10n.ratingGood),
    // T5: each sentence understood; the last closes to T6 (FR-T5-04).
    find.text(l10n.sentencesUnderstood),
  ];

  final clock = Stopwatch()..start();
  while (dayComplete.evaluate().isEmpty) {
    if (clock.elapsed > const Duration(minutes: 5)) {
      throw TestFailure('Day 1 never reached T6 in 5 minutes');
    }

    // T3's first next step (FR-T3-02), the day's sentences. Tapped once:
    // a second tap while T5 replaces the session would replace it twice.
    if (summary.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: summary, matching: find.byType(DpButton)).first,
        warnIfMissed: false,
      );
      for (var i = 0; i < 30 && summary.evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      continue;
    }

    for (final move in moves) {
      if (move.evaluate().isNotEmpty) {
        await tester.tap(move.first, warnIfMissed: false);
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
  }
}
