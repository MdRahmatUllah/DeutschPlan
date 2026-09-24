import 'dart:async';

import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart' show FormLabel;
import 'package:deutschplan/features/learn/grammar_practice_screen.dart'
    show itemKind;
import 'package:deutschplan/features/quiz/quiz_item_view.dart';
import 'package:deutschplan/features/study/study_cloze.dart'
    show StudyAnswerField;
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// FR-L12-06: a Listening word plays once and replays twice.
const int examPlays = 3;

/// Whether [item] is a numbered question: Writing and Speaking are tasks,
/// so a full paper reads "Question 21 of 40" with 42 items.
bool examNumbered(ExamItem item) =>
    item is! WritingTask && item is! SpeakingTask;

/// Whether [item] is answered by typing, into the runner's field.
bool examTyped(ExamItem item) => switch (item) {
  WordQuestion(:final section) => section != ExamSection.articles,
  GapQuestion() => true,
  GrammarQuestion(:final item) => item is GapFill,
  WritingTask() || SpeakingTask() => false,
};

/// Whether [item]'s typed answer is German, which gets the umlaut row.
bool examTypesGerman(ExamItem item) =>
    examTyped(item) &&
    !(item is WordQuestion && item.section == ExamSection.vocabulary);

/// One exam question as L12 asks it (`exam-runner.md`, the ExamRunner
/// artboard): a caption, the prompt centred, and the way to answer. No
/// verdict, ever (FR-L12-02): a tap or a typed answer is only recorded.
class ExamQuestionView extends ConsumerWidget {
  const ExamQuestionView({
    required this.item,
    required this.given,
    required this.field,
    required this.onGiven,
    required this.plays,
    required this.onPlay,
    super.key,
  });

  final ExamItem item;

  /// What is recorded for it: a tapped choice, or a rule recall's index.
  final String? given;

  /// The typed answer, for the kinds [examTyped] says type.
  final TextEditingController field;

  /// A choice was tapped, or the field submitted.
  final ValueChanged<String> onGiven;

  /// How often a Listening word has been played.
  final int plays;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;

    Widget speaker(String word, {double size = 48}) => DpSpeakerButton(
      size: size,
      state: speakerState(ref),
      semanticLabel: l10n.quizPlay,
      onPressed: () => unawaited(say(ref, context, word)),
    );

    final (
      String caption,
      Widget prompt,
      String? hint,
      Widget answer,
    ) = switch (item) {
      WordQuestion(:final section, :final prompt, :final form) =>
        switch (section) {
          ExamSection.articles => (
            l10n.examRunAskArticle,
            _Centred(<Widget>[
              Flexible(child: GermanWord(prompt, role: DpTextRole.display)),
              const SizedBox(width: 14),
              speaker(prompt),
            ]),
            l10n.examRunTapArticle,
            ArticleButtons(picked: given, onPick: onGiven),
          ),
          ExamSection.listening => (
            l10n.examRunAskListening,
            Column(
              children: <Widget>[
                DpSpeakerButton(
                  size: 64,
                  state: speakerState(ref),
                  semanticLabel: l10n.quizAskListening,
                  onPressed: plays >= examPlays
                      ? null
                      : () {
                          onPlay();
                          unawaited(say(ref, context, prompt));
                        },
                ),
                const SizedBox(height: 8),
                DpText(
                  l10n.examRunPlaysLeft(examPlays - plays),
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.wordForms => (
            l10n.examRunAskForm,
            DpText(
              switch (form) {
                FormLabel.plural => l10n.quizFormPlural(prompt),
                FormLabel.thirdPerson => l10n.quizFormThirdPerson(prompt),
                FormLabel.perfekt => l10n.quizFormPerfekt(prompt),
                FormLabel.comparative => l10n.quizFormComparative(prompt),
                FormLabel.superlative => l10n.quizFormSuperlative(prompt),
                null => prompt,
              },
              role: DpTextRole.headline,
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.reverse => (
            l10n.examRunAskGerman,
            DpText(
              prompt,
              role: DpTextRole.headline,
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          _ => (
            l10n.examRunAskMeaning,
            _Centred(<Widget>[
              Flexible(child: GermanWord(prompt, role: DpTextRole.display)),
              const SizedBox(width: 14),
              speaker(prompt),
            ]),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
        },
      GapQuestion(:final before, :final after, :final translation) => (
        l10n.examRunAskGap,
        _Gap(before: before, after: after, translation: translation),
        null,
        _Field(field: field, onGiven: onGiven),
      ),
      GrammarQuestion(:final item) => switch (item) {
        GapFill(:final before, :final after, :final translation) => (
          itemKind(l10n, item),
          _Gap(before: before, after: after, translation: translation),
          null,
          _Field(field: field, onGiven: onGiven),
        ),
        PickTheForm(
          :final before,
          :final after,
          :final options,
          :final translation,
        ) =>
          (
            itemKind(l10n, item),
            _Gap(before: before, after: after, translation: translation),
            l10n.examRunTapOne,
            ChoiceTiles(options: options, picked: given, onPick: onGiven),
          ),
        // Graded by the rule's index (#84), so the index is recorded.
        RuleRecall(:final question, :final options) => (
          itemKind(l10n, item),
          DpText(
            l10n.practiceRecallQuestion(question),
            role: DpTextRole.title,
            textAlign: TextAlign.center,
          ),
          l10n.examRunTapOne,
          ChoiceTiles(
            options: options,
            picked: switch (int.tryParse(given ?? '')) {
              final int i when i >= 0 && i < options.length => options[i],
              _ => null,
            },
            onPick: (option) => onGiven('${options.indexOf(option)}'),
          ),
        ),
        SpotTheError(:final tokens) => (
          itemKind(l10n, item),
          const SizedBox.shrink(),
          l10n.examRunTapOne,
          _Words(
            words: tokens,
            picked: <int>{?int.tryParse(given ?? '')},
            onTap: (i) => onGiven('$i'),
          ),
        ),
        OrderTheSentence(:final chips) => (
          itemKind(l10n, item),
          const SizedBox.shrink(),
          l10n.examRunTapOne,
          _Order(chips: chips, given: given, onGiven: onGiven),
        ),
      },
      WritingTask(:final section) || SpeakingTask(:final section) => (
        section == ExamSection.writing
            ? l10n.examSectionWriting
            : l10n.examSectionSpeaking,
        // ponytail: #133 (Writing) and #134 (Speaking) build these; a
        // skipped task scores nothing (#84), as FR-L12S-01 says.
        DpText(
          l10n.examRunLater,
          role: DpTextRole.body,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        null,
        const SizedBox.shrink(),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          caption.toUpperCase(),
          role: DpTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 12),
        prompt,
        if (hint != null) ...<Widget>[
          const SizedBox(height: 12),
          DpText(
            hint,
            role: DpTextRole.caption,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
        ],
        const SizedBox(height: 32),
        answer,
      ],
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
}

class _Field extends StatelessWidget {
  const _Field({required this.field, required this.onGiven});

  final TextEditingController field;
  final ValueChanged<String> onGiven;

  @override
  Widget build(BuildContext context) => StudyAnswerField(
    controller: field,
    hint: AppLocalizations.of(context).quizYourAnswer,
    onSubmitted: () => onGiven(field.text),
  );
}

/// "Ich ____ gern einen Kaffee." and its translation.
class _Gap extends StatelessWidget {
  const _Gap({
    required this.before,
    required this.after,
    required this.translation,
  });

  final String before;
  final String after;
  final String translation;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      children: <Widget>[
        DpText(
          <String>[
            if (before.isNotEmpty) before,
            '_____',
            if (after.isNotEmpty) after,
          ].join(' '),
          role: DpTextRole.title,
          weight: 600,
          textAlign: TextAlign.center,
        ),
        if (translation.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          DpText(
            translation,
            role: DpTextRole.body,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
        ],
      ],
    );
  }
}

/// Words as tiles to tap: spot the error's sentence, and order the
/// sentence's chips.
class _Words extends StatelessWidget {
  const _Words({
    required this.words,
    required this.picked,
    required this.onTap,
  });

  final List<String> words;
  final Set<int> picked;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final (i, word) in words.indexed)
        Semantics(
          button: true,
          selected: picked.contains(i),
          child: DpSurface(
            kind: DpSurfaceKind.bar,
            selected: picked.contains(i),
            radius: context.tokens.shape.button,
            onTap: () => onTap(i),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: DpText(word, role: DpTextRole.bodyLarge, weight: 600),
          ),
        ),
    ],
  );
}

/// Order the sentence: tap the chips in order; tap a placed one to take it
/// back. Every tap records the words placed so far, joined by a space (#84
/// compares it whole, so a partial one is wrong); none placed records
/// nothing, and the question is unanswered again.
class _Order extends StatelessWidget {
  const _Order({
    required this.chips,
    required this.given,
    required this.onGiven,
  });

  final List<String> chips;
  final String? given;
  final ValueChanged<String> onGiven;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The placed chips, by their index in [chips]: rebuilt from what is
    // recorded, so a restart shows the sentence as it was.
    final placed = <int>[];
    for (final word in (given ?? '').split(' ').where((w) => w.isNotEmpty)) {
      final i = <int>[
        for (var j = 0; j < chips.length; j++)
          if (chips[j] == word && !placed.contains(j)) j,
      ].firstOrNull;
      if (i != null) placed.add(i);
    }
    String sentence(List<int> order) =>
        [for (final i in order) chips[i]].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: _Words(
            words: [for (final i in placed) chips[i]],
            picked: const <int>{},
            onTap: (k) => onGiven(sentence([...placed]..removeAt(k))),
          ),
        ),
        const SizedBox(height: 16),
        _Words(
          words: chips,
          picked: placed.toSet(),
          onTap: (i) {
            if (!placed.contains(i)) onGiven(sentence([...placed, i]));
          },
        ),
      ],
    );
  }
}
