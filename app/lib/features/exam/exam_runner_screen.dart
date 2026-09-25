import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_run_service.dart';
import 'package:deutschplan/domain/exam_generator.dart'
    show ExamSection, WritingTask;
import 'package:deutschplan/features/exam/exam_navigator_sheet.dart';
import 'package:deutschplan/features/exam/exam_question_view.dart';
import 'package:deutschplan/features/learn/step_exams.dart'
    show examMinutes, examSectionName;
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/router/back_behaviour.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// L12 · Exam runner (`exam-runner.md`, `ExamRunner-android.html`, #130):
/// a timed, feedback-free paper that survives being killed. The Cobalt band
/// holds pause, the section and the clock; one question a screen with its
/// flag; *Previous* / *Next*, and *Submit exam* on the last.
///
/// Every answer and flag is written as it is given (FR-L12-01); the clock
/// is written every 10 s (FR-L12-03), so a crash loses at most that.
class ExamRunnerScreen extends ConsumerStatefulWidget {
  const ExamRunnerScreen({
    required this.attemptId,
    required this.results,
    required this.onLeft,
    super.key,
  });

  final int attemptId;

  /// After *Leave* (FR-L12-04), with the attempt's step: back to its exam
  /// hub. The route navigates.
  final ValueChanged<String> onLeft;

  /// What follows the submit: L13 (#135).
  final WidgetBuilder results;

  /// The paper's time, when the timer is on (exam-hub.md's "≈ 20 min").
  static const int limitSeconds = examMinutes * 60;

  /// How often the clock is written (FR-L12-03's "≤ 10 s").
  static const int flushEvery = 10;

  @override
  ConsumerState<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends ConsumerState<ExamRunnerScreen> {
  ExamPaperRun? _paper;
  Object? _error;
  bool _done = false;
  bool _submitting = false;

  int _at = 0;
  final List<String?> _given = <String?>[];
  final List<bool> _flagged = <bool>[];
  final List<List<bool>> _rubrics = <List<bool>>[];
  // ponytail: FR-L12-06's plays live in memory, so a resumed attempt
  // gives each word three again; a column on exam_answers when it matters.
  final Map<int, int> _plays = <int, int>{};
  final TextEditingController _field = TextEditingController();

  bool _timed = true;

  /// The leave dialog is up: its clock is stopped, and seconds count as
  /// paused (FR-L12-03, FR-L12-04's "The timer stops").
  bool _paused = false;
  final GlobalKey<ExamBackGuardState> _guard = GlobalKey<ExamBackGuardState>();
  int _left = ExamRunnerScreen.limitSeconds;
  Timer? _tick;

  /// Seconds counted but not yet written.
  int _runPending = 0;
  int _pausePending = 0;

  /// Held, not read each time: dispose writes through it, when `ref` may
  /// no longer be used.
  late final ExamRunService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(examRunServiceProvider);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    // What the learner typed and the seconds since the last write: the
    // route is going, not the attempt.
    _saveTyped();
    unawaited(_flush());
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final paper = await _service.load(widget.attemptId);
      if (!mounted) return;
      if (paper == null) {
        setState(() => _error = StateError('no attempt'));
        return;
      }
      if (paper.attempt.status == 'finished') {
        setState(() => _done = true);
        return;
      }
      // Left once (FR-L12-04), it is closed: a deep link doesn't reopen it.
      if (paper.attempt.status == 'abandoned') {
        widget.onLeft(paper.attempt.sublevelCode);
        return;
      }
      setState(() {
        _paper = paper;
        _given
          ..clear()
          ..addAll([for (final q in paper.questions) q.given]);
        _flagged
          ..clear()
          ..addAll([for (final q in paper.questions) q.flagged]);
        _rubrics
          ..clear()
          ..addAll([for (final q in paper.questions) q.rubric]);
        _at = paper.resumeAt;
        _field.text = _typedHere ? _given[_at] ?? '' : '';
        _timed = _service.timed;
        _left = math.max(
          0,
          ExamRunnerScreen.limitSeconds - paper.attempt.durationSec,
        );
      });
      if (_timed && _left == 0) {
        await _submit(asked: true);
        return;
      }
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// FR-L12-03: the clock counts only while running; paused seconds are
  /// kept apart; at 0:00 the exam submits itself.
  void _second() {
    if (!mounted || _done) return;
    setState(() {
      if (_paused) {
        _pausePending++;
      } else {
        _runPending++;
        // Held at 0:00 while a submit the learner started is still asking.
        if (_timed && _left > 0) _left--;
      }
    });
    if (_runPending + _pausePending >= ExamRunnerScreen.flushEvery) {
      unawaited(_flush());
    }
    if (_timed && _left <= 0) unawaited(_submit(asked: true));
  }

  Future<void> _flush() async {
    // Writing's text is long to lose: it is written with the clock too
    // (FR-L12W-04). Any other typed answer waits for the learner to move on,
    // or a half-typed "Hau" would count as answered and skip the resume.
    if (_paper?.questions[_at].item is WritingTask) _saveTyped();
    final (running, paused) = (_runPending, _pausePending);
    if (running == 0 && paused == 0) return;
    _runPending = 0;
    _pausePending = 0;
    await _service.recordTime(
      widget.attemptId,
      running: running,
      paused: paused,
    );
  }

  bool get _typedHere {
    final paper = _paper;
    return paper != null && examTyped(paper.questions[_at].item);
  }

  /// FR-L12-01: the current typed answer, written if it changed.
  void _saveTyped() {
    final paper = _paper;
    if (paper == null || !_typedHere || _done) return;
    final typed = _field.text.trim();
    final given = typed.isEmpty ? null : typed;
    if (given == _given[_at]) return;
    _given[_at] = given;
    unawaited(
      _service.answer(widget.attemptId, paper.questions[_at].ord, given),
    );
  }

  /// A choice tapped, or the field submitted: written at once. Nothing
  /// (an ordered sentence taken back to no chips) is unanswered.
  ///
  /// [at] is the question it belongs to (#372): Speaking stopped by moving
  /// on lands after [_at] has moved, and belongs to the task it was said in.
  void _record(String value, {int? at}) {
    final paper = _paper;
    if (paper == null) return;
    final index = at ?? _at;
    if (index == _at && _typedHere) {
      _saveTyped();
      return;
    }
    final given = value.isEmpty ? null : value;
    // Speaking stopped by leaving the exam lands after the runner has gone,
    // and is still written: what was said is kept.
    if (mounted) {
      setState(() => _given[index] = given);
    } else {
      _given[index] = given;
    }
    unawaited(
      _service.answer(widget.attemptId, paper.questions[index].ord, given),
    );
  }

  /// While Speaking records: how to stop it and keep what was said (#372).
  Future<void> Function()? _stopRecording;

  void _go(int to) {
    _saveTyped();
    setState(() {
      _at = to;
      _field.text = _typedHere ? _given[to] ?? '' : '';
    });
  }

  /// #131: the navigator. A tap goes to that question; *Submit exam*
  /// submits, asking first when questions are open.
  Future<void> _openNavigator(List<ExamRunQuestion> questions) async {
    _saveTyped();
    final numbered = <int>[
      for (final (i, q) in questions.indexed)
        if (examNumbered(q.item)) i,
    ];
    final left = _timed ? _clock(_left) : null;
    final pick = await Adaptive.showSheet<NavChoice>(
      context: context,
      builder: (_) => ExamNavigatorSheet(
        cells: <NavCell>[
          for (final i in numbered)
            (answered: _given[i] != null, flagged: _flagged[i]),
        ],
        current: numbered.contains(_at) ? numbered.indexOf(_at) : null,
        left: left,
      ),
    );
    if (pick == null || !mounted) return;
    if (pick.jump case final cell?) {
      _go(numbered[cell]);
    } else {
      await _submit();
    }
  }

  void _toggleFlag() {
    final paper = _paper;
    if (paper == null) return;
    final flagged = !_flagged[_at];
    setState(() => _flagged[_at] = flagged);
    unawaited(
      _service.flag(
        widget.attemptId,
        paper.questions[_at].ord,
        flagged: flagged,
      ),
    );
  }

  /// FR-L12-04 *Leave*: what was typed and the time are written, and the
  /// attempt is abandoned: the hub shows it as an attempt without a score.
  /// Not while a submit is under way: that one finishes, and L13 follows.
  Future<void> _leave() async {
    final paper = _paper;
    if (paper == null || _submitting || _done) return;
    _tick?.cancel();
    _saveTyped();
    try {
      await _flush();
      await _service.abandon(widget.attemptId);
    } on Object {
      // Left anyway: the attempt stays in progress and the hub offers
      // *Resume*, with every answer and all but the last seconds written.
    }
    if (mounted) widget.onLeft(paper.attempt.sublevelCode);
  }

  /// What the submit asks about (#350): the numbered questions with no
  /// answer, counted as the navigator counts them, and the Writing and
  /// Speaking tasks left empty, named apart.
  ({int questions, Set<ExamSection> tasks}) _open(List<ExamRunQuestion> paper) {
    var questions = 0;
    final tasks = <ExamSection>{};
    for (final (i, q) in paper.indexed) {
      if (_given[i] != null) continue;
      if (examNumbered(q.item)) {
        questions++;
      } else {
        tasks.add(q.item.section);
      }
    }
    return (questions: questions, tasks: tasks);
  }

  /// The submit. By hand with questions unanswered, it asks first
  /// (FR-L12-05); the clock running out does not ask.
  Future<void> _submit({bool asked = false}) async {
    final paper = _paper;
    if (paper == null || _submitting || _done) return;
    // #372: one at a time. A second tap, the 0:00 tick or Speaking's Stop
    // while this one stops the recorder or asks is turned away; a submit the
    // learner takes back lets the next one through.
    _submitting = true;
    _saveTyped();
    // #372: a live recording is stopped and saved first, so the confirm
    // counts it and the grading has it. It never throws: a recorder that
    // fails loses the take (ExamSpeaking's `_stop`), not the exam.
    if (_stopRecording case final stop?) {
      await stop();
      if (!mounted) return;
    }
    final open = _open(paper.questions);
    if (!asked && (open.questions > 0 || open.tasks.isNotEmpty)) {
      final l10n = AppLocalizations.of(context);
      final sure = await Adaptive.showConfirm(
        context: context,
        title: l10n.examRunSubmitTitle,
        message: <String>[
          if (open.questions > 0) l10n.examRunSubmitUnanswered(open.questions),
          if (open.tasks.isNotEmpty)
            l10n.examRunSubmitTasksEmpty(
              open.tasks.length > 1 ? 'both' : open.tasks.single.name,
            ),
        ].join(' '),
        confirmLabel: l10n.examRunSubmitConfirm,
        cancelLabel: l10n.examRunKeepAnswering,
      );
      if (!mounted) return;
      if (sure != true) {
        _submitting = false;
        return;
      }
    }
    _tick?.cancel();
    try {
      await _flush();
      await _service.submit(widget.attemptId);
    } on Object {
      // The answers are written already: stay on the paper, clock running,
      // and let the learner submit again.
      _submitting = false;
      if (!mounted) return;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
      DpToast.show(context, AppLocalizations.of(context).examRunSubmitFailed);
      return;
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.results(context);
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final paper = _paper;

    final Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpText(
            l10n.examRunLoadFailed,
            role: DpTextRole.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (paper == null) {
      body = const SizedBox.expand();
    } else {
      final questions = paper.questions;
      // The question this view is for, kept in its callbacks (#372).
      final at = _at;
      final item = questions[at].item;
      final inSection = [
        for (final q in questions)
          if (q.item.section == item.section) q,
      ];
      final last = _at == questions.length - 1;
      final count = questions.where((q) => examNumbered(q.item)).length;
      final number = questions.take(_at + 1).where((q) => examNumbered(q.item));
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Band(
            title: l10n.examRunSection(
              examSectionName(l10n, item.section),
              inSection.indexWhere((q) => q.ord == questions[_at].ord) + 1,
              inSection.length,
            ),
            left: _timed ? _left : null,
            onPause: () => unawaited(_guard.currentState?.ask()),
            onNavigator: () => unawaited(_openNavigator(questions)),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: DpText(
                    examNumbered(item)
                        ? l10n.examRunQuestion(number.length, count)
                        : '',
                    role: DpTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
                ),
                Semantics(
                  button: true,
                  toggled: _flagged[_at],
                  label: _flagged[_at] ? l10n.examRunFlagged : l10n.examRunFlag,
                  onTap: _toggleFlag,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleFlag,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(
                        _flagged[_at] ? Icons.flag : Icons.outlined_flag,
                        color: _flagged[_at]
                            ? tokens.color.learning
                            : tokens.color.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: <Widget>[
                ExamQuestionView(
                  key: ValueKey<int>(questions[_at].ord),
                  item: item,
                  given: _given[_at],
                  field: _field,
                  onGiven: (value) => _record(value, at: at),
                  onRecording: (stop) => _stopRecording = stop,
                  rubric: _rubrics[_at],
                  onRubric: (ticks) {
                    _rubrics[_at] = ticks;
                    unawaited(
                      _service.rubric(
                        widget.attemptId,
                        questions[_at].ord,
                        ticks,
                      ),
                    );
                  },
                  recordingPath: () => _service.recordingPath(widget.attemptId),
                  onDiscard: _service.discard,
                  plays: _plays[questions[_at].ord] ?? 0,
                  onPlay: () => setState(
                    () => _plays.update(
                      questions[_at].ord,
                      (n) => n + 1,
                      ifAbsent: () => 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: DpButton(
                    label: l10n.examRunPrevious,
                    kind: DpButtonKind.secondary,
                    onPressed: _at == 0 ? null : () => _go(_at - 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DpButton(
                    label: last
                        ? l10n.examRunSubmit
                        : item is WritingTask
                        ? l10n.examWritingSubmit
                        : l10n.examRunNext,
                    onPressed: last
                        ? () => unawaited(_submit())
                        : () => _go(_at + 1),
                  ),
                ),
              ],
            ),
          ),
          if (examTypesGerman(item))
            DpSurface(
              kind: DpSurfaceKind.bar,
              radius: 0,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: DpUmlautBar(controller: _field),
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
    final screen = tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.der, child: scaffold)
        : scaffold;
    // FR-L12-04: back and the band's pause both ask before leaving. Nothing
    // to lose while the paper loads or fails, so no guard then.
    return paper == null
        ? screen
        : ExamBackGuard(
            key: _guard,
            mock: paper.attempt.seed,
            onAsk: () => setState(() => _paused = true),
            onStay: () {
              if (mounted) setState(() => _paused = false);
            },
            onLeave: () => unawaited(_leave()),
            child: screen,
          );
  }
}

/// "14:32".
String _clock(int seconds) =>
    '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';

/// The Cobalt band: pause (which asks to leave, as the artboard wires it),
/// the section, the clock — Coral in the last two minutes — and the
/// navigator.
class _Band extends StatelessWidget {
  const _Band({
    required this.title,
    required this.left,
    required this.onPause,
    required this.onNavigator,
  });

  final String title;

  /// Seconds left; null when the timer is off.
  final int? left;
  final VoidCallback onPause;

  /// Opens the navigator (#131).
  final VoidCallback onNavigator;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onDer;
    final seconds = left;
    // FR-L12-03 / exam-hub.md: Coral in the last 2 minutes.
    final coral = seconds != null && seconds <= 120;
    final content = Column(
      children: <Widget>[
        SizedBox(height: MediaQuery.paddingOf(context).top),
        SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: l10n.examRunPause,
                onTap: onPause,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPause,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.pause, color: ink),
                  ),
                ),
              ),
              Expanded(
                child: DpText(
                  title,
                  role: DpTextRole.body,
                  weight: 600,
                  color: ink,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              if (seconds != null)
                Semantics(
                  label: l10n.examRunTimeLeft(seconds ~/ 60, seconds % 60),
                  excludeSemantics: true,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: coral
                          ? tokens.color.again
                          : ink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DpText(
                      AppLocalizations.of(context).digits(_clock(seconds)),
                      role: DpTextRole.body,
                      weight: 700,
                      color: coral ? tokens.color.ink : ink,
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: l10n.examNavOpen,
                onTap: onNavigator,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onNavigator,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.grid_view_outlined, color: ink),
                  ),
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
            kind: DpSurfaceKind.tint(tokens.color.der),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.der, child: content);
  }
}
