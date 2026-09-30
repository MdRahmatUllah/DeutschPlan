import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart' show customId;
import 'package:sogda/features/words/speak.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

part 'study_back.g.dart';

/// An example sentence on the back: the German and its translation, in the
/// primary meaning language or, where that has none, English (#1081).
typedef StudyExample = ({String german, String? translation});

/// A word's interference tips by language: one for each language whose
/// speakers the course has one for (#1081).
typedef StudyTip = Map<String, String>;

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
        if (mine?.example case final example?)
          (german: example, translation: null),
      ],
      tip: null,
    );
  }
  // Watched: a primary language changed in M3 reaches an open card.
  final lang = ref.watch(meaningsProvider.select((m) => m.choice.primary));
  final dao = ref.watch(contentDaoProvider);
  final examples = await dao.examplesForWordIn(uid, lang).get();
  final tips = await dao.wordTipsFor(uid).get();
  return (
    examples: <StudyExample>[
      for (final e in examples.take(2))
        (german: e.german, translation: e.translation),
    ],
    tip: tips.isEmpty
        ? null
        : <String, String>{for (final t in tips) t.lang: t.tip},
  );
}

/// The card turned over (`StudyBack`): the meanings in the learner's
/// languages, the interference tip, two examples with play and translation,
/// the collocations (⟶) and the register (≈).
class StudyBack extends StatelessWidget {
  const StudyBack({
    required this.word,
    required this.meanings,
    required this.onPlay,
    super.key,
    this.guide,
    this.pronKeySeen = false,
    this.extras,
    this.updated = false,
  });

  final Word word;
  final Meanings meanings;

  /// The language of the pronunciation guide on the front, whose key the
  /// back opens with (#1122); null with no guide.
  final String? guide;

  /// `pron_key_seen`: the key is a small ⓘ.
  final bool pronKeySeen;

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
    final tip = tipText(extras?.tip, meanings.choice);
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
        if (guide case final lang? when PronKey.has(lang)) ...<Widget>[
          PronKey(lang, seen: pronKeySeen),
          const SizedBox(height: 6),
        ],
        MeaningLines(meanings.lines(word)),
        if (tip != null) ...<Widget>[
          const SizedBox(height: 14),
          SgCallout.text(l10n.studyTip(tip)),
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
          SgText(
            // The course separates them with semicolons; the card with dots.
            l10n.studyCollocations(collocations.split('; ').join(' · ')),
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
        if (register != null && register.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          SgText(
            l10n.studyRegister(register),
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ],
    );
  }
}

/// A word's meanings ([Meanings.lines]): the primary in the body's weight, a
/// secondary under it in the secondary colour. T2's back and W1.
class MeaningLines extends StatelessWidget {
  const MeaningLines(this.lines, {super.key});

  final List<({String lang, String text})> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (i, line) in lines.indexed) ...<Widget>[
          if (i > 0) const SizedBox(height: 2),
          SgText(
            line.text,
            role: SgTextRole.bodyLarge,
            // Bangla keeps its role's own weight (#1063).
            weight: i == 0 && line.lang != 'bn' ? 500 : null,
            color: i == 0 ? null : tokens.color.textSecondary,
          ),
        ],
      ],
    );
  }
}

/// #1122: the key to a pronunciation guide in [lang], how its letters and
/// capitals read. A line under the guide opens it in a sheet; once the
/// learner has opened one, a small ⓘ in its place (`pron_key_seen`). W1 and
/// T2's back.
class PronKey extends ConsumerStatefulWidget {
  const PronKey(this.lang, {required this.seen, super.key});

  final String lang;

  /// `pron_key_seen`, read by the screen with its other settings: the key
  /// writes it, and reads nothing (W1's view reads no settings).
  final bool seen;

  /// Whether [lang]'s guide has a key: English, Russian and Polish do.
  static bool has(String lang) =>
      const <String>{'en', 'ru', 'pl'}.contains(lang);

  /// [lang]'s key, written in [lang] whatever the app's language.
  static String _text(AppLocalizations l10n, String lang) => switch (lang) {
    'ru' => l10n.pronKeyRu,
    'pl' => l10n.pronKeyPl,
    _ => l10n.pronKeyEn,
  };

  @override
  ConsumerState<PronKey> createState() => _PronKeyState();
}

class _PronKeyState extends ConsumerState<PronKey> {
  late bool _seen = widget.seen;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final text = PronKey._text(l10n, widget.lang);
    if (!_seen) {
      setState(() => _seen = true);
      unawaited(
        ref.read(settingsProvider).write(SettingKeys.pronKeySeen, true),
      );
    }
    await Adaptive.showSheet<void>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: SgText(l10n.pronKeyLine, role: SgTextRole.title),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SgText(text, role: SgTextRole.body),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        container: true,
        button: true,
        label: l10n.pronKeyLine,
        onTap: _open,
        excludeSemantics: true,
        child: SgTappable(
          onTap: _open,
          child: ConstrainedBox(
            // accessibility-performance.md: 48 dp on Android, 44 pt on iOS.
            constraints: BoxConstraints(
              minHeight: context.isCupertino ? 44 : 48,
              minWidth: context.isCupertino ? 44 : 48,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.info_outline, size: 18, color: tokens.color.link),
                if (!_seen) ...<Widget>[
                  const SizedBox(width: 6),
                  Flexible(
                    child: SgText(
                      l10n.pronKeyLine,
                      role: SgTextRole.caption,
                      color: tokens.color.link,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
    return SgChip(
      label: l10n.wordUpdated,
      kind: SgChipKind.status,
      // "Updated" alone, read next to "Done", could be the word's status.
      semanticLabel: l10n.wordUpdatedSemantic,
    );
  }
}

/// A word's interference tip in the chosen languages, primary first, a line
/// each; null where none of them has one: a tip is about its own language's
/// speakers, so no other language's stands in (#1081). T2's back, W1, L13.
String? tipText(StudyTip? tip, MeaningChoice choice) {
  final lines = <String>[for (final lang in choice.languages) ?tip?[lang]];
  return lines.isEmpty ? null : lines.join('\n');
}

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
    return AdaptiveTapTarget(
      child: Semantics(
        button: true,
        label: label,
        child: AdaptiveTooltip(
          message: label,
          child: SgTappable(
            radius: BorderRadius.circular(16),
            onTap: tap,
            // 32 dp drawn, 48 dp tall to hit, and the gap after it part of the
            // target, so the dot keeps the text's left edge.
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                top: 8,
                bottom: 8,
                end: 10,
              ),
              child: dot,
            ),
          ),
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
    final translation = example.translation;
    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context).studyPlaySentence,
      child: SgTappable(
        onTap: onPlay,
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
                  SgText(
                    example.german,
                    role: SgTextRole.bodyLarge,
                    italic: true,
                    german: true,
                  ),
                  if (translation != null) ...<Widget>[
                    const SizedBox(height: 2),
                    SgText(
                      translation,
                      role: SgTextRole.body,
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
