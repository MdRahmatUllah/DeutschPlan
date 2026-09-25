// What #169's three smoke files share: launching the real app, waiting on a
// real clock, and the walks more than one of them takes.
//
// Real time, not fake: this runs on the emulator (`tools/smoke.py`), where
// `pump(duration)` waits that long for real. `pumpAndSettle` is not used —
// the aurora, the exam clock and the card motion keep scheduling frames, so it
// would never settle.

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/learn/learn_screen.dart' show StepTile;
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' as app;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// How long S1 may take to hand over. A first run copies the 8 MB course and
/// a debug build is JIT, so this is generous.
const Duration launchTimeout = Duration(seconds: 90);

/// How long a route has to finish sliding in before its buttons are tapped:
/// mid-transition, the page underneath still shows the same *Continue*.
const Duration settle = Duration(milliseconds: 600);

/// The exam questions answered before the kill, and what was typed in each —
/// what exam_resume_test.dart expects to find again.
const int answeredBeforeKill = 3;
String typedAnswer(int question) => 'smoke $question';

/// Starts the app as the launcher would, and returns the copy it shows:
/// English, `ui_language`'s default (user-database.md), whatever the phone's.
Future<AppLocalizations> launch(WidgetTester tester) async {
  await app.main();
  return AppLocalizations.delegate.load(app.supportedLocales.first);
}

/// Pumps until [finder] finds something, or fails after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty, '$finder', timeout);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what,
  Duration timeout,
) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > timeout) {
      throw TestFailure('Waited $timeout and never saw: $what');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits for [finder], lets the route settle, and taps the first match,
/// scrolled into view.
Future<void> tapOn(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  await pumpUntil(tester, finder, timeout: timeout);
  await tester.pump(settle);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump(settle);
}

/// A widget by its semantics label: the icon buttons (pause, navigator)
/// carry one and no text. Read off the `Semantics` widget, so it works with
/// the semantics tree off.
Finder semanticsLabelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Whether S1 handed over to S2 (no enrollment) rather than T1 (`splash.md`).
Future<bool> startsInSetup(WidgetTester tester, AppLocalizations l10n) async {
  final setup = find.text(l10n.onboardingWelcomeStart);
  final today = find.byType(PrimaryActionBar);
  await _pumpUntil(
    tester,
    () => setup.evaluate().isNotEmpty || today.evaluate().isNotEmpty,
    'S2 page 1 or T1',
    launchTimeout,
  );
  return setup.evaluate().isNotEmpty;
}

/// S2's five pages with their defaults — the first step, A1.1 — then
/// *Start learning* (FR-S2-03), which opens Today.
Future<void> onboard(WidgetTester tester, AppLocalizations l10n) async {
  await tapOn(tester, find.text(l10n.onboardingWelcomeStart));
  for (final headline in <String>[
    l10n.onboardingMeaningHeadline,
    l10n.onboardingStartHeadline,
    l10n.onboardingPaceHeadline,
  ]) {
    await pumpUntil(tester, find.text(headline));
    await tapOn(tester, find.text(l10n.continueAction));
  }
  await pumpUntil(tester, find.text(l10n.onboardingVoiceHeadline));
  await tapOn(tester, find.text(l10n.onboardingStartLearning));
  await pumpUntil(tester, find.byType(PrimaryActionBar));
}

/// BR-EXAM-01 opens a step's mocks once 90 % of its words are introduced:
/// weeks of study on a fresh install. The smoke is about the runner, not the
/// threshold (unit-tested on its own), so it goes to 0 — below Settings'
/// 50–100, which only a test sets.
Future<void> unlockExams(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(app.DeutschPlanApp)),
    listen: false,
  );
  await container
      .read(settingsProvider)
      .write(SettingKeys.examUnlockPercent, 0);
}

/// Learn → A1.1 → Exams: L10, with its three mocks.
Future<void> openExamHub(WidgetTester tester, AppLocalizations l10n) async {
  await tapOn(tester, find.text(l10n.tabLearn));
  // The tile's own "A1.1": the header names the step too.
  await tapOn(tester, find.widgetWithText(StepTile, OnboardingDraft.firstStep));
  await tapOn(tester, find.text(l10n.stepTabExams));
  // The papers are drawn on first sight, which takes a moment in debug.
  await pumpUntil(
    tester,
    find.text(l10n.examHubMock(1)),
    timeout: const Duration(seconds: 60),
  );
}
