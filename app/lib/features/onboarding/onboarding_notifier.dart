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
  const OnboardingDraft({this.step = firstStep});

  /// BR-COURSE-01's first step, and what page 3 starts on.
  static const String firstStep = 'A1.1';

  /// The step the learner will start in — a `sublevels.code`.
  final String step;

  OnboardingDraft copyWith({String? step}) =>
      OnboardingDraft(step: step ?? this.step);
}

/// Kept alive: the pages come and go as the learner walks through them, and
/// FR-S2-02 wants every value still there on the way back.
@Riverpod(keepAlive: true)
class OnboardingNotifier extends _$OnboardingNotifier {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  /// Page 3, or S3's suggestion when the learner comes back from it.
  void chooseStep(String code) => state = state.copyWith(step: code);
}
