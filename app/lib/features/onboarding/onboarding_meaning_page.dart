import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/onboarding/onboarding_shell.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

part 'onboarding_meaning_page.g.dart';

/// `die Wohnung`, A1.1 — the word the spec shows on every card.
///
/// By uid rather than by spelling: progress is keyed on uids, so a content
/// update that changed this one would already be breaking far more than a
/// sample line. A test holds the shipped content.db to it.
const String meaningSampleUid = '0346db60d5618b4a';

/// The sample, from content.db — "German course text comes from content.db".
///
/// `WordWithState` rather than the drift `Word`: riverpod_generator runs in
/// the same build as drift and cannot name a type drift has not written yet.
@riverpod
Future<WordWithState?> meaningSample(Ref ref) =>
    ref.watch(wordRepositoryProvider).find(meaningSampleUid);

/// S2 page 2 · Meaning language. `Onboarding-android.html`.
///
/// A card for each language the course ships (#1081), each showing the same
/// word in it: the chosen one is the first meaning. Under them, *Also show*
/// adds a second, or none. The choice is written as it is tapped — see
/// [Languages.chooseMeaning] — so coming back to this page shows what was
/// picked (FR-S2-02) without a draft to carry it.
class OnboardingMeaningPage extends ConsumerWidget {
  const OnboardingMeaningPage({super.key, this.onContinue, this.onBack});

  final VoidCallback? onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final chosen = ref.watch(languagesProvider).meaning;
    final languages = ref.watch(courseLanguagesProvider).value ?? baseLanguages;
    final sample = ref.watch(meaningSampleProvider).value?.word;
    // Beyond English and Bangla, a card's sample is the course's.
    final course = languages.every((l) => l.code == 'en' || l.code == 'bn')
        ? CourseMeanings.none
        : ref.watch(courseMeaningsProvider).value ?? CourseMeanings.none;

    // A card with nothing to show gets no sample line rather than a dangling
    // arrow: `bangla` is nullable in the schema.
    String? sampleIn(String code) {
      if (sample == null) return null;
      final meaning = Meanings(chosen, course).of(sample, code);
      if (meaning == null) return null;
      final german = [sample.article, sample.german].nonNulls.join(' ');
      return l10n.onboardingMeaningSample(german, meaning);
    }

    void choose(MeaningChoice choice) =>
        ref.read(languagesProvider.notifier).chooseMeaning(choice);

    return OnboardingShell(
      page: OnboardingPage.meaningLanguage,
      headline: l10n.onboardingMeaningHeadline,
      primaryLabel: l10n.continueAction,
      onPrimary: onContinue,
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Room for the badge, which sits 10 dp above the first card's edge.
          const SizedBox(height: 10),
          for (final language in languages)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _LanguageCard(
                // Each named in itself, as a learner looks for it.
                title: language.ownName,
                sample: sampleIn(language.code),
                selected: language.code == chosen.primary,
                // The second chosen first: the two swap places.
                onTap: () => choose(
                  MeaningChoice(
                    language.code,
                    chosen.secondary == language.code
                        ? chosen.primary
                        : chosen.secondary,
                  ),
                ),
              ),
            ),
          SgText(
            l10n.onboardingMeaningAlso,
            role: SgTextRole.label,
            weight: 600,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: AdaptiveTapTarget.runSpacing(32),
            children: <Widget>[
              SgChip(
                label: l10n.onboardingMeaningNone,
                kind: SgChipKind.filter,
                selected: chosen.secondary == null,
                onTap: () => choose(MeaningChoice(chosen.primary)),
              ),
              for (final language in languages)
                if (language.code != chosen.primary)
                  SgChip(
                    label: language.ownName,
                    kind: SgChipKind.filter,
                    selected: chosen.secondary == language.code,
                    onTap: () =>
                        choose(MeaningChoice(chosen.primary, language.code)),
                  ),
            ],
          ),
          // The artboard's 14 dp gap runs between the cards and the note as
          // well, and the note adds 4 of its own.
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SgText(
              l10n.onboardingMeaningNote,
              role: SgTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One option: its name, the sample as it would read, and a Sun tick when
/// chosen.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.title,
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  final String title;

  /// Null until content.db answers, and if it never does — the card still
  /// works as a choice without it.
  final String? sample;
  final bool selected;
  final VoidCallback onTap;

  static const double badge = 26;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      // One of several, so a screen reader says which is picked and that
      // picking another unpicks this.
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Stack(
        // Passthrough, so the card takes the column's full width as the
        // artboard's `width: 100%` does. The default loosens it, and a card
        // with a short sample shrinks to fit its text.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          SgSurface(
            kind: SgSurfaceKind.bar,
            selected: selected,
            onTap: onTap,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgText(title, role: SgTextRole.bodyLarge, weight: 600),
                if (sample != null) ...<Widget>[
                  const SizedBox(height: 4),
                  SgText(
                    sample!,
                    role: SgTextRole.label,
                    weight: 400,
                    color: tokens.color.textSecondary,
                  ),
                ],
              ],
            ),
          ),
          if (selected)
            Positioned(
              top: -10,
              right: -10,
              child: ExcludeSemantics(
                child: Container(
                  width: badge,
                  height: badge,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.color.accent,
                    shape: BoxShape.circle,
                    // The glass artboard gives the badge the glass hairline;
                    // on paper it is the 2 px ink every selected edge has.
                    border: tokens.isGlass
                        ? Border.all(
                            color: tokens.surface.outline,
                            width: tokens.surface.outlineWidth,
                          )
                        : Border.all(color: tokens.color.ink, width: 2),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: tokens.color.onAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
