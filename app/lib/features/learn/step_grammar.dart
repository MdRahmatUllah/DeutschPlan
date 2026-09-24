import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show daysBetween;
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'step_grammar.g.dart';

/// L2's Grammar tab: the step's topics in teaching order with their FSRS
/// state, as a stream — a topic practised elsewhere moves on here.
@riverpod
Stream<List<TopicWithState>> stepTopics(Ref ref, String code) =>
    ref.watch(grammarRepositoryProvider).watchStep(code);

/// Where a topic stands today (FR-L2-05).
enum TopicDue { notLearned, due, scheduled, suspended }

/// FR-L2-05 from `grammar_state`: a learned topic is due once its day has
/// come, and scheduled before; one never practised is not learned yet.
TopicDue topicDue(TopicWithState topic, String today) {
  if (topic.status == WordStatus.suspended) return TopicDue.suspended;
  final due = topic.state?.due;
  if (topic.status == WordStatus.todo || due == null) {
    return TopicDue.notLearned;
  }
  return daysBetween(today, due) <= 0 ? TopicDue.due : TopicDue.scheduled;
}

/// L2 · Grammar (`step-detail.md`, `StepGrammar-android.html`): *Practise
/// all due · N* over the numbered topics, each with its rule on one line and
/// when it comes round again.
class StepGrammarTab extends ConsumerWidget {
  const StepGrammarTab({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final topics = ref.watch(stepTopicsProvider(code)).value;
    if (topics == null) return const SizedBox.expand();
    final today = ref.watch(todayProvider);
    final due = <String>[
      for (final topic in topics)
        if (topicDue(topic, today) == TopicDue.due) topic.uid,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (due.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            // Every due topic, back to back in L15.
            child: DpButton(
              label: l10n.stepPractiseDue(due.length),
              drawnHeight: 48,
              onPressed: () => GrammarPracticeRoute.open(
                context,
                GrammarPracticeArgs(topicUids: due),
              ),
            ),
          ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.surface.outline)),
            ),
            child: ListView.builder(
              key: PageStorageKey<String>('step-grammar-$code'),
              padding: EdgeInsets.zero,
              itemCount: topics.length,
              itemBuilder: (context, index) => TopicRow(
                number: index + 1,
                topic: topics[index],
                due: topicDue(topics[index], today),
                daysLeft: topics[index].state?.due == null
                    ? 0
                    : daysBetween(today, topics[index].state!.due!),
                last: index == topics.length - 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One topic: its number, title, rule on one line and due state, its dot
/// and a chevron to L4.
class TopicRow extends StatelessWidget {
  const TopicRow({
    required this.number,
    required this.topic,
    required this.due,
    required this.daysLeft,
    required this.last,
    super.key,
  });

  final int number;
  final TopicWithState topic;
  final TopicDue due;

  /// Days until it is due, for "next practice in 4 d".
  final int daysLeft;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final rule = topic.topic.rule?.split('\n').first.trim();
    final (String? line, Color? lineColour) = switch (due) {
      TopicDue.due => (l10n.stepTopicDueToday, tokens.color.link),
      TopicDue.scheduled => (
        l10n.stepTopicNextIn(daysLeft),
        tokens.color.textSecondary,
      ),
      TopicDue.suspended => (
        l10n.wordStatusSuspended,
        tokens.color.textSecondary,
      ),
      TopicDue.notLearned => (null, null),
    };

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => GrammarTopicRoute.open(context, topic.uid),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          decoration: BoxDecoration(
            color: tokens.surface.card,
            border: last
                ? null
                : Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                child: DpText(
                  '$number',
                  role: DpTextRole.label,
                  weight: 700,
                  color: tokens.color.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(
                      topic.topic.topic,
                      role: DpTextRole.body,
                      weight: 600,
                    ),
                    if (rule != null && rule.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      DpOneLine(
                        rule,
                        role: DpTextRole.label,
                        weight: 400,
                        color: tokens.color.textSecondary,
                      ),
                    ],
                    if (line != null) ...<Widget>[
                      const SizedBox(height: 2),
                      DpText(line, role: DpTextRole.caption, color: lineColour),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TopicDot(due: due),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A topic's 10 dp status dot: Sun when due, Lime when scheduled, hollow
/// before it is learned.
class TopicDot extends StatelessWidget {
  const TopicDot({required this.due, super.key});

  final TopicDue due;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (due) {
          TopicDue.due => tokens.color.learning,
          TopicDue.scheduled => tokens.color.easy,
          TopicDue.suspended => tokens.color.textSecondary,
          TopicDue.notLearned => tokens.surface.muted,
        },
        border: Border.all(color: tokens.color.ink),
      ),
    );
  }
}
