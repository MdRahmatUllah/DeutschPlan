import 'dart:async';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/cloze.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The example a cloze card blanks, and where.
typedef StudyCloze = ({StudyExample example, ClozeGap gap});

/// The first of [examples] that holds [word], or null — and then the card
/// stays plain (study-session-states.md, Cloze rules).
StudyCloze? clozeOf(Word word, List<StudyExample> examples) {
  for (final example in examples) {
    final gap = clozeGap(example.german, word.german, pos: word.pos);
    if (gap != null) return (example: example, gap: gap);
  }
  return null;
}

/// T2's cloze card (`StudyCloze`, FR-T2-10), for a word whose
/// `card_mode` is cloze (BR-FSRS-06).
///
/// *Fill the gap*: the example with the word blanked, its translation, and
/// a field with the umlaut row. Checked with `checkGerman`, article not
/// required. Right, the sentence plays; *almost* shows the spelling; either
/// way, and wrong too, the card turns ([onChecked]) and the rating bar
/// comes up. The footnote says why the card changed and how to change it
/// back. Keyed by word where it is built, so each word starts clean.
class StudyClozeCard extends ConsumerStatefulWidget {
  const StudyClozeCard({
    required this.word,
    required this.cloze,
    required this.onChecked,
    super.key,
  });

  final Word word;
  final StudyCloze cloze;

  /// The answer is checked: the session turns the card over.
  final VoidCallback onChecked;

  @override
  ConsumerState<StudyClozeCard> createState() => _StudyClozeCardState();
}

class _StudyClozeCardState extends ConsumerState<StudyClozeCard> {
  final TextEditingController _answer = TextEditingController();
  Verdict? _verdict;

  String get _expected => widget.cloze.example.german.substring(
    widget.cloze.gap.start,
    widget.cloze.gap.end,
  );

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _check() {
    if (_verdict != null || _answer.text.trim().isEmpty) return;
    final verdict = checkGerman(_answer.text, _expected);
    setState(() => _verdict = verdict);
    if (verdict.isRight) _play();
    widget.onChecked();
  }

  void _play() {
    final speed = ref.read(settingsProvider).read(SettingKeys.ttsSpeed);
    unawaited(
      ref
          .read(systemTtsProvider)
          .speak(widget.cloze.example.german, rate: speed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = widget.word;
    final example = widget.cloze.example;
    final gap = widget.cloze.gap;
    final verdict = _verdict;
    final line = DpText.styleFor(
      tokens,
      DpTextRole.title,
    ).copyWith(fontWeight: FontWeight.w500);
    final english = example.english;

    return StudyCardFrame(
      article: word.article,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                DpChip(label: word.sublevelCode),
                const SizedBox(width: 6),
                DpChip(label: l10n.studyClozeChip, fill: tokens.color.primary),
              ],
            ),
            const SizedBox(height: 14),
            DpText(
              l10n.studyClozePrompt.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: line,
                children: <InlineSpan>[
                  TextSpan(text: example.german.substring(0, gap.start)),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: _Gap(
                      article: word.article,
                      // The word shows once the answer is in.
                      word: verdict == null ? null : _expected,
                      style: line,
                    ),
                  ),
                  TextSpan(text: example.german.substring(gap.end)),
                ],
              ),
            ),
            if (english != null) ...<Widget>[
              const SizedBox(height: 6),
              DpText(
                english,
                role: DpTextRole.body,
                color: tokens.color.textSecondary,
              ),
            ],
            const SizedBox(height: 14),
            if (verdict == null) ...<Widget>[
              StudyAnswerField(controller: _answer, onSubmitted: _check),
              const SizedBox(height: 8),
              DpUmlautBar(controller: _answer),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _answer,
                builder: (context, _) => DpButton(
                  label: l10n.studyClozeCheck,
                  onPressed: _answer.text.trim().isEmpty ? null : _check,
                  kind: DpButtonKind.secondary,
                ),
              ),
            ] else ...<Widget>[
              DpVerdictRow(
                verdict: switch (verdict) {
                  Verdict.correct => DpVerdict.correct,
                  Verdict.almost => DpVerdict.almost,
                  Verdict.wrongArticle => DpVerdict.wrongArticle,
                  Verdict.wrong => DpVerdict.wrong,
                },
                message: switch (verdict) {
                  Verdict.correct => l10n.studyClozeCorrect,
                  Verdict.almost => l10n.studyClozeAlmost(_expected),
                  Verdict.wrongArticle ||
                  Verdict.wrong => l10n.studyClozeWrong(_expected),
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  StudyPlayButton(
                    label: l10n.studyPlaySentence,
                    onPressed: _play,
                  ),
                  Expanded(
                    child: DpText(
                      l10n.studyClozeFootnote,
                      role: DpTextRole.label,
                      weight: 400,
                      color: tokens.color.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The blank, underlined in the gender colour; the word in it once answered.
class _Gap extends StatelessWidget {
  const _Gap({required this.article, required this.word, required this.style});

  final String? article;
  final String? word;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gender = tokens.color.forArticle(article) ?? tokens.color.ink;
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: gender, width: 3)),
      ),
      child: Text(
        word ?? '',
        textAlign: TextAlign.center,
        style: style.copyWith(
          color: tokens.color.textForArticle(article) ?? tokens.color.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The QuizRunner artboard's answer field: 56 dp, 12 px corners, a 2 px ink
/// edge, 20 px text.
class StudyAnswerField extends StatelessWidget {
  const StudyAnswerField({
    required this.controller,
    required this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.shape.button),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
      style: DpText.styleFor(
        tokens,
        DpTextRole.title,
      ).copyWith(fontWeight: FontWeight.w400),
      decoration: InputDecoration(
        hintText: l10n.studyClozeHint,
        filled: true,
        fillColor: tokens.surface.cardStrong,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: edge,
        enabledBorder: edge,
        focusedBorder: edge,
      ),
    );
  }
}
