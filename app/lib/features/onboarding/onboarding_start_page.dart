import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_start_page.g.dart';

/// The twelve steps and their word counts, from `c.sublevels` — never
/// written into the screen, so a content update that moves a word moves the
/// count with it.
@riverpod
Future<List<CourseStep>> courseSteps(Ref ref) =>
    ref.watch(contentDaoProvider).courseSteps();

/// S2 page 3 · Starting point. `OnboardingStart-android.html`.
///
/// One chip per step, two to a level, in BR-COURSE-01's order. A1.1 starts
/// picked. The link under them opens S3, whose suggestion comes back picked.
class OnboardingStartPage extends ConsumerWidget {
  const OnboardingStartPage({
    super.key,
    this.onContinue,
    this.onBack,
    this.onSkip,
    this.onPlacement,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  /// Opens S3. Completes with the step it suggests, or null when the learner
  /// comes back without taking it.
  final Future<String?> Function()? onPlacement;

  static const double rowGap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final setup = ref.watch(setupFlowProvider);
    final chosen = ref.watch(onboardingProvider).step;
    final steps = ref.watch(courseStepsProvider).value ?? const <CourseStep>[];

    // Level by level, keeping the order the steps arrived in. A map literal
    // is insertion-ordered, so this is the grouping and nothing else.
    final levels = <String, List<CourseStep>>{};
    for (final step in steps) {
      levels.putIfAbsent(step.levelCode, () => <CourseStep>[]).add(step);
    }

    Future<void> placement() async {
      final suggested = await onPlacement!();
      if (suggested != null && context.mounted) {
        ref.read(onboardingProvider.notifier).chooseStep(suggested);
      }
    }

    return OnboardingShell(
      page: OnboardingPage.startingPoint,
      headline: l10n.onboardingStartHeadline,
      primaryLabel: l10n.continueAction,
      onPrimary: onContinue,
      onBack: onBack,
      onSkip: onSkip,
      busy: setup == SetupStatus.finishing,
      error: setup == SetupStatus.failed ? l10n.onboardingFinishFailed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final MapEntry(key: level, value: inLevel) in levels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: rowGap),
              child: _LevelRow(
                level: level,
                steps: inLevel,
                chosen: chosen,
                onChoose: (code) =>
                    ref.read(onboardingProvider.notifier).chooseStep(code),
              ),
            ),
          // The artboard's 12 between the chips and the link, plus the link's
          // own 4 — less the last row's 8, already spent.
          const SizedBox(height: 12 + 4 - rowGap),
          _PlacementLink(onTap: onPlacement == null ? null : placement),
        ],
      ),
    );
  }
}

/// "A1" and its two steps.
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.steps,
    required this.chosen,
    required this.onChoose,
  });

  final String level;
  final List<CourseStep> steps;
  final String chosen;
  final void Function(String) onChoose;

  static const double labelWidth = 28;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: DpText(
            level,
            role: DpTextRole.label,
            weight: 700,
            color: tokens.color.textSecondary,
          ),
        ),
        // The artboard's 8 dp gap, between the label and each chip alike.
        for (final step in steps) ...<Widget>[
          const SizedBox(width: OnboardingStartPage.rowGap),
          Expanded(
            child: _StepChip(
              step: step,
              selected: step.code == chosen,
              onTap: () => onChoose(step.code),
            ),
          ),
        ],
      ],
    );
  }
}

/// One step: its code, and how many words it holds.
class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.step,
    required this.selected,
    required this.onTap,
  });

  final CourseStep step;
  final bool selected;
  final VoidCallback onTap;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    return Semantics(
      // Twelve choices, one picked — read as a group, like page 2's cards.
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        selected: selected,
        radius: tokens.shape.button,
        onTap: onTap,
        // The artboard's 52 as a floor, not a fixed size: at 200 % text the
        // code and the count need more, and the chip grows rather than
        // clipping them.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DpText(step.code, role: DpTextRole.body, weight: 700),
                const SizedBox(height: 1),
                DpText(
                  l10n.onboardingStepWords(step.wordCount),
                  role: DpTextRole.caption,
                  weight: 500,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// *Not sure? Take a 3-minute check* — a link, not a button, so it sits at
/// the chips' edge rather than a text button's 12 dp in.
class _PlacementLink extends StatelessWidget {
  const _PlacementLink({required this.onTap});

  final VoidCallback? onTap;

  /// accessibility-performance.md's tap target, which the drawn text is well
  /// under.
  static const double minTapHeight = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final colour = onTap == null
        ? tokens.color.textSecondary
        : tokens.color.link;

    return Semantics(
      link: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTapHeight),
          child: Row(
            children: <Widget>[
              Flexible(
                child: DpText(
                  l10n.onboardingPlacementLink,
                  role: DpTextRole.body,
                  weight: 600,
                  color: colour,
                ),
              ),
              const SizedBox(width: 2),
              ExcludeSemantics(
                child: Icon(Icons.chevron_right, size: 18, color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
