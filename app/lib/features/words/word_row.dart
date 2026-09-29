import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_speaker_button.dart'
    show SgPlayingBars, SgSpeakerState;
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/study/study_card.dart';
import 'package:sogda/features/words/speak.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

/// A word in a list — T4's backlog, L2's Words tab, L6: the headword in its
/// article's colour, its meaning, its status chip and a speaker, 64 dp on
/// the card, with a hairline under all but the [last]. A suspended word is
/// greyed rather than hidden (BR-STATUS-03). Past 130 % text it stacks, so
/// its rows differ in height: a list takes no `prototypeItem` there (#550).
///
/// Only the drawing: what a tap or a long press does is the list's.
class WordRow extends StatelessWidget {
  const WordRow({
    required this.word,
    required this.meaning,
    required this.last,
    super.key,
    this.step,
    this.onPanel = false,
  });

  final WordWithState word;

  /// In the learner's meaning language.
  final String meaning;
  final bool last;

  /// L6's step chip before the status, where a list spans steps.
  final String? step;

  /// Inside a [WordListPanel]: under glass the panel is the fill, so the row
  /// paints none of its own (#282).
  final bool onPanel;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Past 130 % text the chips and the speaker took half the row, and cut
    // the headword to "die Gebu…" and the meaning at a word, with no "…"
    // (#550): the two take the row's width, wrapping (the headword at its
    // syllables), and the chips and the speaker go on a line under them.
    final large = SgScript.large(context);
    final text = <Widget>[
      SgHeadword(
        word.word.german,
        article: word.word.article,
        plural: word.word.forms,
        role: SgTextRole.bodyLarge,
        weight: 600,
        maxLines: large ? null : 1,
      ),
      const SizedBox(height: 2),
      SgText(
        meaning,
        role: SgTextRole.label,
        weight: 400,
        maxLines: large ? null : 1,
        color: tokens.color.textSecondary,
      ),
    ];
    final chips = <Widget>[
      if (step case final step?) ...<Widget>[
        SgChip(label: step, kind: SgChipKind.step),
        const SizedBox(width: 6),
      ],
      if (word.studied) WordStatusChip(word.status),
    ];
    final play = WordPlayButton(word: spokenForm(word.word));

    final content = large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...text,
              Row(children: <Widget>[...chips, const Spacer(), play]),
            ],
          )
        : Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: text,
                ),
              ),
              const SizedBox(width: 10),
              ...chips,
              play,
            ],
          );

    // At least the artboard's 64 dp; taller at large text, so the meaning
    // line isn't cut mid-glyph (#314).
    return Container(
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(
        color: onPanel && tokens.isGlass ? null : tokens.surface.card,
        border: last
            ? null
            : Border(bottom: BorderSide(color: tokens.surface.outline)),
      ),
      child: word.isSuspended ? Opacity(opacity: 0.5, child: content) : content,
    );
  }
}

/// A list of [WordRow]s as L2 and L6 draw it (#282): under a hairline, and
/// under glass one frosted panel for the whole list — the artboards' blur,
/// sheen and top highlight — so one `BackdropFilter`, never one per row
/// (`accessibility-performance.md`). Its rows pass `onPanel`, and its list
/// shrink-wraps, so a short list's panel ends at its last row, as the
/// artboards draw it, with the aurora clear below.
class WordListPanel extends StatelessWidget {
  const WordListPanel({required this.child, super.key});

  final Widget child;

  /// Whether a list of [rows] in the panel shrink-wraps, so the panel ends
  /// at its last row (#282). Past 130 % the rows have no prototype, and a
  /// shrink-wrapped list without one sizes itself again as it scrolls, over
  /// L6's and L2's hundreds of rows (#690 LQ-12). A list longer than the
  /// screen fills it either way, so only a short one wraps there.
  /// ponytail: 20 rows over-fill a tablet at 130 %; a device profile at
  /// 200 % is still to come.
  static bool shrinkWrap(BuildContext context, int rows) =>
      !SgScript.large(context) || rows <= 20;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Align(
      alignment: Alignment.topCenter,
      child: tokens.isGlass
          ? SgSurface(kind: SgSurfaceKind.bar, radius: 0, child: child)
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.surface.outline)),
              ),
              child: child,
            ),
    );
  }
}

/// A word's status as a chip with its dot: To do, Learning, Done or
/// Suspended (BR-STATUS-01, BR-STATUS-03). A list row and W1's header.
class WordStatusChip extends StatelessWidget {
  const WordStatusChip(this.status, {super.key});

  final WordStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final (label, dot) = switch (status) {
      WordStatus.todo => (l10n.wordStatusToDo, tokens.surface.muted),
      WordStatus.learning => (l10n.wordStatusLearning, tokens.color.learning),
      WordStatus.done => (l10n.wordStatusDone, tokens.color.easy),
      WordStatus.suspended => (
        l10n.wordStatusSuspended,
        tokens.color.textSecondary,
      ),
    };
    return SgChip(label: label, kind: SgChipKind.status, statusColour: dot);
  }
}

/// A row's 40 dp speaker: the word at the learner's speed, through `say()`.
class WordPlayButton extends ConsumerWidget {
  const WordPlayButton({required this.word, super.key});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    // #515: the row's speaker says it's playing, as the big one does (V03).
    final state = speakerState(ref, word);
    final mute = state == SgSpeakerState.unavailable;
    return AdaptiveTapTarget(
      child: Semantics(
        button: true,
        label: AppLocalizations.of(context).summaryPlay(word),
        child: AdaptiveTooltip(
          message: AppLocalizations.of(context).summaryPlay(word),
          child: SgTappable(
            radius: BorderRadius.circular(20),
            onTap: () => unawaited(say(ref, context, word)),
            child: SizedBox(
              width: 40,
              height: 40,
              child: switch (state) {
                SgSpeakerState.playing => Center(
                  child: SgPlayingBars(colour: tokens.color.ink, size: 40),
                ),
                SgSpeakerState.loading => Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.color.ink,
                    ),
                  ),
                ),
                _ => Icon(
                  mute ? Icons.volume_off : Icons.volume_up,
                  size: 22,
                  color: mute ? tokens.color.textSecondary : tokens.color.ink,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}
