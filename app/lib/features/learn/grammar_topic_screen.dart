import 'dart:math' as math;

import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/course_text.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/plan_engine.dart' show daysBetween;
import 'package:deutschplan/features/learn/step_grammar.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'grammar_topic_screen.g.dart';

/// One topic and the learner's state with it, live: *Mark as learned* shows
/// at once.
@riverpod
Stream<TopicWithState?> grammarTopic(Ref ref, String uid) =>
    ref.watch(grammarRepositoryProvider).watchTopic(uid);

/// What the generator reads of [topic].
GrammarSource grammarSource(TopicWithState topic) => GrammarSource(
  uid: topic.uid,
  topic: topic.topic.topic,
  rule: topic.topic.rule ?? '',
  exampleDe: topic.topic.exampleDe ?? '',
  exampleEn: topic.topic.exampleEn ?? '',
  watchOut: topic.topic.watchOut ?? '',
  tags: topic.tags,
  levelCode: topic.topic.levelCode,
);

/// What the generator checks its forms against and takes *Pick the form*'s
/// sentence from (#330), read once. A read that fails practises without it,
/// as before #330, rather than not at all.
@riverpod
Future<CourseText> grammarCourse(Ref ref) async {
  try {
    return await loadCourseText(ref.watch(appDatabaseProvider));
  } on Object {
    return CourseText.none;
  }
}

/// [topic]'s items for [day], its step's other rules the recall options —
/// what L15 will ask, so L4 can say how many.
List<GrammarItem> practiceItemsFor(
  TopicWithState topic,
  List<TopicWithState> step,
  String day,
  CourseText course,
) => generateItems(
  grammarSource(topic),
  seed: practiceSeed(topic.uid, day),
  siblings: <String>[
    for (final other in step)
      if (other.uid != topic.uid && other.topic.rule != null) other.topic.rule!,
  ],
  course: course,
);

/// L4 · Grammar topic (`grammar-topic.md`, `GrammarTopic-android.html`): one
/// rule — its text, its examples with play, the *Watch out* callout — with
/// *Practise this rule* and *Mark as learned*, and the step's previous and
/// next topics.
class GrammarTopicScreen extends ConsumerWidget {
  const GrammarTopicScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final topic = ref.watch(grammarTopicProvider(uid)).value;
    final step = topic == null
        ? null
        : ref.watch(stepTopicsProvider(topic.topic.sublevelCode)).value;
    final course = ref.watch(grammarCourseProvider).value;

    final body = topic == null || step == null
        ? const SizedBox.expand()
        : _Topic(topic: topic, step: step, course: course);

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

class _Topic extends ConsumerWidget {
  const _Topic({required this.topic, required this.step, required this.course});

  final TopicWithState topic;
  final List<TopicWithState> step;

  /// Null while it loads: the page shows, and only *Practise* waits (#386).
  final CourseText? course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final index = step.indexWhere((other) => other.uid == topic.uid);
    final previous = index > 0 ? step[index - 1] : null;
    final next = index >= 0 && index < step.length - 1 ? step[index + 1] : null;
    final ready = course;
    final items = ready == null
        ? null
        : practiceItemsFor(topic, step, today, ready);
    final rule = topic.topic.rule;
    final watchOut = topic.topic.watchOut;
    final examples = examplePairs(
      topic.topic.exampleDe ?? '',
      topic.topic.exampleEn ?? '',
    );
    final due = topicDue(topic, today);

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _Header(
          topic: topic,
          place: index < 0 ? null : (index + 1, step.length),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (rule != null && rule.isNotEmpty) ...<Widget>[
                _Label(l10n.topicRule),
                const SizedBox(height: 6),
                DpText(rule, role: DpTextRole.bodyLarge),
                const SizedBox(height: 14),
              ],
              if (examples.isNotEmpty) ...<Widget>[
                _Label(l10n.topicExamples),
                for (final example in examples) ...<Widget>[
                  const SizedBox(height: 8),
                  _Example(german: example.german, english: example.english),
                ],
                const SizedBox(height: 14),
              ],
              if (watchOut != null && watchOut.isNotEmpty) ...<Widget>[
                WatchOut(text: watchOut),
                const SizedBox(height: 16),
              ],
              // FR-L4-02: L15 for this topic; finishing it marks it learned.
              // Its count waits for the course; the rest of the page doesn't.
              if (items == null)
                const SizedBox(height: DpButton.primaryHeight)
              else
                DpButton(
                  label: l10n.topicPractise(items.length),
                  onPressed: () => GrammarPracticeRoute.open(
                    context,
                    GrammarPracticeArgs(topicUids: <String>[topic.uid]),
                  ),
                ),
              const SizedBox(height: 8),
              if (due == TopicDue.notLearned)
                _MarkLearned(uid: topic.uid)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: DpText(
                    switch (due) {
                      TopicDue.due => l10n.topicLearnedDue,
                      TopicDue.suspended => l10n.wordStatusSuspended,
                      _ => l10n.topicLearnedNext(
                        daysBetween(today, topic.state!.due!),
                      ),
                    },
                    role: DpTextRole.body,
                    weight: 600,
                    textAlign: TextAlign.center,
                    color: tokens.color.textSecondary,
                  ),
                ),
              const SizedBox(height: 8),
              // FR-L4-04: the step's neighbours, in its teaching order.
              Row(
                children: <Widget>[
                  if (previous != null)
                    Expanded(child: _Neighbour(topic: previous, forward: false))
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  if (next != null)
                    Expanded(child: _Neighbour(topic: next, forward: true))
                  else
                    const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// FR-L4-01's button. Inert while its write is in flight: a second tap
/// before the topic re-emits would be a second review rated Good.
class _MarkLearned extends ConsumerStatefulWidget {
  const _MarkLearned({required this.uid});

  final String uid;

  @override
  ConsumerState<_MarkLearned> createState() => _MarkLearnedState();
}

class _MarkLearnedState extends ConsumerState<_MarkLearned> {
  bool _busy = false;

  Future<void> _mark() async {
    // Checked here too: two taps inside one frame both reach the callback
    // the button was built with.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(grammarRatingServiceProvider).markLearned(widget.uid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DpButton(
    label: AppLocalizations.of(context).topicMarkLearned,
    kind: DpButtonKind.secondary,
    onPressed: _busy ? null : () => unawaited(_mark()),
  );
}

/// L4's Sun header: back, the step chip and "Topic 4 of 10", the title.
class _Header extends StatelessWidget {
  const _Header({required this.topic, required this.place});

  final TopicWithState topic;

  /// Where it stands in its step, 1-based.
  final (int, int)? place;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final cupertino = context.isCupertino;
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: MediaQuery.paddingOf(context).top),
        // The bar's height, or the back button's when larger text makes
        // its label taller (#404).
        SizedBox(
          height: math.max(
            cupertino
                ? AdaptiveScaffold.cupertinoBarHeight
                : AdaptiveScaffold.materialBarHeight,
            AdaptiveBackButton.heightOf(
              context,
              label: topic.topic.sublevelCode,
            ),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 4),
              AdaptiveBackButton(
                label: topic.topic.sublevelCode,
                colour: cupertino ? null : ink,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DpChip(label: topic.topic.sublevelCode, ink: ink),
                  if (place case (final at, final of)) ...<Widget>[
                    const SizedBox(width: 8),
                    DpText(
                      l10n.topicPlace(at, of),
                      role: DpTextRole.caption,
                      weight: 700,
                      color: ink,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              DpText(topic.topic.topic, role: DpTextRole.title, color: ink),
            ],
          ),
        ),
      ],
    );
    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.accent),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.accent, child: content);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DpText(
    text.toUpperCase(),
    role: DpTextRole.caption,
    weight: 700,
    letterSpacing: 0.6,
    color: context.tokens.color.textSecondary,
  );
}

/// An example with play (FR-L4-03): the German spoken, its translation
/// under it.
class _Example extends ConsumerWidget {
  const _Example({required this.german, required this.english});

  final String german;
  final String? english;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          label: l10n.topicPlay(german),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(say(ref, context, german)),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surface.muted,
                    border: Border.all(color: tokens.color.ink, width: 1.5),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: tokens.color.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DpText(german, role: DpTextRole.bodyLarge, italic: true),
              if (english != null)
                DpText(
                  english!,
                  role: DpTextRole.body,
                  color: tokens.color.textSecondary,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Tangerine *Watch out* callout.
class WatchOut extends StatelessWidget {
  const WatchOut({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: tokens.surface.muted,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: 6, child: ColoredBox(color: tokens.color.hard)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DpText(
                        l10n.topicWatchOut.toUpperCase(),
                        role: DpTextRole.caption,
                        weight: 700,
                        letterSpacing: 0.6,
                      ),
                      const SizedBox(height: 2),
                      DpText(text, role: DpTextRole.body),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The previous or next topic of the step, as an arrow and its title.
class _Neighbour extends StatelessWidget {
  const _Neighbour({required this.topic, required this.forward});

  final TopicWithState topic;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final arrow = Icon(
      forward ? Icons.chevron_right : Icons.chevron_left,
      size: 18,
      color: tokens.color.link,
    );
    void open() => GrammarTopicRoute.instead(context, topic.uid);
    return Semantics(
      button: true,
      label: forward
          ? l10n.topicNext(topic.topic.topic)
          : l10n.topicPrevious(topic.topic.topic),
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: forward
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: <Widget>[
              if (!forward) arrow,
              const SizedBox(width: 4),
              Flexible(
                child: DpOneLine(
                  topic.topic.topic,
                  role: DpTextRole.label,
                  color: tokens.color.link,
                ),
              ),
              const SizedBox(width: 4),
              if (forward) arrow,
            ],
          ),
        ),
      ),
    );
  }
}
