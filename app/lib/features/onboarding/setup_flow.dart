import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/onboarding/onboarding_notifier.dart';

part 'setup_flow.g.dart';

/// Where finishing setup stands.
enum SetupStatus { idle, finishing, failed }

/// The two ends of S2: finishing it (FR-S2-03, and FR-S2-01's Skip), and
/// starting it again from Settings.
///
/// Apart from the draft because the draft is kept alive and these reach the
/// repositories, which are not — and because a finish in progress is
/// something the page shows, not a value the learner chose.
@riverpod
class SetupFlow extends _$SetupFlow {
  @override
  SetupStatus build() => SetupStatus.idle;

  /// FR-S2-03: commits the draft in one transaction and plans day 1. True
  /// when setup is done and Today can open. FR-S2-01's *Skip* is this too:
  /// the draft keeps what the learner chose, and the defaults for what they
  /// never touched (the owner, 2026-09-28, #1011 ME-11).
  Future<bool> finish() async {
    if (state == SetupStatus.finishing) return false;
    state = SetupStatus.finishing;

    final draft = ref.read(onboardingProvider);
    final today = ref.read(todayProvider);

    try {
      await ref
          .read(setupRepositoryProvider)
          .commit(draft.choice, today: today);
      // "…and open Today with the first day planned": planned here, so Today
      // opens on a plan rather than generating one under the learner's thumb.
      await ref.read(planEngineProvider).openDay(today);
    } on Object {
      if (ref.mounted) state = SetupStatus.failed;
      return false;
    }

    // The draft is left for the caller to clear once it has left the page:
    // cleared here, the page still on screen redraws with the defaults for a
    // frame before Today arrives.
    if (ref.mounted) state = SetupStatus.idle;
    return true;
  }

  /// Restart setup (`onboarding.md`, States): page 1 hidden, every page
  /// pre-filled with what the learner has now. Progress is not touched here
  /// or by the finish.
  Future<void> beginRestart() async {
    final settings = ref.read(settingsProvider);
    final step = await ref.read(setupRepositoryProvider).activeStep();
    ref
        .read(onboardingProvider.notifier)
        .prefill(
          step: step ?? OnboardingDraft.firstStep,
          dailyNew: settings.read(SettingKeys.dailyNew),
          reviseCount: settings.read(SettingKeys.reviseCount),
          studyDaysMask: settings.read(SettingKeys.studyDaysMask),
          reminderOn: settings.read(SettingKeys.reminderEnabled),
          reminderTime: settings.read(SettingKeys.reminderTime),
        );
  }
}
