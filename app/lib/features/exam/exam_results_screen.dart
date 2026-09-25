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
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_question_view.dart'
    show ExamRubricTick, examRubricLines;
import 'package:deutschplan/features/learn/step_exams.dart'
    show examSectionName;
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'exam_results_screen.g.dart';

/// L13's result, read back after the submit and after each rubric tick.
@riverpod
Future<ExamResult?> examResult(Ref ref, int attemptId) =>
    ref.watch(examResultServiceProvider).result(attemptId);

/// L13 · Exam results (`exam-results.md`, `ExamResults-android.html`, #135),
/// shown by L12 in place of the paper it submitted: "Bestanden!" on Lime or
/// "Noch nicht" on Coral, the score, the pass mark on a bar, the step, mock,
/// time and the comparison with the previous finished attempt (FR-L13-01),
/// the sections, and *Review answers* · *Add missed words to revision*
/// (FR-L13-02) · *Try another mock* · *Back to step*. Writing and Speaking
/// open their rubric, and a tick grades the paper again (FR-L13-03).
class ExamResultsScreen extends ConsumerStatefulWidget {
  const ExamResultsScreen({
    required this.attemptId,
    required this.onHub,
    required this.onStep,
    required this.review,
    super.key,
  });

  final int attemptId;

  /// Close and *Try another mock*, with the attempt's step: its exam hub
  /// (L10). The route navigates.
  final ValueChanged<String> onHub;

  /// *Back to step*: the step's detail (L2).
  final ValueChanged<String> onStep;

  /// *Review answers*: L14 (#136), in this screen's place.
  final WidgetBuilder review;

  @override
  ConsumerState<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends ConsumerState<ExamResultsScreen> {
  bool _reviewing = false;

  /// *Add missed words to revision* is done once.
  bool _added = false;

  // ponytail: "once" is this visit's; L13 opened again offers it again,
  // and a second go rates the words Again once more. A column on the
  // attempt if that matters.
  Future<void> _addToRevision(List<String> uids) async {
    setState(() => _added = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(examResultServiceProvider)
          .addToRevision(uids, today: ref.read(todayProvider));
    } on Object {
      if (!mounted) return;
      setState(() => _added = false);
      DpToast.show(context, l10n.examResultAddFailed);
      return;
    }
    if (!mounted) return;
    DpToast.show(context, l10n.examResultAdded(uids.length));
  }

  /// FR-L13-03: a task's rubric, ticked here; each tick grades again.
  Future<void> _rubric(ExamResultRow task) async {
    final l10n = AppLocalizations.of(context);
    await Adaptive.showSheet<void>(
      context: context,
      builder: (_) => _RubricSheet(
        title: examSectionName(l10n, task.item.section),
        lines: examRubricLines(l10n, task.item.section),
        ticks: task.rubric,
        // #84 counts the ticks only with a text or a recording.
        empty: switch (task.given) {
          final given? => given.trim().isEmpty,
          null => true,
        },
        speaking: task.item is SpeakingTask,
        onChanged: (ticks) async {
          await ref
              .read(examResultServiceProvider)
              .rubric(widget.attemptId, task.ord, ticks);
          ref.invalidate(examResultProvider(widget.attemptId));
        },
        onDelete: () async {
          await ref
              .read(examResultServiceProvider)
              .deleteRecording(widget.attemptId, task.ord, task.given!);
          ref.invalidate(examResultProvider(widget.attemptId));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_reviewing) return widget.review(context);
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final loaded = ref.watch(examResultProvider(widget.attemptId));

    final Widget content;
    if (loaded.hasError || (loaded.hasValue && loaded.value == null)) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DpText(
            l10n.examRunLoadFailed,
            role: DpTextRole.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (loaded.value case final result?) {
      content = _Result(
        result: result,
        added: _added,
        onClose: () => widget.onHub(result.attempt.sublevelCode),
        onReview: () => setState(() => _reviewing = true),
        onAdd: (uids) => unawaited(_addToRevision(uids)),
        onRubric: (task) => unawaited(_rubric(task)),
        onHub: () => widget.onHub(result.attempt.sublevelCode),
        onStep: () => widget.onStep(result.attempt.sublevelCode),
      );
    } else {
      content = const SizedBox.expand();
    }

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: content,
    );
    // Back, the system's or the iOS swipe, is the close button: the exam
    // hub, never L11 under the route (navigation.md: no swipe-dismiss).
    final step = loaded.value?.attempt.sublevelCode;
    final guarded = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && step != null) widget.onHub(step);
      },
      child: scaffold,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.easy, child: guarded)
        : guarded;
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.result,
    required this.added,
    required this.onClose,
    required this.onReview,
    required this.onAdd,
    required this.onRubric,
    required this.onHub,
    required this.onStep,
  });

  final ExamResult result;
  final bool added;
  final VoidCallback onClose;
  final VoidCallback onReview;
  final ValueChanged<List<String>> onAdd;
  final ValueChanged<ExamResultRow> onRubric;
  final VoidCallback onHub;
  final VoidCallback onStep;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final attempt = result.attempt;
    final share = attempt.maxPoints == 0
        ? 0.0
        : attempt.scorePoints / attempt.maxPoints;
    final missed = result.missed;

    // The sections in BR-EXAM-03's order, each with its points and maximum.
    final sections = <ExamSection, ({double points, int max})>{};
    final tasks = <ExamSection, ExamResultRow>{};
    for (final row in result.rows) {
      final section = row.item.section;
      final so = sections[section] ?? (points: 0.0, max: 0);
      sections[section] = (
        points: so.points + row.points,
        max: so.max + section.points,
      );
      if (row.item is WritingTask || row.item is SpeakingTask) {
        tasks[section] = row;
      }
    }

    final previous = result.previous;
    final line = <String>[
      l10n.examResultLine(
        attempt.sublevelCode,
        attempt.seed,
        _clock(attempt.durationSec),
      ),
      if (previous != null)
        l10n.examResultCompare(
          _signed(attempt.scorePoints - previous.attempt.scorePoints),
          previous.number,
          _percent(previous.attempt.scorePoints, previous.attempt.maxPoints),
        ),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              _Hero(
                passed: attempt.passed != 0,
                share: share,
                percent: _percent(attempt.scorePoints, attempt.maxPoints),
                points: l10n.examResultPoints(
                  _points(attempt.scorePoints),
                  _points(attempt.maxPoints),
                ),
                passPercent: result.passPercent,
                line: line,
                onClose: onClose,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: DpText(
                  l10n.examResultBySection.toUpperCase(),
                  role: DpTextRole.caption,
                  weight: 700,
                  letterSpacing: 0.6,
                  color: tokens.color.textSecondary,
                ),
              ),
              for (final section in ExamSection.values)
                if (sections[section] case final score?)
                  _SectionRow(
                    name: examSectionName(l10n, section),
                    points: score.points,
                    max: score.max,
                    task: tasks[section],
                    onRubric: onRubric,
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DpButton(label: l10n.examResultReview, onPressed: onReview),
              const SizedBox(height: 8),
              DpButton(
                label: l10n.examResultAddMissed(missed.length),
                kind: DpButtonKind.secondary,
                onPressed: missed.isEmpty || added ? null : () => onAdd(missed),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DpButton(
                      label: l10n.examResultAnotherMock,
                      kind: DpButtonKind.text,
                      onPressed: onHub,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DpButton(
                      label: l10n.examResultBackToStep,
                      kind: DpButtonKind.text,
                      onPressed: onStep,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "77", down and never up: 59.9 % is not the 60 % that passes.
int _percent(double points, double max) =>
    max == 0 ? 0 : (points / max * 100).floor();

/// "37", or "36.5": Writing's rubric counts in halves.
String _points(double points) => points == points.roundToDouble()
    ? '${points.round()}'
    : points.toStringAsFixed(1);

/// "+15", "−2.5", "±0".
String _signed(double delta) => delta > 0
    ? '+${_points(delta)}'
    : delta < 0
    ? '−${_points(-delta)}'
    : '±0';

/// "18:41", the time the paper ran.
String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The block on the result's colour: close, the badge, the score, the pass
/// mark on its bar, and the line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.passed,
    required this.share,
    required this.percent,
    required this.points,
    required this.passPercent,
    required this.line,
    required this.onClose,
  });

  final bool passed;
  final double share;
  final int percent;
  final String points;
  final int passPercent;
  final String line;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final colour = passed ? tokens.color.easy : tokens.color.again;
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        16,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Semantics(
              container: true,
              button: true,
              label: l10n.examResultClose,
              onTap: onClose,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                // The artboards: a back arrow on Android, a cross on iOS.
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    context.isCupertino ? Icons.close : Icons.arrow_back,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _Badge(passed: passed),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              DpText(
                l10n.examResultPercent(percent),
                role: DpTextRole.display,
                weight: 700,
                color: ink,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: DpText(
                  points,
                  role: DpTextRole.body,
                  weight: 600,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PassBar(share: share, passPercent: passPercent, ink: ink),
          const SizedBox(height: 8),
          DpText(line, role: DpTextRole.label, weight: 600, color: ink),
        ],
      ),
    );
    return tokens.isGlass
        ? DpSurface(kind: DpSurfaceKind.tint(colour), radius: 0, child: content)
        : ColoredBox(color: colour, child: content);
  }
}

/// "Bestanden!" with its tick, or "Noch nicht": scales in with one glow
/// pulse, and stands still when motion is reduced.
class _Badge extends StatefulWidget {
  const _Badge({required this.passed});

  final bool passed;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = context.tokens.motion.celebrate;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else if (_motion.isDismissed) {
      unawaited(_motion.forward());
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final label = widget.passed ? l10n.examResultPassed : l10n.examResultFailed;
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final t = _motion.value;
        // In over the first third, then one pulse of the halo, settling at
        // the artboard's 6 px.
        final scale = Curves.easeOutBack.transform(math.min(1, t * 3));
        final pulse = t < 1 / 3 ? 0.0 : math.sin(math.pi * (t - 1 / 3) * 1.5);
        final halo = 6.0 + 6.0 * math.max(0.0, pulse);
        return Transform.scale(
          scale: 0.6 + 0.4 * scale,
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.isGlass ? 20 : 16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.surface.card.withValues(alpha: 0.45),
                  spreadRadius: halo,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Semantics(
        container: true,
        header: true,
        child: Container(
          // 32 dp at 100 % text (22 + 2 × 5), taller as the text grows.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: tokens.surface.card,
            borderRadius: BorderRadius.circular(tokens.isGlass ? 20 : 16),
            border: Border.all(color: tokens.color.ink, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.passed ? Icons.check : Icons.close,
                size: 16,
                color: tokens.color.ink,
              ),
              const SizedBox(width: 6),
              DpText(
                label,
                role: DpTextRole.body,
                weight: 700,
                color: tokens.color.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The score as a bar, with the pass mark's tick and "pass 60%" under it.
class _PassBar extends StatelessWidget {
  const _PassBar({
    required this.share,
    required this.passPercent,
    required this.ink,
  });

  final double share;
  final int passPercent;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final mark = passPercent.clamp(0, 100) / 100;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final bar = SizedBox(
          height: 26,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Container(
                  height: 14,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: tokens.surface.card.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: ink, width: 1.5),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share.clamp(0, 1),
                    child: ColoredBox(color: ink),
                  ),
                ),
              ),
              Positioned(
                left: width * mark - 1,
                top: 1,
                child: Container(width: 2, height: 24, color: ink),
              ),
            ],
          ),
        );
        // Under the tick, kept inside the bar's width at either end, and in
        // the flow so a large text pushes the line down rather than over it.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            bar,
            Align(
              alignment: Alignment(mark * 2 - 1, 0),
              child: DpText(
                l10n.examResultPassMark(passPercent),
                role: DpTextRole.caption,
                weight: 700,
                color: ink,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Vocabulary ▬▬▬ 8 / 10", and for a task "self-assessed", which opens its
/// rubric.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.name,
    required this.points,
    required this.max,
    required this.task,
    required this.onRubric,
  });

  final String name;
  final double points;
  final int max;
  final ExamResultRow? task;
  final ValueChanged<ExamResultRow> onRubric;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final task = this.task;
    final score = l10n.examResultSectionPoints(_points(points), max);
    final bar = Container(
      height: 8,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: max == 0 ? 0 : (points / max).clamp(0, 1),
        child: ColoredBox(color: tokens.color.easy),
      ),
    );
    final scoreText = DpText(score, role: DpTextRole.label, weight: 700);
    final note = task == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: DpText(
                  l10n.examResultSelfAssessed,
                  role: DpTextRole.caption,
                  color: tokens.color.link,
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: tokens.color.link),
            ],
          );
    // The artboard's columns at ordinary sizes; past 130 % text the name and
    // score on a line, the bar and the note under them, so nothing clips.
    final big = MediaQuery.textScalerOf(context).scale(10) > 13;
    final row = ConstrainedBox(
      // accessibility-performance.md: 48 dp on Android, 44 pt on iOS, for
      // the rows that open a rubric.
      constraints: BoxConstraints(
        minHeight: task == null ? 26 : (context.isCupertino ? 44 : 48),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: big ? 6 : 0),
        child: big
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DpText(
                          name,
                          role: DpTextRole.label,
                          weight: 400,
                        ),
                      ),
                      const SizedBox(width: 10),
                      scoreText,
                    ],
                  ),
                  const SizedBox(height: 4),
                  bar,
                  ?note,
                ],
              )
            : Row(
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: DpText(name, role: DpTextRole.label, weight: 400),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: bar),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: scoreText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 100, child: note),
                ],
              ),
      ),
    );
    if (task == null) {
      return Semantics(
        container: true,
        label: l10n.examResultSectionLabel(name, score),
        excludeSemantics: true,
        child: row,
      );
    }
    return Semantics(
      container: true,
      button: true,
      label: l10n.examResultTaskLabel(name, score),
      hint: l10n.examResultRubricHint,
      excludeSemantics: true,
      onTap: () => onRubric(task),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onRubric(task),
        child: row,
      ),
    );
  }
}

/// A task's rubric: its ticks, each written and graded as it is ticked.
class _RubricSheet extends StatefulWidget {
  const _RubricSheet({
    required this.title,
    required this.lines,
    required this.ticks,
    required this.empty,
    required this.speaking,
    required this.onChanged,
    required this.onDelete,
  });

  final String title;
  final List<String> lines;
  final List<bool> ticks;

  /// No text, or no recording: the ticks would count nothing (#84).
  final bool empty;
  final bool speaking;
  final Future<void> Function(List<bool> ticks) onChanged;

  /// FR-L12S-04 from L13: *Delete recording*.
  final Future<void> Function() onDelete;

  @override
  State<_RubricSheet> createState() => _RubricSheetState();
}

class _RubricSheetState extends State<_RubricSheet> {
  /// Asked first: deleting zeros Speaking.
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final sure = await Adaptive.showConfirm(
      context: context,
      title: l10n.examResultDeleteTitle,
      message: l10n.examResultDeleteMessage,
      confirmLabel: l10n.examSpeakingDelete,
      cancelLabel: l10n.examResultDeleteKeep,
      destructive: true,
    );
    if (sure != true || !mounted) return;
    await widget.onDelete();
    if (mounted) Navigator.of(context).pop();
  }

  late final List<bool> _ticks = <bool>[
    for (var i = 0; i < widget.lines.length; i++)
      i < widget.ticks.length && widget.ticks[i],
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DpText(widget.title, role: DpTextRole.title),
            const SizedBox(height: 4),
            DpText(
              widget.empty
                  ? (widget.speaking
                        ? l10n.examResultRubricNoRecording
                        : l10n.examResultRubricNoText)
                  : l10n.examResultRubricIntro,
              role: DpTextRole.label,
            ),
            const SizedBox(height: 8),
            for (final (i, line) in widget.lines.indexed)
              ExamRubricTick(
                label: line,
                ticked: _ticks[i],
                onTap: widget.empty
                    ? null
                    : () {
                        setState(() => _ticks[i] = !_ticks[i]);
                        unawaited(widget.onChanged(List<bool>.of(_ticks)));
                      },
              ),
            if (widget.speaking && !widget.empty) ...<Widget>[
              const SizedBox(height: 8),
              DpButton(
                label: l10n.examSpeakingDelete,
                kind: DpButtonKind.text,
                onPressed: () => unawaited(_delete()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
