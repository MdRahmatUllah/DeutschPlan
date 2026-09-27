import 'dart:async';

import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/domain/grammar_item_generator.dart';
import 'package:sogda/domain/quiz_builder.dart' show FormLabel;
import 'package:sogda/features/learn/grammar_practice_screen.dart'
    show itemKind;
import 'package:sogda/features/quiz/quiz_item_view.dart';
import 'package:sogda/features/study/study_cloze.dart' show StudyAnswerField;
import 'package:sogda/features/words/speak.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
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
  WordQuestion(:final section, :final tiles) =>
    section != ExamSection.articles && tiles.isEmpty,
  GapQuestion() => true,
  GrammarQuestion(:final item) => item is GapFill,
  WritingTask() => true,
  SpeakingTask() => false,
};

/// Whether [item]'s typed answer is German, which gets the umlaut row.
bool examTypesGerman(ExamItem item) =>
    examTyped(item) &&
    !(item is WordQuestion && item.section == ExamSection.vocabulary);

/// One exam question as L12 asks it (`exam-runner.md`, the ExamRunner
/// artboard): a caption, the prompt centred, and the way to answer. No
/// verdict, ever (FR-L12-02): a tap or a typed answer is only recorded.
/// Writing and Speaking are tasks, drawn by `exam_writing.dart` and
/// `exam_speaking.dart`.
class ExamQuestionView extends ConsumerWidget {
  const ExamQuestionView({
    required this.item,
    required this.given,
    required this.field,
    required this.onGiven,
    required this.plays,
    required this.onPlay,
    super.key,
    this.typingLarge = false,
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

  /// Typing past 130 % with the keyboard up: what is asked is one role
  /// smaller, so a display-size word or a two-line gap still fits above the
  /// field on a short phone; what still doesn't scrolls (#573).
  final bool typingLarge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    SgTextRole asked(SgTextRole role) =>
        typingLarge ? role.oneStepSmaller : role;

    Widget speaker(String word, {double size = 48}) => SgSpeakerButton(
      size: size,
      state: speakerState(ref, word),
      semanticLabel: l10n.quizPlay,
      onPressed: () => unawaited(say(ref, context, word)),
    );

    final (
      String caption,
      Widget prompt,
      String? hint,
      Widget answer,
    ) = switch (item) {
      WordQuestion(:final section, :final prompt, :final form, :final tiles) =>
        switch (section) {
          ExamSection.articles => (
            l10n.examRunAskArticle,
            _Centred(<Widget>[
              Flexible(child: GermanWord(prompt, role: SgTextRole.display)),
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
                SgSpeakerButton(
                  size: 64,
                  state: speakerState(ref, prompt),
                  semanticLabel: l10n.quizAskListening,
                  onPressed: plays >= examPlays
                      ? null
                      : () {
                          onPlay();
                          unawaited(say(ref, context, prompt));
                        },
                ),
                const SizedBox(height: 8),
                SgText(
                  l10n.examRunPlaysLeft(examPlays - plays),
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.wordForms => (
            l10n.examRunAskForm,
            SgText(
              examFormPrompt(l10n, prompt, form),
              role: asked(SgTextRole.headline),
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.reverse => (
            l10n.examRunAskGerman,
            SgText(
              prompt,
              role: asked(SgTextRole.headline),
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          _ => (
            l10n.examRunAskMeaning,
            _Centred(<Widget>[
              Flexible(
                child: GermanWord(prompt, role: asked(SgTextRole.display)),
              ),
              const SizedBox(width: 14),
              speaker(prompt),
            ]),
            tiles.isEmpty ? null : l10n.examRunTapOne,
            // #798: a Bangla meaning is tapped, as L8's DE → বাংলা.
            tiles.isEmpty
                ? _Field(field: field, onGiven: onGiven)
                : ChoiceTiles(options: tiles, picked: given, onPick: onGiven),
          ),
        },
      GapQuestion(:final before, :final after, :final translation) => (
        l10n.examRunAskGap,
        _Gap(
          before: before,
          after: after,
          translation: translation,
          role: asked(SgTextRole.title),
        ),
        null,
        _Field(field: field, onGiven: onGiven),
      ),
      GrammarQuestion(:final item) => switch (item) {
        GapFill(:final before, :final after, :final translation) => (
          itemKind(l10n, item),
          _Gap(
            before: before,
            after: after,
            translation: translation,
            role: asked(SgTextRole.title),
          ),
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
          SgText(
            l10n.practiceRecallQuestion(question),
            role: SgTextRole.title,
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
      // The runner draws them: ExamWriting and ExamSpeaking.
      WritingTask() ||
      SpeakingTask() => throw StateError('a task is drawn by the runner'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SgText(
          caption.toUpperCase(),
          role: SgTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 12),
        prompt,
        if (hint != null) ...<Widget>[
          const SizedBox(height: 12),
          SgText(
            hint,
            role: SgTextRole.caption,
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
    this.role = SgTextRole.title,
  });

  final String before;
  final String after;
  final String translation;

  /// The sentence's role: a step smaller while typing past 130 % (#573).
  final SgTextRole role;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      children: <Widget>[
        SgText(
          <String>[
            if (before.isNotEmpty) before,
            '_____',
            if (after.isNotEmpty) after,
          ].join(' '),
          role: role,
          weight: 600,
          textAlign: TextAlign.center,
        ),
        if (translation.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          SgText(
            translation,
            role: SgTextRole.body,
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
        AdaptiveTapTarget(
          child: Semantics(
            button: true,
            selected: picked.contains(i),
            child: SgSurface(
              kind: SgSurfaceKind.bar,
              selected: picked.contains(i),
              radius: context.tokens.shape.button,
              onTap: () => onTap(i),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: SgText(word, role: SgTextRole.bodyLarge, weight: 600),
            ),
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

/// Writing's and Speaking's task: a flat Oat panel on paper, as the task
/// artboards draw their prompt — no edge, no shadow, which every SgSurface
/// kind has; the frosted card under glass.
Widget examTaskPanel(SgTokens tokens, Widget child) => tokens.isGlass
    ? SgSurface(radius: 12, padding: _taskPadding, child: child)
    : Container(
        padding: _taskPadding,
        decoration: BoxDecoration(
          color: tokens.surface.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

const EdgeInsets _taskPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

/// "14:32": minutes and seconds, the runner's clock, L13's time and, with
/// its minutes in two digits, Speaking's.
String examClock(int seconds) =>
    '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';

/// A rubric line: a 22 dp box, Lime with a tick once ticked. L12's
/// Speaking and L13's rubric sheet (#135).
class ExamRubricTick extends StatelessWidget {
  const ExamRubricTick({
    required this.label,
    required this.ticked,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool ticked;

  /// Null: shown, but not tickable (L13, a task without an answer).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tick = Semantics(
      container: true,
      checked: ticked,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          // accessibility-performance.md: 48 dp on Android, 44 pt on iOS.
          constraints: BoxConstraints(minHeight: context.isCupertino ? 44 : 48),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: ticked ? tokens.color.easy : null,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.color.ink, width: 2),
                ),
                child: ticked
                    ? Icon(Icons.check, size: 14, color: tokens.color.onAccent)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: SgText(label, role: SgTextRole.body)),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? Opacity(opacity: 0.5, child: tick) : tick;
  }
}

/// A task's rubric lines, in the order `self_rubric_json` stores its ticks:
/// Speaking's four (FR-L12S-03), Writing's two, ticked on L13 (FR-L12W-03).
List<String> examRubricLines(AppLocalizations l10n, ExamSection section) =>
    switch (section) {
      ExamSection.speaking => <String>[
        l10n.examSpeakingRubricTask,
        l10n.examSpeakingRubricFluency,
        l10n.examSpeakingRubricPronunciation,
        l10n.examSpeakingRubricVocabulary,
      ],
      ExamSection.writing => <String>[
        l10n.examWritingRubricTask,
        l10n.examWritingRubricStructure,
      ],
      _ => const <String>[],
    };

/// A Word forms question as the paper asks it: "Plural of Haus". L12 and
/// L14.
String examFormPrompt(AppLocalizations l10n, String prompt, FormLabel? form) =>
    switch (form) {
      FormLabel.plural => l10n.quizFormPlural(prompt),
      FormLabel.thirdPerson => l10n.quizFormThirdPerson(prompt),
      FormLabel.perfekt => l10n.quizFormPerfekt(prompt),
      FormLabel.comparative => l10n.quizFormComparative(prompt),
      FormLabel.superlative => l10n.quizFormSuperlative(prompt),
      null => prompt,
    };
