import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'study_rating.g.dart';

/// FR-T2-05: the days each rating would schedule [uid] for, from its
/// current FSRS state.
///
/// A provider per card, so it is computed once when the rating bar first
/// shows — on reveal — and kept while the card is up, not recomputed per
/// frame.
@riverpod
Future<Map<Rating, int>> studyIntervals(Ref ref, String uid) =>
    ref.watch(ratingServiceProvider).preview(uid);

/// The rating bar and the prompt above it, once the card is turned over.
class StudyRatingActions extends ConsumerWidget {
  const StudyRatingActions({
    required this.uid,
    required this.prompt,
    required this.onRated,
    this.missed = false,
    super.key,
  });

  final String uid;

  /// After a wrong cloze answer: Again and Hard only (#345).
  final bool missed;

  /// "How well did you remember it?…" on the back, "How well did you know
  /// it?" after a cloze.
  final String prompt;

  final ValueChanged<Rating> onRated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final days = ref.watch(studyIntervalsProvider(uid)).value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          prompt,
          role: DpTextRole.caption,
          color: tokens.color.textSecondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        DpRatingBar(
          // Held until the previews exist: a rating tapped before its
          // interval shows is a rating made blind.
          enabled: days != null,
          only: missed ? const <DpRating>{DpRating.again, DpRating.hard} : null,
          intervals: <DpRating, String>{
            for (final rating in DpRating.values)
              rating: switch (days?[Rating.parse(rating.value)]) {
                final n? => l10n.studyIntervalDays(n),
                null => '',
              },
          },
          onRated: (rating) => onRated(Rating.parse(rating.value)),
        ),
      ],
    );
  }
}
