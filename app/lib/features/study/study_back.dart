import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show customId;
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'study_back.g.dart';

/// An example sentence on the back: the German and its translation.
typedef StudyExample = ({String german, String? english});

/// An interference tip, in English and, when the course has it, Bangla.
typedef StudyTip = ({String en, String? bn});

/// What the back shows beyond the word's own row.
typedef StudyBackExtras = ({List<StudyExample> examples, StudyTip? tip});

/// The back's two examples and its interference tip, if the word has one.
/// A word of the learner's own has its own example, if they gave one, and no
/// tip (#363).
@riverpod
Future<StudyBackExtras> studyBack(Ref ref, String uid) async {
  if (customId(uid) case final id?) {
    final mine = await ref.watch(wordRepositoryProvider).myWord(id);
    return (
      examples: <StudyExample>[
        if (mine?.example case final example?) (german: example, english: null),
      ],
      tip: null,
    );
  }
  final dao = ref.watch(contentDaoProvider);
  final examples = await dao.examplesForWord(uid).get();
  final tips = await dao.tipsForWord(uid).get();
  return (
    examples: <StudyExample>[
      for (final e in examples.take(2)) (german: e.german, english: e.english),
    ],
    tip: tips.isEmpty ? null : (en: tips.first.tipEn, bn: tips.first.tipBn),
  );
}

/// The meanings to show in [meaning]: English, Bangla or both, null where
/// the learner's language leaves one out. A Bangla-only learner still gets
/// English where the course has no Bangla. T2's back and W1.
({String? english, String? bangla}) meaningsFor(
  Word word,
  MeaningLanguage meaning,
) {
  final bangla = meaning == MeaningLanguage.english ? null : word.bangla;
  return (
    english: meaning == MeaningLanguage.bangla && bangla != null
        ? null
        : word.english,
    bangla: bangla,
  );
}

/// The card turned over (`StudyBack`): the meanings per `meaning_language`,
/// the interference tip, two examples with play and translation, the
/// collocations (⟶) and the register (≈).
class StudyBack extends StatelessWidget {
  const StudyBack({
    required this.word,
    required this.meaning,
    required this.onPlay,
    super.key,
    this.extras,
    this.updated = false,
  });

  final Word word;
  final MeaningLanguage meaning;

  /// Null until the examples and tip have loaded.
  final StudyBackExtras? extras;

  /// Plays an example sentence.
  final ValueChanged<String> onPlay;

  /// BR-CONTENT-02: a course update changed the meaning in the last 7 days,
  /// so the [UpdatedChip] sits over it.
  final bool updated;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final (:english, :bangla) = meaningsFor(word, meaning);
    final tip = extras?.tip;
    final collocations = word.collocations;
    final register = word.synonymsRegister;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 1.5,
            child: ColoredBox(color: tokens.surface.outline),
          ),
        ),
        const SizedBox(height: 14),
        if (updated) ...<Widget>[
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: UpdatedChip(),
          ),
          const SizedBox(height: 8),
        ],
        if (english != null)
          DpText(english, role: DpTextRole.bodyLarge, weight: 500),
        if (english != null && bangla != null) const SizedBox(height: 2),
        if (bangla != null)
          DpText(
            bangla,
            role: DpTextRole.bodyLarge,
            color: english == null ? null : tokens.color.textSecondary,
          ),
        if (tip != null) ...<Widget>[
          const SizedBox(height: 14),
          DpCallout.text(l10n.studyTip(tipText(tip, meaning))),
        ],
        for (final example in extras?.examples ?? const <StudyExample>[])
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: StudyExampleRow(
              example,
              onPlay: () => onPlay(example.german),
            ),
          ),
        if (collocations != null && collocations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          DpText(
            // The course separates them with semicolons; the card with dots.
            l10n.studyCollocations(collocations.split('; ').join(' · ')),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
        if (register != null && register.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          DpText(
            l10n.studyRegister(register),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ],
    );
  }
}

/// BR-CONTENT-02's chip on a meaning a course update changed in the last
/// 7 days: the status chip's look, without a dot. T2's back and W1's header.
class UpdatedChip extends StatelessWidget {
  const UpdatedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DpChip(
      label: l10n.wordUpdated,
      kind: DpChipKind.status,
      // "Updated" alone, read next to "Done", could be the word's status.
      semanticLabel: l10n.wordUpdatedSemantic,
    );
  }
}

/// An interference tip in [meaning], English where there is no Bangla. T2's
/// back and W1.
String tipText(StudyTip tip, MeaningLanguage meaning) =>
    switch ((meaning, tip.bn)) {
      (MeaningLanguage.bangla, final bn?) => bn,
      (MeaningLanguage.both, final bn?) => '${tip.en}\n$bn',
      _ => tip.en,
    };

/// The 32 dp mini play button: Oat with an ink edge on paper, frosted under
/// glass. With [onPressed] it is its own button; without, it only draws, for
/// a row that is the target as a whole. Slashed with no German voice (V01,
/// #452).
class StudyPlayButton extends ConsumerWidget {
  const StudyPlayButton({super.key, this.label, this.onPressed});

  /// For screen readers, when it is its own button.
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final mute = noVoice(ref);
    final dot = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        shape: BoxShape.circle,
        border: Border.all(
          color: tokens.isGlass ? tokens.surface.outline : tokens.color.ink,
          width: tokens.surface.outlineWidth,
        ),
      ),
      child: Icon(
        mute ? Icons.volume_off : Icons.play_arrow,
        size: 16,
        color: mute ? tokens.color.textSecondary : tokens.color.ink,
      ),
    );
    final tap = onPressed;
    if (tap == null) return dot;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        // 32 dp drawn, 48 dp tall to hit, and the gap after it part of the
        // target, so the dot keeps the text's left edge.
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8, end: 10),
          child: dot,
        ),
      ),
    );
  }
}

/// One example: the mini play button, the German in italics, its
/// translation. The whole row plays it, so the target is not just 32 dp.
/// T2's back and W1 both draw it.
class StudyExampleRow extends StatelessWidget {
  const StudyExampleRow(this.example, {required this.onPlay, super.key});

  final StudyExample example;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final english = example.english;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).studyPlaySentence,
      child: GestureDetector(
        onTap: onPlay,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The row is the target, so the dot draws only.
            const StudyPlayButton(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    example.german,
                    role: DpTextRole.bodyLarge,
                    italic: true,
                  ),
                  if (english != null) ...<Widget>[
                    const SizedBox(height: 2),
                    DpText(
                      english,
                      role: DpTextRole.body,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
