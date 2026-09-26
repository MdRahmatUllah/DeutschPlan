import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/learn/grammar_topic_screen.dart';
import 'package:deutschplan/features/study/study_cloze.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/features/study/write_guard.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'grammar_practice_screen.g.dart';

/// One topic's run: the topic, and today's items for it.
typedef PracticeSet = ({TopicWithState topic, List<GrammarItem> items});

/// FR-L15-01: [uid]'s items from the generator, seeded per topic and day,
/// its step's other rules the recall options — the same as L4 counts.
@riverpod
Future<PracticeSet?> practiceSet(Ref ref, String uid) async {
  final grammar = ref.watch(grammarRepositoryProvider);
  final topic = await grammar.find(uid);
  if (topic == null) return null;
  final step = await grammar.step(topic.topic.sublevelCode);
  final course = await ref.watch(grammarCourseProvider.future);
  return (
    topic: topic,
    items: practiceItemsFor(topic, step, ref.watch(todayProvider), course),
  );
}

/// L15 · Grammar practice (`grammar-practice.md`, `GrammarPractice-android.html`):
/// each topic's 3–5 items with immediate feedback, the topic rated as a
/// whole on its last, and due topics back to back.
class GrammarPracticeScreen extends ConsumerStatefulWidget {
  const GrammarPracticeScreen({required this.topicUids, super.key});

  final List<String> topicUids;

  /// How long the next topic's banner shows (FR-L15-04).
  static const Duration bannerTime = Duration(milliseconds: 1600);

  @override
  ConsumerState<GrammarPracticeScreen> createState() =>
      _GrammarPracticeScreenState();
}

class _GrammarPracticeScreenState extends ConsumerState<GrammarPracticeScreen> {
  int _topic = 0;
  int _item = 0;
  int _correct = 0;

  /// Right or wrong once the current item is answered; null before.
  bool? _right;

  /// The right answer was a near miss (BR-ANS-01): it counts as right, and
  /// says so as T2's cloze does (#345).
  bool _almost = false;

  /// What the learner gave, for the options to show their pick.
  String? _given;
  int _answers = 0;

  bool _banner = false;
  Timer? _hide;
  bool _leaving = false;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _answer({required bool right, String? given, bool almost = false}) {
    if (_right != null) return;
    setState(() {
      _right = right;
      _almost = almost;
      _given = given;
      if (right) _correct++;
    });
  }

  /// *Next*: the next item, or the topic rated and the next topic, or out.
  Future<void> _next(PracticeSet set) async {
    if (_right == null || _leaving) return;
    if (_item < set.items.length - 1) {
      setState(() {
        _item++;
        _right = null;
        _given = null;
        _answers++;
      });
      return;
    }
    // FR-L15-03: the topic as a whole, on its last item. A write that fails
    // keeps the topic, with Retry and Export (#174).
    _leaving = true;
    final written = await guardWrite(context, () async {
      await ref
          .read(grammarRatingServiceProvider)
          .ratePractice(
            set.topic.uid,
            items: set.items.length,
            correct: _correct,
          );
      return true;
    });
    if (!mounted) return;
    if (!written) {
      _leaving = false;
      return;
    }
    if (_topic < widget.topicUids.length - 1) {
      setState(() {
        _topic++;
        _item = 0;
        _correct = 0;
        _right = null;
        _given = null;
        _answers++;
        _banner = true;
        _leaving = false;
      });
      _hide?.cancel();
      _hide = Timer(GrammarPracticeScreen.bannerTime, () {
        if (mounted) setState(() => _banner = false);
      });
      return;
    }
    await _finish();
  }

  /// Every topic done: T6 if that completes the day, else back.
  Future<void> _finish() async {
    final today = ref.read(todayProvider);
    ref.invalidate(studyNextProvider(today));
    // Listened to while it answers: read alone, an auto-disposing provider
    // can go before its future does.
    final hold = ref.listenManual(studyNextProvider(today), (_, _) {});
    final next = await ref.read(studyNextProvider(today).future);
    hold.close();
    if (!mounted) return;
    if (next.dayDone && next.sentences == 0) {
      DayCompleteRoute.instead(context);
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _seeRule(TopicWithState topic) => unawaited(
    Adaptive.showSheet<void>(
      context: context,
      builder: (sheet) => RuleSheet(topic: topic),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final uid = widget.topicUids.isEmpty ? null : widget.topicUids[_topic];
    final set = uid == null ? null : ref.watch(practiceSetProvider(uid)).value;

    final Widget body;
    if (set == null || set.items.isEmpty) {
      body = const SizedBox.expand();
    } else {
      final item = set.items[_item];
      final right = _right;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PracticeHeader(
            title: set.topic.topic.topic,
            place: (_item + 1, set.items.length),
            onClose: () => Navigator.of(context).maybePop(),
          ),
          PracticeStrip(done: _item + 1, of: set.items.length),
          if (widget.topicUids.length > 1)
            _TopicBanner(
              visible: _banner,
              label: l10n.practiceNextTopic(
                _topic + 1,
                widget.topicUids.length,
                set.topic.topic.topic,
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: <Widget>[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DpChip(
                    label: itemKind(l10n, item),
                    kind: DpChipKind.status,
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  // A fresh field and fresh chips for every item.
                  key: ValueKey<int>(_answers),
                  child: PracticeItemView(
                    item: item,
                    answered: right != null,
                    given: _given,
                    onAnswer: _answer,
                  ),
                ),
                if (right != null) ...<Widget>[
                  const SizedBox(height: 16),
                  PracticeFeedback(
                    right: right,
                    almost: _almost,
                    answer: itemAnswer(item),
                    rule: set.topic.topic.rule,
                    onSeeRule: () => _seeRule(set.topic),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: DpButton(
              label: l10n.practiceNext,
              onPressed: right == null ? null : () => unawaited(_next(set)),
            ),
          ),
        ],
      );
    }

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

/// The item's kind, as its chip names it.
String itemKind(AppLocalizations l10n, GrammarItem item) => switch (item) {
  GapFill() => l10n.practiceGapFill,
  PickTheForm() => l10n.practicePickTheForm,
  SpotTheError() => l10n.practiceSpotTheError,
  OrderTheSentence() => l10n.practiceOrderTheSentence,
  RuleRecall() => l10n.practiceRuleRecall,
};

/// The right answer, as the feedback line gives it.
String itemAnswer(GrammarItem item) => switch (item) {
  GapFill(:final answer) || PickTheForm(:final answer) => answer,
  SpotTheError(:final correction) => correction,
  OrderTheSentence(:final answer) => answer.join(' '),
  RuleRecall(:final options, :final answer) => options[answer],
};

/// Close · the topic · "3 / 5", on Sun. L8's quiz runner wears it too.
class PracticeHeader extends StatelessWidget {
  const PracticeHeader({
    required this.title,
    required this.place,
    required this.onClose,
    super.key,
    this.closeLabel,
  });

  final String title;
  final (int, int) place;
  final VoidCallback onClose;

  /// What a screen reader calls the close button: "Close practice" unless
  /// given.
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final content = Column(
      children: <Widget>[
        SizedBox(height: MediaQuery.paddingOf(context).top),
        // The artboard's 56, grown with the text size (#165).
        SizedBox(
          height: DpScript.grow(context, 56),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: closeLabel ?? l10n.practiceClose,
                onTap: onClose,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.close, color: ink),
                  ),
                ),
              ),
              Expanded(
                child: DpText(
                  title,
                  role: DpTextRole.bodyLarge,
                  weight: 600,
                  color: ink,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              // 52, grown with the text size: at 200 % a fixed 52 wrapped
              // "7 / 20" onto two lines and cut it (#165).
              SizedBox(
                width: DpScript.grow(context, 52, role: DpTextRole.label),
                child: DpText(
                  l10n.digits('${place.$1} / ${place.$2}'),
                  role: DpTextRole.label,
                  weight: 700,
                  color: ink,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 4),
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

/// One segment per item, Sun up to the current one.
class PracticeStrip extends StatelessWidget {
  const PracticeStrip({required this.done, required this.of, super.key});

  final int done;
  final int of;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < of; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: ColoredBox(
                    // To do at 3:1 on the page (#437).
                    color: i < done
                        ? tokens.color.accent
                        : tokens.surface.track,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// FR-L15-04: the next topic's name, for a moment, as it starts.
class _TopicBanner extends StatelessWidget {
  const _TopicBanner({required this.visible, required this.label});

  final bool visible;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    final Widget shown = visible
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: DpSurface(
                kind: DpSurfaceKind.tint(tokens.color.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: DpText(label, role: DpTextRole.label),
              ),
            ),
          )
        : const SizedBox(width: double.infinity);
    // #164: reduce motion shows it without the size animation; a zero
    // duration breaks AnimatedSize's layout (as study_card.dart says).
    if (still) return shown;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      child: shown,
    );
  }
}

/// An item, laid out for its kind (FR-L15's five layouts).
class PracticeItemView extends StatelessWidget {
  const PracticeItemView({
    required this.item,
    required this.answered,
    required this.given,
    required this.onAnswer,
    super.key,
  });

  final GrammarItem item;
  final bool answered;
  final String? given;
  final void Function({required bool right, String? given, bool almost})
  onAnswer;

  @override
  Widget build(BuildContext context) => switch (item) {
    GapFill(:final before, :final after, :final answer, :final translation) =>
      _GapFillView(
        before: before,
        after: after,
        answer: answer,
        translation: translation,
        answered: answered,
        onAnswer: onAnswer,
      ),
    PickTheForm(
      :final before,
      :final after,
      :final options,
      :final answer,
      :final translation,
    ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Sentence(
            before: before,
            after: after,
            filled: answered ? answer : null,
          ),
          if (translation.isNotEmpty) _Translation(translation),
          const SizedBox(height: 14),
          _Options(
            options: options,
            answer: answer,
            given: given,
            answered: answered,
            onPick: (option) =>
                onAnswer(right: option == answer, given: option),
          ),
        ],
      ),
    SpotTheError(:final tokens, :final wrong) => _SpotView(
      words: tokens,
      wrong: wrong,
      given: given,
      answered: answered,
      onAnswer: onAnswer,
    ),
    OrderTheSentence(:final chips, :final answer) => _OrderView(
      chips: chips,
      answer: answer,
      answered: answered,
      onAnswer: onAnswer,
    ),
    RuleRecall(:final question, :final options, :final answer) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          AppLocalizations.of(context).practiceRecallQuestion(question),
          role: DpTextRole.title,
        ),
        const SizedBox(height: 14),
        _Options(
          options: options,
          answer: options[answer],
          given: given,
          answered: answered,
          onPick: (option) =>
              onAnswer(right: option == options[answer], given: option),
        ),
      ],
    ),
  };
}

/// "Könnten ___ Sie mir helfen?", the gap filled once answered.
class _Sentence extends StatelessWidget {
  const _Sentence({
    required this.before,
    required this.after,
    required this.filled,
  });

  final String before;
  final String after;
  final String? filled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = DpText.styleFor(tokens, DpTextRole.title);
    // Punctuation sits against the gap; words get a space.
    final tail = after.isEmpty || RegExp(r'^[.,!?;:…]').hasMatch(after)
        ? after
        : ' $after';
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          if (before.isNotEmpty) TextSpan(text: '$before '),
          TextSpan(
            text: filled ?? '_____',
            style: style.copyWith(
              color: filled == null ? tokens.color.textSecondary : null,
              fontWeight: filled == null ? null : FontWeight.w700,
            ),
          ),
          TextSpan(text: tail),
        ],
      ),
    );
  }
}

class _Translation extends StatelessWidget {
  const _Translation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: DpText(
      text,
      role: DpTextRole.label,
      weight: 400,
      color: context.tokens.color.textSecondary,
    ),
  );
}

/// Option tiles: once picked, the right one Lime with a tick and a wrong
/// pick Coral with a cross; the rest fade.
class _Options extends StatelessWidget {
  const _Options({
    required this.options,
    required this.answer,
    required this.given,
    required this.answered,
    required this.onPick,
  });

  final List<String> options;
  final String answer;
  final String? given;
  final bool answered;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final option in options) ...<Widget>[
          Builder(
            builder: (context) {
              final right = answered && option == answer;
              final wrongPick = answered && option == given && option != answer;
              final faded = answered && !right && !wrongPick;
              final label = Row(
                children: <Widget>[
                  Expanded(
                    child: DpText(
                      option,
                      role: DpTextRole.bodyLarge,
                      weight: 600,
                      color: faded ? tokens.color.textSecondary : null,
                    ),
                  ),
                  if (right) Icon(Icons.check, color: tokens.color.correctText),
                  if (wrongPick)
                    Icon(Icons.close, color: tokens.color.wrongText),
                ],
              );
              const padding = EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              );
              // Answered, the artboard draws the right tile and a wrong pick
              // flat, washed in their verdict and edged in it — no shadow.
              final verdict = right
                  ? (tokens.color.easy, tokens.color.correctText)
                  : wrongPick
                  ? (tokens.color.again, tokens.color.wrongText)
                  : null;
              final tile = verdict == null
                  ? DpSurface(
                      kind: DpSurfaceKind.bar,
                      onTap: answered ? null : () => onPick(option),
                      padding: padding,
                      child: label,
                    )
                  : Container(
                      padding: padding,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          verdict.$1.withValues(alpha: 0.25),
                          tokens.surface.card,
                        ),
                        borderRadius: BorderRadius.circular(tokens.shape.card),
                        border: Border.all(color: verdict.$2, width: 2),
                      ),
                      child: label,
                    );
              return Semantics(
                button: !answered,
                selected: option == given,
                child: tile,
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Gap fill: the answer typed, with the umlaut row, checked as German.
class _GapFillView extends StatefulWidget {
  const _GapFillView({
    required this.before,
    required this.after,
    required this.answer,
    required this.translation,
    required this.answered,
    required this.onAnswer,
  });

  final String before;
  final String after;
  final String answer;
  final String translation;
  final bool answered;
  final void Function({required bool right, String? given, bool almost})
  onAnswer;

  @override
  State<_GapFillView> createState() => _GapFillViewState();
}

class _GapFillViewState extends State<_GapFillView> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _check() {
    if (widget.answered || _typed.text.trim().isEmpty) return;
    final verdict = checkGerman(_typed.text, widget.answer);
    // An *almost* counts as right for the topic's rating (BR-FSRS-05): it is
    // a typo, not a miss (the lead's call, #345).
    final almost = verdict == Verdict.almost;
    widget.onAnswer(
      right: verdict.isRight || almost,
      almost: almost,
      given: _typed.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Sentence(
          before: widget.before,
          after: widget.after,
          filled: widget.answered ? widget.answer : null,
        ),
        if (widget.translation.isNotEmpty) _Translation(widget.translation),
        if (!widget.answered) ...<Widget>[
          const SizedBox(height: 14),
          StudyAnswerField(controller: _typed, onSubmitted: _check),
          const SizedBox(height: 8),
          DpUmlautBar(controller: _typed),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: _typed,
            builder: (context, _) => DpButton(
              label: l10n.practiceCheck,
              kind: DpButtonKind.secondary,
              onPressed: _typed.text.trim().isEmpty ? null : _check,
            ),
          ),
        ],
      ],
    );
  }
}

/// Spot the error: the sentence's words, one of them wrong; tap it.
class _SpotView extends StatelessWidget {
  const _SpotView({
    required this.words,
    required this.wrong,
    required this.given,
    required this.answered,
    required this.onAnswer,
  });

  final List<String> words;
  final int wrong;
  final String? given;
  final bool answered;
  final void Function({required bool right, String? given, bool almost})
  onAnswer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          l10n.practiceSpotPrompt,
          role: DpTextRole.label,
          weight: 400,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var i = 0; i < words.length; i++)
              _WordChip(
                word: words[i],
                tone: !answered
                    ? null
                    : i == wrong
                    ? tokens.color.easy
                    : '$i' == given
                    ? tokens.color.again
                    : null,
                onTap: answered
                    ? null
                    : () => onAnswer(right: i == wrong, given: '$i'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Order the sentence: tap the chips in order; tap a placed one to take it
/// back; check once all are placed.
class _OrderView extends StatefulWidget {
  const _OrderView({
    required this.chips,
    required this.answer,
    required this.answered,
    required this.onAnswer,
  });

  final List<String> chips;
  final List<String> answer;
  final bool answered;
  final void Function({required bool right, String? given, bool almost})
  onAnswer;

  @override
  State<_OrderView> createState() => _OrderViewState();
}

class _OrderViewState extends State<_OrderView> {
  /// Indexes into the chips, in the order placed.
  final List<int> _placed = <int>[];

  void _check() {
    final built = <String>[for (final i in _placed) widget.chips[i]];
    var same = built.length == widget.answer.length;
    for (var i = 0; same && i < built.length; i++) {
      same = built[i] == widget.answer[i];
    }
    widget.onAnswer(right: same, given: built.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          l10n.practiceOrderPrompt,
          role: DpTextRole.label,
          weight: 400,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 12),
        // The sentence as built so far.
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.surface.outline, width: 1.5),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final i in _placed)
                _WordChip(
                  word: widget.chips[i],
                  onTap: widget.answered
                      ? null
                      : () => setState(() => _placed.remove(i)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var i = 0; i < widget.chips.length; i++)
              if (!_placed.contains(i))
                _WordChip(
                  word: widget.chips[i],
                  onTap: widget.answered
                      ? null
                      : () => setState(() => _placed.add(i)),
                ),
          ],
        ),
        if (!widget.answered) ...<Widget>[
          const SizedBox(height: 12),
          DpButton(
            label: l10n.practiceCheck,
            kind: DpButtonKind.secondary,
            onPressed: _placed.length == widget.chips.length ? _check : null,
          ),
        ],
      ],
    );
  }
}

/// A word as a tappable chip: Spot the error's tokens, Order the sentence's
/// pieces.
class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.onTap, this.tone});

  final String word;
  final VoidCallback? onTap;

  /// Lime for the right word, Coral for a wrong tap, once answered.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: DpSurface(
        kind: tone == null
            ? DpSurfaceKind.bar
            : DpSurfaceKind.tint(tone!, opacity: 0.3),
        radius: 10,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DpText(word, role: DpTextRole.bodyLarge),
      ),
    );
  }
}

/// FR-L15-02: right; *almost*, with the answer's spelling; or "Not quite —
/// the answer is Könnten" with the rule's first line and *See rule*.
class PracticeFeedback extends StatelessWidget {
  const PracticeFeedback({
    required this.right,
    required this.answer,
    required this.rule,
    required this.onSeeRule,
    this.almost = false,
    super.key,
  });

  final bool right;

  /// A right answer that was a near miss (BR-ANS-01, #345).
  final bool almost;
  final String answer;
  final String? rule;
  final VoidCallback onSeeRule;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final line = rule?.split(RegExp(r'(?<=[.!?;])\s')).first.trim();
    // The artboard's flat Oat panel: no edge, no shadow.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DpVerdictRow(
            verdict: almost
                ? DpVerdict.almost
                : right
                ? DpVerdict.correct
                : DpVerdict.wrong,
            message: almost
                ? l10n.practiceAlmost(answer)
                : right
                ? l10n.practiceRight
                : l10n.practiceNotQuite(answer),
          ),
          if (!right && line != null && line.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            DpText(l10n.practiceRuleLine(line), role: DpTextRole.body),
            DpButton(
              label: l10n.practiceSeeRule,
              kind: DpButtonKind.text,
              expand: false,
              onPressed: onSeeRule,
            ),
          ],
        ],
      ),
    );
  }
}

/// *See rule*: the topic's rule and *Watch out*, over the run, so the
/// learner comes back to the same item.
class RuleSheet extends StatelessWidget {
  const RuleSheet({required this.topic, super.key});

  final TopicWithState topic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rule = topic.topic.rule;
    final watchOut = topic.topic.watchOut;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DpText(topic.topic.topic, role: DpTextRole.title),
            if (rule != null && rule.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              DpText(rule, role: DpTextRole.bodyLarge),
            ],
            if (watchOut != null && watchOut.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              WatchOut(text: watchOut),
            ],
            const SizedBox(height: 16),
            DpButton(
              label: l10n.practiceBackToItem,
              kind: DpButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
