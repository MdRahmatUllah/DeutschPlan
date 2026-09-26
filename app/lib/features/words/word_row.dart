import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A word in a list — T4's backlog, L2's Words tab, L6: the headword in its
/// article's colour, its meaning, its status chip and a speaker, 64 dp on
/// the card, with a hairline under all but the [last]. A suspended word is
/// greyed rather than hidden (BR-STATUS-03).
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

    final content = Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DpHeadword(
                word.word.german,
                article: word.word.article,
                plural: word.word.forms,
                role: DpTextRole.bodyLarge,
                weight: 600,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              DpText(
                meaning,
                role: DpTextRole.label,
                weight: 400,
                maxLines: 1,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (step case final step?) ...<Widget>[
          DpChip(label: step, kind: DpChipKind.step),
          const SizedBox(width: 6),
        ],
        WordStatusChip(word.status),
        WordPlayButton(word: spokenForm(word.word)),
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Align(
      alignment: Alignment.topCenter,
      child: tokens.isGlass
          ? DpSurface(kind: DpSurfaceKind.bar, radius: 0, child: child)
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
    return DpChip(label: label, kind: DpChipKind.status, statusColour: dot);
  }
}

/// A row's 40 dp speaker: the word at the learner's speed, through `say()`.
class WordPlayButton extends ConsumerWidget {
  const WordPlayButton({required this.word, super.key});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final mute = noVoice(ref);
    return AdaptiveTapTarget(
      child: Semantics(
        button: true,
        label: AppLocalizations.of(context).summaryPlay(word),
        child: AdaptiveTooltip(
          message: AppLocalizations.of(context).summaryPlay(word),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(say(ref, context, word)),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                mute ? Icons.volume_off : Icons.volume_up,
                size: 22,
                color: mute ? tokens.color.textSecondary : tokens.color.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
