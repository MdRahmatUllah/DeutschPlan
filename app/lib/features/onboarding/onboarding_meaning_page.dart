import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
/// Three cards, each showing the same word the way that option would. The
/// choice is written as it is tapped — see [Languages.chooseMeaning] — so
/// coming back to this page shows what was picked (FR-S2-02) without a draft
/// to carry it.
class OnboardingMeaningPage extends ConsumerWidget {
  const OnboardingMeaningPage({super.key, this.onContinue, this.onBack});

  final VoidCallback? onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final chosen = ref.watch(languagesProvider).meaning;
    final sample = ref.watch(meaningSampleProvider).value?.word;

    String? sampleFor(MeaningLanguage option) {
      if (sample == null) return null;
      final bangla = sample.bangla;

      // `bangla` is nullable in the schema. A card with nothing to show gets
      // no sample line rather than a dangling arrow; *Both* falls back to the
      // English it does have.
      final meaning = switch (option) {
        MeaningLanguage.english => sample.english,
        MeaningLanguage.bangla => bangla,
        MeaningLanguage.both =>
          bangla == null
              ? sample.english
              : l10n.onboardingMeaningSampleBoth(sample.english, bangla),
      };
      if (meaning == null) return null;
      final german = [sample.article, sample.german].nonNulls.join(' ');
      return l10n.onboardingMeaningSample(german, meaning);
    }

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
          for (final option in MeaningLanguage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _LanguageCard(
                title: switch (option) {
                  MeaningLanguage.english => l10n.onboardingMeaningEnglish,
                  MeaningLanguage.bangla => l10n.onboardingMeaningBangla,
                  MeaningLanguage.both => l10n.onboardingMeaningBoth,
                },
                sample: sampleFor(option),
                selected: option == chosen,
                onTap: () =>
                    ref.read(languagesProvider.notifier).chooseMeaning(option),
              ),
            ),
          // The artboard's 14 dp gap runs between the cards and the note as
          // well, and the note adds 4 of its own.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DpText(
              l10n.onboardingMeaningNote,
              role: DpTextRole.caption,
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
      // One of three, so a screen reader says which is picked and that
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
          DpSurface(
            kind: DpSurfaceKind.bar,
            selected: selected,
            onTap: onTap,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DpText(title, role: DpTextRole.bodyLarge, weight: 600),
                if (sample != null) ...<Widget>[
                  const SizedBox(height: 4),
                  DpText(
                    sample!,
                    role: DpTextRole.label,
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
