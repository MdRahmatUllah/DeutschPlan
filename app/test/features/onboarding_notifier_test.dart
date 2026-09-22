import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// S2's draft — `onboarding.md`: "`OnboardingNotifier` holds draft values".
void main() {
  test('starts on A1.1, the first step of the course', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(onboardingProvider).step, 'A1.1');
  });

  test('holds new words to 3–30 and revisions to 0–100', () {
    // The slider cannot leave 3–30 by itself, but a preset or restart setup
    // can hand the draft anything; the rule lives here, not in the widget.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(onboardingProvider.notifier);

    notifier.setDailyNew(99);
    expect(container.read(onboardingProvider).dailyNew, 30);
    notifier.setDailyNew(1);
    expect(container.read(onboardingProvider).dailyNew, 3);

    notifier.setReviseCount(250);
    expect(container.read(onboardingProvider).reviseCount, 100);
    notifier.setReviseCount(-4);
    expect(container.read(onboardingProvider).reviseCount, 0);
  });

  test('starts on the documented pace defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final draft = container.read(onboardingProvider);

    expect(
      (draft.dailyNew, draft.reviseCount, draft.studyDaysMask),
      (7, 10, 127),
    );
  });

  test('FR-S2-02 outlives the pages that show it', () async {
    // Going back from page 3 to page 2 unmounts page 3, and nothing else
    // watches the draft. An auto-disposing provider would go with it, and
    // coming forward again would show A1.1 however the learner had chosen.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final page = container.listen(onboardingProvider, (_, _) {});
    container.read(onboardingProvider.notifier).chooseStep('B1.2');
    page.close();

    // Long enough for the dispose Riverpod schedules when the last listener
    // leaves.
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(onboardingProvider).step, 'B1.2');
  });
}
