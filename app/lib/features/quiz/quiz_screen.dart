import 'dart:async';

import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_pill.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/quiz_run_service.dart';
import 'package:sogda/domain/answer_check.dart';
import 'package:sogda/domain/quiz_builder.dart';
import 'package:sogda/domain/quiz_queue.dart';
import 'package:sogda/features/learn/grammar_practice_screen.dart'
    show PracticeHeader;
import 'package:sogda/features/learn/step_quiz.dart';
import 'package:sogda/features/quiz/quiz_item_view.dart';
import 'package:sogda/features/quiz/quiz_result_screen.dart';
import 'package:sogda/features/study/write_guard.dart';
import 'package:sogda/features/words/speak.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// L8's title: "Standard · DE → EN", or "Forms", or W2's "Compare".
String quizTitle(AppLocalizations l10n, QuizArgs args) =>
    args.direction == QuizDirection.forms.name ||
        args.direction == QuizDirection.compare.name
    ? quizDirectionName(l10n, args.direction)
    : '${quizKindName(l10n, args.length)} · '
          '${quizDirectionName(l10n, args.direction)}';

/// L8 · Quiz runner (`quiz.md`, `QuizRunner-android.html`, #123): a
/// full-screen modal with close, the title and "7 / 20" on Sun, the progress
/// strip, and the optional 15 s timer. Each answer is graded, recorded as it
/// is given, and the run finishes when the last one is.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({required this.args, super.key});

  final QuizArgs args;

  /// FR-L8-05: a question's time when the timer is on.
  static const int questionSeconds = 15;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  QuizRun? _run;
  Object? _error;

  /// The quiz, then its mistakes once more (FR-L8-03).
  QuizQueue _queue = QuizQueue(const <QuizItem>[]);

  /// The current item's verdict once answered; null before.
  Verdict? _verdict;
  String _given = '';

  /// The answered item's feedback, scrolled into view once it shows (#574).
  final GlobalKey _feedback = GlobalKey();
  bool _timedOut = false;
  double _points = 0;

  /// Bumped per item, so the field and its controller start empty.
  int _answers = 0;
  final TextEditingController _field = TextEditingController();

  Timer? _tick;
  int _left = QuizScreen.questionSeconds;

  /// Set once the run is being left, so no second tap races the exit.
  bool _leaving = false;

  /// Set while an answer is being written, so a second tap writes nothing.
  bool _saving = false;

  /// The finished run's attempt: L9 takes the screen's place (#126).
  int? _resultOf;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _field.dispose();
    super.dispose();
  }

  QuizRunService get _service => ref.read(quizRunServiceProvider);

  Future<void> _start() async {
    final args = widget.args;
    try {
      final run = await _service.start(
        direction: QuizDirection.parse(args.direction),
        source: QuizSource.parse(args.source),
        sourceRef: args.sourceRef,
        length: args.length,
        seed: args.seed,
        today: ref.read(todayProvider),
      );
      if (!mounted) return;
      setState(() {
        _run = run;
        _queue = QuizQueue(run.quiz.items);
      });
      _startClock();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// FR-L8-05: 15 s for the question when the timer is on; at 0 an empty
  /// answer goes in, and it is wrong. [resume] carries on from the seconds
  /// left.
  void _startClock({bool resume = false}) {
    _tick?.cancel();
    if (!widget.args.timer || (_run?.quiz.items.isEmpty ?? true)) return;
    if (!resume) _left = QuizScreen.questionSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        timer.cancel();
        unawaited(_submit('', timedOut: true));
      }
    });
  }

  Future<void> _submit(String given, {bool timedOut = false}) async {
    final run = _run;
    if (run == null || _verdict != null || _saving) return;
    if (!timedOut && given.trim().isEmpty) return;
    _tick?.cancel();
    final item = _queue.current;
    final reask = _queue.reasking;
    final verdict = timedOut ? Verdict.wrong : grade(item, given);

    // #647: saved before it is shown or scored. A write that fails keeps the
    // question, with Retry and Export (#174): a verdict on screen that was
    // never saved was a score L9 could not match, and a rating FSRS never had.
    _saving = true;
    final written = await guardWrite(context, () async {
      if (reask) {
        await _service.reasked(run, item);
      } else {
        await _service.answer(run, item, given: given.trim(), verdict: verdict);
      }
      return true;
    });
    _saving = false;
    if (!written || !mounted) return;

    _queue.answered(verdict);
    setState(() {
      _verdict = verdict;
      _given = given.trim();
      _timedOut = timedOut;
      // FR-L8-03: a re-ask is feedback, not score.
      if (!reask) _points += verdict.score;
    });
    // #574: the feedback is the list's last row, and *Next*'s row coming
    // back shrinks the list: typing on a short phone, the verdict was built
    // under the window and *Next* could be pressed unseen. A jump, so no
    // motion to reduce.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shown = _feedback.currentContext;
      if (shown == null || !shown.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          shown,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  /// *Next*: the next item, or the run finished and closed.
  Future<void> _next() async {
    final run = _run;
    if (run == null || _verdict == null || _leaving) return;
    if (_queue.next()) {
      setState(() {
        _verdict = null;
        _timedOut = false;
        _answers++;
        _field.clear();
      });
      _startClock();
      return;
    }
    // #647: a finish that fails keeps the run, with Retry and Export (#174).
    // Closing the sheet leaves *Next* and back working: stuck on `_leaving`,
    // both did nothing, and the only way out was to kill the app.
    _leaving = true;
    final written = await guardWrite(context, () async {
      await _service.finish(run, points: _points);
      return true;
    });
    if (!mounted) return;
    if (!written) {
      _leaving = false;
      return;
    }
    setState(() => _resultOf = run.attemptId);
  }

  /// FR-L8-04: closing asks first; what was answered is already saved.
  Future<void> _close() async {
    if (_leaving) return;
    final run = _run;
    if (run == null || run.quiz.items.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    // The clock stops while the learner decides: *Keep going* must not
    // come back to a question the timer has already failed.
    final ticking = _tick?.isActive ?? false;
    _tick?.cancel();
    final stop = await Adaptive.showConfirm(
      context: context,
      title: l10n.quizStopTitle,
      message: l10n.quizStopBody,
      confirmLabel: l10n.quizStop,
      cancelLabel: l10n.quizKeepGoing,
    );
    if (!mounted) return;
    if (stop != true) {
      if (ticking) _startClock(resume: true);
      return;
    }
    _leaving = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // L8 → L9 in the one route (`navigation.md`): back from the result just
    // leaves.
    if (_resultOf case final attemptId?) {
      return QuizResultView(attemptId: attemptId, args: widget.args);
    }
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final run = _run;
    // #554: typing at large text, the field alone filled the room above the
    // keyboard and the prompt scrolled away. The header's row and the
    // answer's caption give theirs to the prompt, and come back with the
    // keyboard's going.
    final typing = SgScript.largeTyping(context);

    final Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SgErrorPanel(
            message: l10n.quizLoadFailed,
            retryLabel: l10n.retry,
            onRetry: () {
              setState(() => _error = null);
              unawaited(_start());
            },
          ),
        ),
      );
    } else if (run == null) {
      body = const SizedBox.expand();
    } else if (run.quiz.items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SgText(
            l10n.quizEmpty,
            role: SgTextRole.body,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
        ),
      );
    } else {
      final items = run.quiz.items;
      final item = _queue.current;
      final verdict = _verdict;
      final typed = item.direction != QuizDirection.articles && !item.tiles;
      // #568: typing German past 130 %, *Check* joins the umlaut row: in
      // Bangla, whose copy is a role larger, its own row left a Forms prompt
      // 45 dp under the strip.
      final checkOnKeys =
          typing && typed && typesGerman(item) && verdict == null;
      final onceMore = _queue.reasking
          ? SgChip(label: l10n.quizOnceMore, kind: SgChipKind.status)
          : null;
      final ask = SgChip(label: askName(l10n, item), kind: SgChipKind.status);
      final timer = widget.args.timer && verdict == null
          ? SgPill(
              label: l10n.quizSecondsLeft(_left),
              fill: _left <= 5 ? tokens.color.again : tokens.surface.muted,
            )
          : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // #568: typing past 130 %, the strip's row is the prompt's too.
          if (typing)
            const SizedBox.shrink()
          else
            _QuizStrip(
              done: _queue.reasking ? items.length : item.ord,
              of: items.length,
            ),
          Expanded(
            // Kept by its key as the strip and Check's row come and go
            // around it, or the field in it would lose the keyboard (#568).
            key: const ValueKey<String>('question'),
            child: ListView(
              // Typing past 130 %, the foot's 12 dp go to the prompt too
              // (#561, #574).
              padding: EdgeInsets.fromLTRB(16, 20, 16, typing ? 4 : 16),
              children: <Widget>[
                // Past 130 % text they wrap: in one row the chips and the
                // timer ran 26 dp off the screen at 200 % (#165).
                if (SgScript.large(context))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[?onceMore, ask, ?timer],
                  )
                else
                  Row(
                    children: <Widget>[
                      if (onceMore != null) ...<Widget>[
                        onceMore,
                        const SizedBox(width: 8),
                      ],
                      ask,
                      const Spacer(),
                      ?timer,
                    ],
                  ),
                const SizedBox(height: 10),
                QuizItemView(
                  key: ValueKey<int>(_answers),
                  item: item,
                  field: _field,
                  typing: typing,
                  picked: verdict == null ? null : _given,
                  onAnswer: (given) => unawaited(_submit(given)),
                ),
                if (verdict != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _Feedback(
                    key: _feedback,
                    item: item,
                    verdict: verdict,
                    given: _given,
                    timedOut: _timedOut,
                  ),
                ],
              ],
            ),
          ),
          // A tile or an article button answers by itself; only a typed
          // answer needs *Check*, and it waits for one: only the timer sends
          // an empty answer.
          //
          // #568: typing German past 130 %, *Check* is a key on the umlaut
          // row instead, and its row goes to the prompt.
          if ((typed || verdict != null) && !checkOnKeys)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ListenableBuilder(
                listenable: _field,
                builder: (context, _) => SgButton(
                  label: verdict == null ? l10n.quizCheck : l10n.practiceNext,
                  onPressed: verdict != null
                      ? () => unawaited(_next())
                      : _field.text.trim().isEmpty
                      ? null
                      : () => unawaited(_submit(_field.text)),
                ),
              ),
            ),
          // The umlaut row stays above the keyboard on a German field.
          if (typesGerman(item))
            SgSurface(
              kind: SgSurfaceKind.bar,
              radius: 0,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: !checkOnKeys
                  ? SgUmlautBar(controller: _field, enabled: verdict == null)
                  : Row(
                      children: <Widget>[
                        Expanded(child: SgUmlautBar(controller: _field)),
                        const SizedBox(width: 8),
                        ListenableBuilder(
                          listenable: _field,
                          builder: (context, _) => _CheckKey(
                            onTap: _field.text.trim().isEmpty
                                ? null
                                : () => unawaited(_submit(_field.text)),
                          ),
                        ),
                      ],
                    ),
            )
          else
            const SizedBox(height: 12),
        ],
      );
    }

    final items = run?.quiz.items ?? const <QuizItem>[];
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PracticeHeader(
            title: quizTitle(l10n, widget.args),
            // A re-ask counts among the re-asks: "Once more · 2 / 4".
            place: items.isEmpty
                ? (0, 0)
                : _queue.reasking
                ? _queue.reask
                : (_queue.current.ord, items.length),
            closeLabel: l10n.quizClose,
            onClose: () => unawaited(_close()),
            collapsed: typing,
          ),
          Expanded(child: body),
        ],
      ),
    );
    return PopScope(
      // Back asks, as close does (FR-L8-04).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
          : scaffold,
    );
  }
}

/// How far through the run: one continuous Sun bar, as the artboard draws it
/// — at 30 items, segments would be slivers.
class _QuizStrip extends StatelessWidget {
  const _QuizStrip({required this.done, required this.of});

  final int done;
  final int of;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: ColoredBox(color: tokens.surface.track)),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: of == 0 ? 0 : done / of,
                heightFactor: 1,
                child: ColoredBox(color: tokens.color.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Under an answered item (`quiz.md`): ✓ Correct · ≈ Almost — watch the
/// spelling: *der Mietvertrag* · Article: *die*, not *der* · ✗ and the
/// answer. A German answer can be heard.
class _Feedback extends ConsumerWidget {
  const _Feedback({
    required this.item,
    required this.verdict,
    required this.given,
    required this.timedOut,
    super.key,
  });

  final QuizItem item;
  final Verdict verdict;
  final String given;
  final bool timedOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final answer = item.expected;
    final (message, emphasis) = switch (verdict) {
      Verdict.correct => (l10n.quizCorrect, const <String>[]),
      Verdict.almost => (l10n.quizAlmost(answer), <String>[answer]),
      // Only a right noun under a wrong article gets here, so both carry
      // one.
      Verdict.wrongArticle => _articles(l10n),
      Verdict.wrong when timedOut => (
        l10n.quizTimeUp(answer),
        <String>[answer],
      ),
      Verdict.wrong => (l10n.quizAnswerIs(answer), <String>[answer]),
    };
    final heard = switch (item.direction) {
      QuizDirection.articles => '$answer ${item.prompt}',
      QuizDirection.compare => answer,
      _ when typesGerman(item) => answer,
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SgVerdictRow(
            verdict: SgVerdict.values.byName(verdict.name),
            message: message,
            emphasis: emphasis,
            // German only when it is: an English or Bangla answer in its
            // own voice (#539).
            germanEmphasis: heard != null,
          ),
        ),
        if (heard != null) ...<Widget>[
          const SizedBox(width: 8),
          // Drawn at the artboard's 32, tapped at 48 (accessibility-
          // performance.md): the button itself only takes taps on what it
          // draws, so the ring is this detector's, and one node speaks for
          // both.
          Semantics(
            container: true,
            button: true,
            label: l10n.quizPlay,
            onTap: () => unawaited(say(ref, context, heard)),
            child: ExcludeSemantics(
              child: AdaptiveTooltip(
                message: l10n.quizPlay,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(say(ref, context, heard)),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: SgSpeakerButton(
                        size: 32,
                        state: speakerState(ref, heard),
                        semanticLabel: l10n.quizPlay,
                        onPressed: () => unawaited(say(ref, context, heard)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  (String, List<String>) _articles(AppLocalizations l10n) {
    final wanted = item.expected.split(' ').first;
    final wrote = given.split(RegExp(r'\s+')).first.toLowerCase();
    return (l10n.quizArticleWrong(wanted, wrote), <String>[wanted, wrote]);
  }
}

/// *Check* as a key beside the umlaut keys while typing past 130 % (#568):
/// the primary's fill, a tick, and its name for a screen reader and a
/// tooltip. 48 dp, so the four keys keep theirs.
class _CheckKey extends StatelessWidget {
  const _CheckKey({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final enabled = onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: l10n.quizCheck,
      onTap: onTap,
      child: ExcludeSemantics(
        child: AdaptiveTooltip(
          message: l10n.quizCheck,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled ? tokens.color.primary : tokens.surface.muted,
                borderRadius: BorderRadius.circular(tokens.shape.button),
                // The primary's 2 px ink edge, as the outlined keys beside
                // it have; none under glass, as the glass primary has none.
                border: tokens.isGlass
                    ? null
                    : Border.all(
                        color: enabled
                            ? tokens.color.ink
                            : tokens.surface.outline,
                        width: 2,
                      ),
              ),
              child: SizedBox.square(
                dimension: SgButton.minimumTapTarget,
                child: Icon(
                  Icons.check,
                  color: enabled
                      ? tokens.color.onPrimary
                      : tokens.color.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
