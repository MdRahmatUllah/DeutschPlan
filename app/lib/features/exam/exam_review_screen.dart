import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart'
    show TopicWithState;
import 'package:deutschplan/domain/answer_check.dart' show Verdict;
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart' show verdictFor;
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/exam/exam_question_view.dart'
    show examFormPrompt, examNumbered;
import 'package:deutschplan/features/exam/exam_results_screen.dart'
    show examResultProvider;
import 'package:deutschplan/features/learn/grammar_practice_screen.dart'
    show RuleSheet, itemAnswer;
import 'package:deutschplan/features/learn/step_exams.dart'
    show examSectionName;
import 'package:deutschplan/features/quiz/quiz_item_view.dart' show GermanWord;
import 'package:deutschplan/features/study/study_back.dart'
    show StudyPlayButton, studyBackProvider;
import 'package:deutschplan/features/words/speak.dart' show say;
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'exam_review_screen.g.dart';

/// A grammar topic, for *See rule*.
@riverpod
Future<TopicWithState?> examReviewTopic(Ref ref, String uid) =>
    ref.watch(grammarRepositoryProvider).find(uid);

/// The step's gender topic, where *See rule* sends an Articles question:
/// the one tagged `gender` (A1.1's "Nouns, gender & articles").
@riverpod
Future<TopicWithState?> examGenderTopic(Ref ref, String step) async {
  for (final topic in await ref.watch(grammarRepositoryProvider).step(step)) {
    if (topic.topic.tags.split(',').map((t) => t.trim()).contains('gender')) {
      return topic;
    }
  }
  return null;
}

/// L14's filters: "All · 40", "Wrong only · 9", "Flagged · 3".
enum ExamReviewFilter { all, wrong, flagged }

/// One numbered question of the paper, as L14 lists it.
typedef ExamReviewCard = ({int number, ExamResultRow row});

/// The paper's questions, numbered as L12 numbers them: Writing and Speaking
/// are tasks, not questions, and L13 has them.
List<ExamReviewCard> examReviewCards(List<ExamResultRow> rows) {
  var number = 0;
  return <ExamReviewCard>[
    for (final row in rows)
      if (examNumbered(row.item)) (number: ++number, row: row),
  ];
}

/// Wrong: less than the question's point (#84 grades *almost* as wrong).
bool examReviewWrong(ExamResultRow row) => row.points < row.item.section.points;

/// L14 · Exam review (`exam-results.md`, `ExamReview-android.html`, #136),
/// in L13's place: every question with the answer given, the right one and
/// an explanation (FR-L14-01), filtered to all, the wrong ones or the
/// flagged ones. Back returns to L13.
class ExamReviewView extends ConsumerStatefulWidget {
  const ExamReviewView({
    required this.attemptId,
    required this.onBack,
    this.onOpenWord,
    super.key,
  });

  final int attemptId;
  final VoidCallback onBack;

  /// *Open word*: W1 over this screen, as a sheet or a pane. A test hands in
  /// its own.
  final void Function(BuildContext context, String uid)? onOpenWord;

  @override
  ConsumerState<ExamReviewView> createState() => _ExamReviewViewState();
}

class _ExamReviewViewState extends ConsumerState<ExamReviewView> {
  ExamReviewFilter _filter = ExamReviewFilter.all;

  void _openWord(String uid) =>
      (widget.onOpenWord ?? WordRoute.open)(context, uid);

  /// *See rule*: the topic's rule over this screen, as L15 shows it, so the
  /// exam stays where it is.
  Future<void> _seeRule(TopicWithState? topic) async {
    if (topic == null) return;
    await Adaptive.showSheet<void>(
      context: context,
      builder: (_) => RuleSheet(topic: topic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(examResultProvider(widget.attemptId)).value;

    Widget body = const SizedBox.expand();
    if (result != null) {
      final cards = examReviewCards(result.rows);
      final wrong = cards.where((c) => examReviewWrong(c.row)).length;
      final flagged = cards.where((c) => c.row.flagged).length;
      final shown = <ExamReviewCard>[
        for (final card in cards)
          if (switch (_filter) {
            ExamReviewFilter.all => true,
            ExamReviewFilter.wrong => examReviewWrong(card.row),
            ExamReviewFilter.flagged => card.row.flagged,
          })
            card,
      ];
      DpChip chip(String label, ExamReviewFilter filter) => DpChip(
        label: label,
        kind: DpChipKind.filter,
        selected: _filter == filter,
        onTap: () => setState(() => _filter = filter),
      );
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              chip(l10n.examReviewAll(cards.length), ExamReviewFilter.all),
              chip(l10n.examReviewWrong(wrong), ExamReviewFilter.wrong),
              chip(l10n.examNavFlagged(flagged), ExamReviewFilter.flagged),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: DpText(
                l10n.examReviewNone,
                role: DpTextRole.body,
                color: tokens.color.textSecondary,
                textAlign: TextAlign.center,
              ),
            ),
          for (final card in shown) ...<Widget>[
            _Card(
              card: card,
              step: result.attempt.sublevelCode,
              onOpenWord: _openWord,
              onSeeRule: (topic) => unawaited(_seeRule(topic)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    final scaffold = AdaptiveScaffold(
      title: l10n.examResultReview,
      leading: AdaptiveBackButton(onPressed: widget.onBack),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    // Back, a gesture or the system's, returns to L13 rather than leaving
    // the exam.
    final guarded = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: scaffold,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.primary, child: guarded)
        : guarded;
  }
}

/// "Q3 · Vocabulary" and its verdict, the item, "Your answer" and
/// "Correct", the explanation and *Open word* or *See rule*.
class _Card extends ConsumerWidget {
  const _Card({
    required this.card,
    required this.step,
    required this.onOpenWord,
    required this.onSeeRule,
  });

  final ExamReviewCard card;
  final String step;
  final ValueChanged<String> onOpenWord;
  final ValueChanged<TopicWithState?> onSeeRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final row = card.row;
    final item = row.item;
    final given = row.given;
    final wrong = examReviewWrong(row);
    final verdict = given == null ? null : verdictFor(item, given);
    final almost = wrong && verdict == Verdict.almost;

    final (label, colour, icon) = given == null
        ? (l10n.examReviewNoAnswer, tokens.color.wrongText, Icons.close)
        : !wrong
        ? (l10n.examReviewRight, tokens.color.correctText, Icons.check)
        : almost
        ? (l10n.examReviewAlmost, tokens.color.almostText, Icons.close)
        : (l10n.examReviewWrongOne, tokens.color.wrongText, Icons.close);

    final grammar = item is GrammarQuestion ? item.item : null;
    final givenText = switch (grammar) {
      SpotTheError(:final tokens) => _at(tokens, given),
      RuleRecall(:final options) => _at(options, given),
      _ => given,
    };
    final correct = switch (item) {
      WordQuestion(:final expected) => expected,
      GapQuestion(:final answer) => answer,
      GrammarQuestion(item: final g) => itemAnswer(g),
      _ => '',
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DpText(
                l10n
                    .examReviewHeader(
                      card.number,
                      examSectionName(l10n, item.section),
                    )
                    .toUpperCase(),
                role: DpTextRole.caption,
                weight: 700,
                letterSpacing: 0.6,
                color: tokens.color.textSecondary,
              ),
            ),
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: 4),
            DpText(label, role: DpTextRole.caption, weight: 700, color: colour),
          ],
        ),
        const SizedBox(height: 8),
        switch (item) {
          WordQuestion(
            section: ExamSection.vocabulary || ExamSection.listening,
            :final prompt,
          ) =>
            GermanWord(prompt, role: DpTextRole.bodyLarge),
          _ => DpText(
            _prompt(l10n, item),
            role: DpTextRole.bodyLarge,
            weight: 600,
          ),
        },
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: <Widget>[
            _Answer(
              label: l10n.quizYourAnswer,
              value: givenText ?? l10n.quizResultNoAnswer,
              colour: wrong ? tokens.color.wrongText : tokens.color.correctText,
              struck: wrong && givenText != null,
            ),
            if (wrong)
              _Answer(
                label: l10n.quizCorrect,
                value: correct,
                colour: tokens.color.correctText,
                bold: true,
              ),
          ],
        ),
        const SizedBox(height: 8),
        ..._explanation(context, ref, item),
      ],
    );
    // The artboard's card: flat, a thin outline (every DpSurface kind draws
    // an edge or a shadow); frosted under glass.
    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.card,
            radius: 20,
            padding: const EdgeInsets.all(14),
            child: content,
          )
        : Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.surface.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.surface.outline, width: 1.5),
            ),
            child: content,
          );
  }

  /// FR-L14-01: a word item's first example, an Articles item's rule of
  /// thumb (the word's interference tip), a grammar item's rule; then
  /// *Open word* or *See rule*.
  List<Widget> _explanation(
    BuildContext context,
    WidgetRef ref,
    ExamItem item,
  ) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    Widget note(String text) => DpText(
      text,
      role: DpTextRole.label,
      weight: 400,
      color: tokens.color.textSecondary,
    );
    switch (item) {
      case GrammarQuestion(ref: final itemRef):
        final topic = ref
            .watch(examReviewTopicProvider(itemRef.split('#').first))
            .value;
        final rule = topic?.topic.rule?.split(RegExp(r'(?<=[.!?;])\s')).first;
        return <Widget>[
          if (rule != null && rule.isNotEmpty) note(rule),
          _Link(label: l10n.practiceSeeRule, onTap: () => onSeeRule(topic)),
        ];
      case WordQuestion(section: ExamSection.articles, ref: final uid):
        final tip = ref.watch(studyBackProvider(uid)).value?.tip;
        final rules = ref.watch(examGenderTopicProvider(step)).value;
        return <Widget>[
          if (tip != null) note(tip.en),
          if (rules != null)
            _Link(label: l10n.practiceSeeRule, onTap: () => onSeeRule(rules)),
        ];
      case WordQuestion(ref: final uid) || GapQuestion(ref: final uid):
        final example = ref
            .watch(studyBackProvider(uid))
            .value
            ?.examples
            .firstOrNull;
        return <Widget>[
          if (example != null)
            _Example(
              german: example.german,
              english: example.english,
              onPlay: () => unawaited(say(ref, context, example.german)),
            ),
          _Link(label: l10n.examReviewOpenWord, onTap: () => onOpenWord(uid)),
        ];
      default:
        return const <Widget>[];
    }
  }
}

/// The word's first example, as the ExamReview artboard draws it: the play
/// button, the German in italics and its translation, at 13.
class _Example extends StatelessWidget {
  const _Example({
    required this.german,
    required this.english,
    required this.onPlay,
  });

  final String german;
  final String? english;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final english = this.english;
    return Semantics(
      container: true,
      button: true,
      label: l10n.studyPlaySentence,
      onTap: onPlay,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const StudyPlayButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    german,
                    role: DpTextRole.label,
                    weight: 400,
                    italic: true,
                    color: tokens.color.textSecondary,
                  ),
                  if (english != null)
                    DpText(
                      english,
                      role: DpTextRole.label,
                      weight: 400,
                      color: tokens.color.textSecondary,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// *Open word* or *See rule*: link-coloured, with its chevron.
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          // accessibility-performance.md: 48 dp on Android, 44 pt on iOS.
          constraints: BoxConstraints(minHeight: context.isCupertino ? 44 : 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DpText(label, role: DpTextRole.label, color: tokens.color.link),
              Icon(Icons.chevron_right, size: 16, color: tokens.color.link),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your answer house", struck through when wrong; "Correct flat" in bold.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.label,
    required this.value,
    required this.colour,
    this.struck = false,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color colour;
  final bool struck;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).examReviewAnswerLabel(label, value),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DpText(
            label,
            role: DpTextRole.body,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                decoration: struck ? TextDecoration.lineThrough : null,
                decorationColor: colour,
              ),
              child: DpText(
                value,
                role: DpTextRole.body,
                weight: bold ? 700 : 400,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The item as the paper asked it.
String _prompt(AppLocalizations l10n, ExamItem item) => switch (item) {
  WordQuestion(section: ExamSection.articles, :final prompt) => '___ $prompt',
  WordQuestion(section: ExamSection.wordForms, :final prompt, :final form) =>
    examFormPrompt(l10n, prompt, form),
  WordQuestion(:final prompt) => prompt,
  GapQuestion(:final before, :final after) => '${before}___$after',
  GrammarQuestion(item: final g) => switch (g) {
    GapFill(:final before, :final after) ||
    PickTheForm(:final before, :final after) => '${before}___$after',
    SpotTheError(:final tokens) => tokens.join(' '),
    OrderTheSentence(:final chips) => chips.join(' / '),
    RuleRecall(:final question) => question,
  },
  _ => '',
};

/// [list]'s item at the index [given] holds, or [given] itself.
String? _at(List<String> list, String? given) {
  final i = int.tryParse(given ?? '');
  return i != null && i >= 0 && i < list.length ? list[i] : given;
}
