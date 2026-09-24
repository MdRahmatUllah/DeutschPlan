import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/quiz_run_service.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/learn/grammar_practice_screen.dart'
    show PracticeHeader;
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/quiz/quiz_item_view.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// L8's title: "Standard · DE → EN", or "Forms".
String quizTitle(AppLocalizations l10n, QuizArgs args) =>
    args.direction == QuizDirection.forms.name
    ? l10n.quizForms
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
  int _index = 0;

  /// The current item's verdict once answered; null before.
  Verdict? _verdict;
  String _given = '';
  bool _timedOut = false;
  double _points = 0;

  /// Bumped per item, so the field and its controller start empty.
  int _answers = 0;
  final TextEditingController _field = TextEditingController();

  Timer? _tick;
  int _left = QuizScreen.questionSeconds;

  /// Set once the run is being left, so no second tap races the exit.
  bool _leaving = false;

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
      setState(() => _run = run);
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
    if (run == null || _verdict != null) return;
    if (!timedOut && given.trim().isEmpty) return;
    _tick?.cancel();
    final item = run.quiz.items[_index];
    final verdict = timedOut ? Verdict.wrong : grade(item, given);
    setState(() {
      _verdict = verdict;
      _given = given.trim();
      _timedOut = timedOut;
      _points += verdict.score;
    });
    await _service.answer(run, item, given: given.trim(), verdict: verdict);
  }

  /// *Next*: the next item, or the run finished and closed.
  Future<void> _next() async {
    final run = _run;
    if (run == null || _verdict == null || _leaving) return;
    if (_index < run.quiz.items.length - 1) {
      setState(() {
        _index++;
        _verdict = null;
        _timedOut = false;
        _answers++;
        _field.clear();
      });
      _startClock();
      return;
    }
    _leaving = true;
    await _service.finish(run, points: _points);
    // ponytail: L9 (#126) takes over from here; until then the run closes.
    if (mounted) Navigator.of(context).pop();
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
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final run = _run;

    final Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
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
          child: DpText(
            l10n.quizEmpty,
            role: DpTextRole.body,
            textAlign: TextAlign.center,
            color: tokens.color.textSecondary,
          ),
        ),
      );
    } else {
      final items = run.quiz.items;
      final item = items[_index];
      final verdict = _verdict;
      final typed = item.direction != QuizDirection.articles && !item.tiles;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _QuizStrip(done: _index + 1, of: items.length),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    DpChip(label: askName(l10n, item), kind: DpChipKind.status),
                    const Spacer(),
                    if (widget.args.timer && verdict == null)
                      DpPill(
                        label: l10n.quizSecondsLeft(_left),
                        fill: _left <= 5
                            ? tokens.color.again
                            : tokens.surface.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                QuizItemView(
                  key: ValueKey<int>(_answers),
                  item: item,
                  field: _field,
                  picked: verdict == null ? null : _given,
                  onAnswer: (given) => unawaited(_submit(given)),
                ),
                if (verdict != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _Feedback(
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
          if (typed || verdict != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ListenableBuilder(
                listenable: _field,
                builder: (context, _) => DpButton(
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
            DpSurface(
              kind: DpSurfaceKind.bar,
              radius: 0,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: DpUmlautBar(controller: _field, enabled: verdict == null),
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
            place: (items.isEmpty ? 0 : _index + 1, items.length),
            closeLabel: l10n.quizClose,
            onClose: () => unawaited(_close()),
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
              Positioned.fill(child: ColoredBox(color: tokens.surface.muted)),
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
      _ when typesGerman(item) => answer,
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: DpVerdictRow(
            verdict: DpVerdict.values.byName(verdict.name),
            message: message,
            emphasis: emphasis,
          ),
        ),
        if (heard != null) ...<Widget>[
          const SizedBox(width: 8),
          DpSpeakerButton(
            size: 32,
            state: speakerState(ref),
            semanticLabel: l10n.quizPlay,
            onPressed: () => unawaited(say(ref, context, heard)),
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
