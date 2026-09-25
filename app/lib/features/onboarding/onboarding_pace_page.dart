import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_slider.dart';
import 'package:deutschplan/core/components/dp_stepper.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 4 · Daily pace. `OnboardingPace-android.html`.
///
/// New words a day, with FR-S2-04's estimate under it as it moves; three
/// presets; revisions a day; and which days are study days. All of it goes to
/// the draft — `daily_new`, `revise_count` and `study_days_mask` are written
/// when the finish commits it (#92).
class OnboardingPacePage extends ConsumerWidget {
  const OnboardingPacePage({
    super.key,
    this.onContinue,
    this.onBack,
    this.onSkip,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  /// The presets `onboarding.md` names: Relaxed 5 · Steady 7 · Intensive 15.
  static const int relaxed = 5;
  static const int steady = 7;
  static const int intensive = 15;

  /// The artboard's 18 between the four groups.
  static const double groupGap = 18;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final setup = ref.watch(setupFlowProvider);
    final tokens = context.tokens;
    final draft = ref.watch(onboardingProvider);
    // Read when a control fires, not now — the same as page 3.
    OnboardingNotifier notifier() => ref.read(onboardingProvider.notifier);
    final steps = ref.watch(courseStepsProvider).value;

    // FR-S2-04, on every change: the chosen step's words, from content.db.
    final words = steps
        ?.where((step) => step.code == draft.step)
        .map((step) => step.wordCount)
        .firstOrNull;
    final days = words == null
        ? null
        : courseDays(
            words: words,
            dailyNew: draft.dailyNew,
            studyDaysMask: draft.studyDaysMask,
          );

    return OnboardingShell(
      page: OnboardingPage.dailyPace,
      headline: l10n.onboardingPaceHeadline,
      primaryLabel: l10n.continueAction,
      onPrimary: onContinue,
      onBack: onBack,
      onSkip: onSkip,
      busy: setup == SetupStatus.finishing,
      error: setup == SetupStatus.failed ? l10n.onboardingFinishFailed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: DpText(
                  l10n.onboardingPaceNewWords,
                  role: DpTextRole.body,
                  weight: 600,
                ),
              ),
              DpText('${draft.dailyNew}', role: DpTextRole.title, weight: 700),
            ],
          ),
          const SizedBox(height: 6),
          DpSlider(
            value: draft.dailyNew,
            min: OnboardingDraft.minDailyNew,
            max: OnboardingDraft.maxDailyNew,
            onChanged: (count) => notifier().setDailyNew(count),
            label: l10n.onboardingPaceNewWords,
          ),
          const SizedBox(height: 6),
          // Live, so a screen reader hears the estimate move with the slider
          // rather than having to go looking for it.
          Semantics(
            liveRegion: true,
            child: DpText(
              days == null
                  ? ''
                  : l10n.onboardingPaceEstimate(
                      days,
                      draft.step,
                      draft.dailyNew,
                    ),
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ),
          const SizedBox(height: groupGap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (count, label) in <(int, String)>[
                (relaxed, l10n.onboardingPaceRelaxed(relaxed)),
                (steady, l10n.onboardingPaceSteady(steady)),
                (intensive, l10n.onboardingPaceIntensive(intensive)),
              ])
                DpChip(
                  label: label,
                  kind: DpChipKind.filter,
                  selected: draft.dailyNew == count,
                  onTap: () => notifier().setDailyNew(count),
                ),
            ],
          ),
          const SizedBox(height: groupGap),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(
                      l10n.onboardingPaceRevisions,
                      role: DpTextRole.body,
                      weight: 600,
                    ),
                    const SizedBox(height: 1),
                    DpText(
                      l10n.onboardingPaceRevisionsNote,
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              DpStepper(
                value: draft.reviseCount,
                min: OnboardingDraft.minReviseCount,
                max: OnboardingDraft.maxReviseCount,
                onChanged: (count) => notifier().setReviseCount(count),
                decreaseLabel: l10n.onboardingPaceRevisionsDecrease,
                increaseLabel: l10n.onboardingPaceRevisionsIncrease,
              ),
            ],
          ),
          const SizedBox(height: groupGap),
          DpText(
            l10n.onboardingPaceStudyDays,
            role: DpTextRole.body,
            weight: 600,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final (index, (short, full)) in studyWeekdays(
                l10n,
              ).indexed) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(
                  child: StudyDayToggle(
                    short: short,
                    full: full,
                    on: draft.studyDaysMask & (1 << index) != 0,
                    onTap: () => notifier().toggleStudyDay(index + 1),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The week's (short, full) names, Monday first, matching the mask's bit 0
/// and `DateTime.monday`. S2 page 4's and M5's day pills (#147).
List<(String, String)> studyWeekdays(AppLocalizations l10n) =>
    <(String, String)>[
      (l10n.weekdayShortMon, l10n.weekdayMon),
      (l10n.weekdayShortTue, l10n.weekdayTue),
      (l10n.weekdayShortWed, l10n.weekdayWed),
      (l10n.weekdayShortThu, l10n.weekdayThu),
      (l10n.weekdayShortFri, l10n.weekdayFri),
      (l10n.weekdayShortSat, l10n.weekdaySat),
      (l10n.weekdayShortSun, l10n.weekdaySun),
    ];

/// One weekday: Lagoon when it is a study day, an outline when it is not.
/// S2 page 4's, and M5's (#147).
class StudyDayToggle extends StatelessWidget {
  const StudyDayToggle({
    required this.short,
    required this.full,
    required this.on,
    required this.onTap,
    super.key,
  });

  final String short;

  /// Read aloud instead of [short]: "Mo" is not a word.
  final String full;
  final bool on;
  final VoidCallback onTap;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      toggled: on,
      button: true,
      label: full,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // A floor, not a fixed height. Two letters fit at 200 %, but a
          // longer weekday name or a larger scale grows the chip rather than
          // clipping it.
          constraints: const BoxConstraints(minHeight: height),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? tokens.color.primary : null,
            borderRadius: BorderRadius.circular(tokens.shape.chip),
            border: Border.all(
              // The ink edge marks a day that is on; an off day has the same
              // hairline every unselected control has.
              color: on ? tokens.color.ink : tokens.surface.outline,
              width: on || !tokens.isGlass ? 1.5 : tokens.surface.outlineWidth,
            ),
          ),
          child: DpText(
            short,
            role: DpTextRole.label,
            weight: 700,
            color: on ? tokens.color.onPrimary : tokens.color.ink,
          ),
        ),
      ),
    );
  }
}
