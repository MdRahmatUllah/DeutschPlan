import 'dart:async';

import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/study/study_card.dart';
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
  });

  final WordWithState word;

  /// In the learner's meaning language.
  final String meaning;
  final bool last;

  /// L6's step chip before the status, where a list spans steps.
  final String? step;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final (status, dot) = switch (word.status) {
      WordStatus.todo => (l10n.wordStatusToDo, tokens.surface.muted),
      WordStatus.learning => (l10n.wordStatusLearning, tokens.color.learning),
      WordStatus.done => (l10n.wordStatusDone, tokens.color.easy),
      WordStatus.suspended => (
        l10n.wordStatusSuspended,
        tokens.color.textSecondary,
      ),
    };

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
        DpChip(label: status, kind: DpChipKind.status, statusColour: dot),
        WordPlayButton(word: spokenForm(word.word)),
      ],
    );

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      decoration: BoxDecoration(
        color: tokens.surface.card,
        border: last
            ? null
            : Border(bottom: BorderSide(color: tokens.surface.outline)),
      ),
      child: word.isSuspended ? Opacity(opacity: 0.5, child: content) : content,
    );
  }
}

/// A row's 40 dp speaker: the word through the system voice at the
/// learner's speed.
class WordPlayButton extends ConsumerWidget {
  const WordPlayButton({required this.word, super.key});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).summaryPlay(word),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final speed = ref.read(settingsProvider).read(SettingKeys.ttsSpeed);
          unawaited(ref.read(systemTtsProvider).speak(word, rate: speed));
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.volume_up, size: 22, color: tokens.color.ink),
        ),
      ),
    );
  }
}
