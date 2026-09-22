import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_notifier.g.dart';

/// The plan values S2 is choosing, before they are anything.
///
/// `onboarding.md`: "`OnboardingNotifier` holds draft values; commits in one
/// transaction on finish." The finish is #92. Until then nothing here touches
/// the database, so walking back and forth through the pages changes nothing
/// a learner would see anywhere else.
///
/// The languages are not here — page 2 writes those as they are tapped, see
/// `Languages.chooseMeaning`.
class OnboardingDraft {
  // The documented defaults, read off the settings catalogue rather than
  // written twice — a learner who skips page 4 gets exactly what they would
  // have had if they had never seen it.
  OnboardingDraft({
    this.step = firstStep,
    int? dailyNew,
    int? reviseCount,
    int? studyDaysMask,
  }) : dailyNew = dailyNew ?? SettingKeys.dailyNew.defaultValue,
       reviseCount = reviseCount ?? SettingKeys.reviseCount.defaultValue,
       studyDaysMask = studyDaysMask ?? SettingKeys.studyDaysMask.defaultValue;

  /// BR-COURSE-01's first step, and what page 3 starts on.
  static const String firstStep = 'A1.1';

  /// Page 4's slider: "New words slider 3–30".
  static const int minDailyNew = 3;
  static const int maxDailyNew = 30;

  /// Page 4's stepper, over the range Settings gives `revise_count`.
  static const int minReviseCount = 0;
  static const int maxReviseCount = 100;

  /// The step the learner will start in — a `sublevels.code`.
  final String step;

  /// `daily_new`, `revise_count` and `study_days_mask` — Monday at bit 0.
  final int dailyNew;
  final int reviseCount;
  final int studyDaysMask;

  OnboardingDraft copyWith({
    String? step,
    int? dailyNew,
    int? reviseCount,
    int? studyDaysMask,
  }) => OnboardingDraft(
    step: step ?? this.step,
    dailyNew: dailyNew ?? this.dailyNew,
    reviseCount: reviseCount ?? this.reviseCount,
    studyDaysMask: studyDaysMask ?? this.studyDaysMask,
  );
}

/// Kept alive: the pages come and go as the learner walks through them, and
/// FR-S2-02 wants every value still there on the way back.
@Riverpod(keepAlive: true)
class OnboardingNotifier extends _$OnboardingNotifier {
  @override
  OnboardingDraft build() => OnboardingDraft();

  /// Page 3, or S3's suggestion when the learner comes back from it.
  void chooseStep(String code) => state = state.copyWith(step: code);

  /// Page 4's slider and presets, held to 3–30.
  void setDailyNew(int count) => state = state.copyWith(
    dailyNew: count.clamp(
      OnboardingDraft.minDailyNew,
      OnboardingDraft.maxDailyNew,
    ),
  );

  /// Page 4's stepper, held to 0–100.
  void setReviseCount(int count) => state = state.copyWith(
    reviseCount: count.clamp(
      OnboardingDraft.minReviseCount,
      OnboardingDraft.maxReviseCount,
    ),
  );

  /// Page 4's weekday chips. [weekday] is `DateTime.monday`…`sunday`.
  ///
  /// The last day cannot be turned off: a week with no study days is a plan
  /// that never runs, and FR-S2-04's estimate would divide by zero.
  void toggleStudyDay(int weekday) {
    final bit = 1 << (weekday - 1);
    final next = state.studyDaysMask ^ bit;
    if (next & 127 == 0) return;
    state = state.copyWith(studyDaysMask: next);
  }
}
