import 'dart:async';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/cloze.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/words/speak.dart';
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
    this.chosen = false,
    super.key,
  });

  final Word word;
  final StudyCloze cloze;

  /// The answer is checked, with its verdict: the session turns the card
  /// over.
  final ValueChanged<Verdict> onChecked;

  /// The learner chose the cloze card in W1 (`card_mode_manual`,
  /// BR-FSRS-06), so the footnote doesn't give the two ratings as the
  /// reason (#515).
  final bool chosen;

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
    // The autoplay stays quiet once the phone is known to have no German
    // voice: T2's front card has already said so once this session. A tap on
    // play still explains, every time (accessibility-performance.md).
    if (verdict.isRight && ref.read(ttsAvailableProvider).value != false) {
      _play();
    }
    widget.onChecked(verdict);
  }

  void _play() => unawaited(say(ref, context, widget.cloze.example.german));

  @override
  Widget build(BuildContext context) {
    // Watched so [_check] can read it: whether the phone can speak German.
    ref.watch(ttsAvailableProvider);
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = widget.word;
    final example = widget.cloze.example;
    final gap = widget.cloze.gap;
    final verdict = _verdict;
    // #572, the lead's rule from #571 (reduce first, then scroll): typing
    // past 130 % on a 360 × 640 phone the sentence went under the top.
    // What is asked is a role smaller, and the gaps and the field close.
    // ponytail: on that phone with a 280 dp keyboard, three lines (about
    // 37 letters) fit at 200 %; a longer sentence scrolls, field first, as
    // L8's and L12's do (#573): the field and its umlaut row stay in view,
    // and a drag shows the sentence. The next lever: a second role down.
    final typing = DpScript.largeTypingInView(context);
    DpTextRole asked(DpTextRole role) => typing ? role.oneStepSmaller : role;
    final line = DpText.styleFor(
      tokens,
      asked(DpTextRole.title),
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
            // The gap is a widget, which `_Hyphenated`'s planner can't lay
            // out: a word too wide for the line gets its syllables here, and
            // one that fits keeps its letters, so 100 % stays as drawn
            // (#539). It is read whole.
            LayoutBuilder(
              builder: (context, box) {
                TextSpan broken(String text) => TextSpan(
                  text: DpScript.breakTooWide(
                    text,
                    style: line,
                    width: box.maxWidth,
                    scaler: MediaQuery.textScalerOf(context),
                  ),
                  semanticsLabel: text,
                );
                return Text.rich(
                  TextSpan(
                    style: line,
                    // Read in a German voice (#162).
                    locale: DpScript.deDE,
                    children: <InlineSpan>[
                      broken(example.german.substring(0, gap.start)),
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
                      broken(example.german.substring(gap.end)),
                    ],
                  ),
                );
              },
            ),
            if (english != null) ...<Widget>[
              SizedBox(height: typing ? 2 : 6),
              DpText(
                english,
                role: asked(DpTextRole.body),
                color: tokens.color.textSecondary,
              ),
            ],
            SizedBox(height: typing ? 6 : 14),
            if (verdict == null) ...<Widget>[
              StudyAnswerField(
                controller: _answer,
                onSubmitted: _check,
                umlautRowBelow: true,
                dense: typing,
              ),
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
                      widget.chosen
                          ? l10n.studyClozeFootnoteChosen
                          : l10n.studyClozeFootnote,
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
      // A long target too wide for the line breaks at a syllable with its
      // "-", in a German voice (#539).
      child: DpGermanRuns(
        <TextSpan>[TextSpan(text: word ?? '')],
        textAlign: TextAlign.center,
        // A WidgetSpan's child is scaled with its sentence already: scaled
        // again here, "Rechnung" was drawn at 4× into half the line at 200 %
        // and broke mid-word (#165).
        textScaler: TextScaler.noScaling,
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
    this.hint,
    this.umlautRowBelow = false,
    this.dense = false,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  /// The placeholder: "Type the missing word" unless given.
  final String? hint;

  /// Less padding above and below the text: L8 typing past 130 %, where
  /// the room above the keyboard is its prompt's (#568).
  final bool dense;

  /// The umlaut row sits under it, then 12 dp and *Check* (T2's cloze,
  /// grammar practice): on focus all of it scrolls above the keyboard
  /// (#515). Not where the row is pinned above the keyboard (L8, L12), whose
  /// prompt it would scroll away for nothing.
  final bool umlautRowBelow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final typing = DpScript.largeTypingInView(context);
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.shape.button),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      scrollPadding: umlautRowBelow
          ? DpUmlautBar.scrollPadding(
              context,
              // Past 130 % the few lines above the keyboard are the
              // question's, and *Check* may scroll under it: the keyboard's
              // Done checks too (#564).
              // ponytail: one threshold, so at 150 % Check goes though it
              // would still fit under a two-line sentence once T2's top bar
              // is gone; measure the sentence if 150 % should keep it.
              below: DpScript.large(context)
                  ? 0
                  : 12 + DpButton.minimumTapTarget,
              // Typing past 130 %, 8 dp of the margin under the keys go to
              // what is asked: T2's cloze (a three-line one fits a 360 × 640
              // phone) and L15's gap, which this field also serves (#572).
              // 12 dp is the keys' floor above the keyboard.
              margin: typing ? 12 : 20,
            )
          : const EdgeInsets.all(20),
      onSubmitted: (_) => onSubmitted(),
      style: DpText.styleFor(
        tokens,
        DpTextRole.title,
      ).copyWith(fontWeight: FontWeight.w400),
      decoration: InputDecoration(
        hintText: hint ?? l10n.studyClozeHint,
        // Whole, not cut to one line, as R1's is (#565). But typing past
        // 130 % the room above the keyboard is the sentence's (#564), and
        // the gap says what the hint does, as #554 let L8's caption go: one
        // line there. A screen reader still reads it whole.
        hintMaxLines: typing ? 1 : 3,
        maintainHintSize: false,
        filled: true,
        fillColor: tokens.surface.cardStrong,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: dense ? 6 : 14,
        ),
        border: edge,
        enabledBorder: edge,
        focusedBorder: edge,
      ),
    );
  }
}
