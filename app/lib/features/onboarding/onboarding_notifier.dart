import 'package:deutschplan/core/providers/app_providers.dart';
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
    bool? reminderOn,
    Clock? reminderTime,
    this.reminderBlocked = false,
    this.voice = VoiceOffer.offered,
  }) : dailyNew = dailyNew ?? SettingKeys.dailyNew.defaultValue,
       reviseCount = reviseCount ?? SettingKeys.reviseCount.defaultValue,
       studyDaysMask = studyDaysMask ?? SettingKeys.studyDaysMask.defaultValue,
       reminderOn = reminderOn ?? SettingKeys.reminderEnabled.defaultValue,
       reminderTime = reminderTime ?? SettingKeys.reminderTime.defaultValue;

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

  /// `reminder_enabled` and `reminder_time` — off, 19:30.
  final bool reminderOn;
  final Clock reminderTime;

  /// The learner turned the switch on and the platform said no. Not a
  /// setting: it says why the switch went back off, so page 5 can tell them.
  final bool reminderBlocked;

  /// Where the Supertonic offer on page 5 stands. In the draft, not the page,
  /// so walking back and forward does not offer — and queue — it twice.
  final VoiceOffer voice;

  OnboardingDraft copyWith({
    String? step,
    int? dailyNew,
    int? reviseCount,
    int? studyDaysMask,
    bool? reminderOn,
    Clock? reminderTime,
    bool? reminderBlocked,
    VoiceOffer? voice,
  }) => OnboardingDraft(
    step: step ?? this.step,
    dailyNew: dailyNew ?? this.dailyNew,
    reviseCount: reviseCount ?? this.reviseCount,
    studyDaysMask: studyDaysMask ?? this.studyDaysMask,
    reminderOn: reminderOn ?? this.reminderOn,
    reminderTime: reminderTime ?? this.reminderTime,
    reminderBlocked: reminderBlocked ?? this.reminderBlocked,
    voice: voice ?? this.voice,
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

  /// Page 5's switch. FR-S2-05: the permission is asked for here — when the
  /// switch goes on — and nowhere earlier. Refused, the switch stays off and
  /// the draft remembers why.
  Future<void> setReminder({required bool on}) async {
    if (!on) {
      state = state.copyWith(reminderOn: false, reminderBlocked: false);
      return;
    }
    // A request that throws — one already running, no activity to show it
    // on — was never answered. Nothing is changed rather than a refusal
    // recorded: the learner has not said no.
    final bool allowed;
    try {
      allowed = await ref.read(notificationPermissionProvider).request();
    } on Object {
      return;
    }
    state = state.copyWith(reminderOn: allowed, reminderBlocked: !allowed);
  }

  void setReminderTime(Clock time) =>
      state = state.copyWith(reminderTime: time);

  /// FR-S2-06: queues Supertonic and lets onboarding carry on. Says whether
  /// the queueing worked; the bytes arrive long after this returns.
  Future<bool> downloadVoice() async {
    if (state.voice == VoiceOffer.started) return true;
    try {
      await ref.read(modelDownloadsProvider).start(supertonic);
    } on Object {
      return false;
    }
    state = state.copyWith(voice: VoiceOffer.started);
    return true;
  }

  void deferVoice() => state = state.copyWith(voice: VoiceOffer.deferred);

  /// The model id `assets/models/manifest.json` gives the voice.
  static const String supertonic = 'supertonic3';
}

/// Page 5's offer of the better voice.
enum VoiceOffer {
  /// *Download now* and *Later* are on the card.
  offered,

  /// Queued — FR-S2-06's "in the background".
  started,

  /// *Later*: Settings has it whenever they want it.
  deferred,
}
