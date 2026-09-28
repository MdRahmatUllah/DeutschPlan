import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/features/exam/exam_question_view.dart'
    show ExamRubricTick, examClock, examRubricLines, examTaskPanel;
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/services/exam_recorder.dart';

/// "00:52": [examClock] with its minutes in two digits, as the artboard
/// draws the recorder's time.
String _mmss(int seconds) => examClock(seconds).padLeft(5, '0');

enum _Mic { idle, recording, recorded, denied }

/// L12's Speaking (`exam-writing-speaking.md`, the ExamSpeaking artboard):
/// the task, the recorder — record, stop, play back, one retake, delete —
/// and the four rubric ticks the learner gives on listening back.
///
/// The recording is the row's `given` (#84 scores nothing without one); the
/// ticks are its `self_rubric_json` (FR-L12S-03).
class ExamSpeaking extends ConsumerStatefulWidget {
  const ExamSpeaking({
    required this.task,
    required this.given,
    required this.rubric,
    required this.onGiven,
    required this.onRubric,
    required this.recordingPath,
    required this.onDiscard,
    required this.onRecording,
    required this.takes,
    required this.onTake,
    super.key,
  });

  final SpeakingTask task;

  /// The recording's path, or null before there is one.
  final String? given;
  final List<bool> rubric;

  /// The recording's path once made; '' once deleted.
  final ValueChanged<String> onGiven;
  final ValueChanged<List<bool>> onRubric;
  final Future<String> Function() recordingPath;
  final Future<bool> Function(String path) onDiscard;

  /// Told how to stop and keep a recording while one runs, and null after.
  final ValueChanged<Future<void> Function()?> onRecording;

  /// FR-L12S-02: the takes made, the first included, and one begun. The
  /// runner counts them per task: this view is built again on every visit,
  /// and a count kept here offered the retake again after *Next* and
  /// *Previous* (#731). Takes, not a Record after a recording: after
  /// *Delete recording* the next take is the retake too (#691 EX-6).
  final int takes;
  final VoidCallback onTake;

  /// FR-L12S-02: one retake.
  static const int retakes = 1;

  /// The rubric's four ticks, in `self_rubric_json`'s order.
  static const int ticks = 4;

  @override
  ConsumerState<ExamSpeaking> createState() => _ExamSpeakingState();
}

class _ExamSpeakingState extends ConsumerState<ExamSpeaking> {
  /// Held for as long as the task is on screen: the provider auto-disposes,
  /// and a read alone would let it go at once.
  late final ProviderSubscription<ExamRecorder> _held;
  ExamRecorder get _recorder => _held.read();
  late _Mic _mic = widget.given == null ? _Mic.idle : _Mic.recorded;
  late List<bool> _ticks = _padded(widget.rubric);

  static List<bool> _padded(List<bool> rubric) => <bool>[
    for (var i = 0; i < ExamSpeaking.ticks; i++) i < rubric.length && rubric[i],
  ];

  /// While recording, the seconds so far; once recorded, its length.
  int _seconds = 0;

  /// A call, an alarm or a voice assistant has the microphone (#624): the
  /// recording waits, and so does its clock.
  bool _interrupted = false;
  StreamSubscription<bool>? _interruptions;

  /// The levels heard while recording, for the bars.
  final List<double> _levels = <double>[];
  String? _path;
  bool _playing = false;

  /// Between the tap on *Record* and the recorder running: a second tap in
  /// that time would start it twice and leave the first clock ticking.
  bool _starting = false;
  Timer? _tick;
  StreamSubscription<double>? _heard;

  @override
  void initState() {
    super.initState();
    _held = ref.listenManual(examRecorderProvider, (_, _) {});
    _path = widget.given;
    if (_path case final path?) {
      unawaited(
        _recorder.length(path).then((length) {
          if (mounted && length != null) {
            setState(() => _seconds = length.inSeconds);
          }
        }),
      );
    }
  }

  /// A tick the runner could not write is taken back there (#730), and
  /// shown so here.
  @override
  void didUpdateWidget(ExamSpeaking old) {
    super.didUpdateWidget(old);
    if (!identical(widget.rubric, old.rubric)) _ticks = _padded(widget.rubric);
  }

  @override
  void dispose() {
    // Leaving mid-recording keeps what was said.
    if (_mic == _Mic.recording) unawaited(_finish(mounted: false));
    _tick?.cancel();
    unawaited(_heard?.cancel());
    unawaited(_interruptions?.cancel());
    unawaited(_recorder.stopPlaying());
    _held.close();
    super.dispose();
  }

  // Each takes the recorder before its first await: dispose closes the
  // subscription, and a recording left mid-way still has to be stopped.

  /// The takes left: the first, and [ExamSpeaking.retakes] more.
  int get _takesLeft => 1 + ExamSpeaking.retakes - widget.takes;

  Future<void> _record() async {
    if (_starting || _mic == _Mic.recording) return;
    _starting = true;
    try {
      await _begin();
    } finally {
      _starting = false;
    }
  }

  Future<void> _begin() async {
    final recorder = _recorder;
    // FR-L12S-01: asked on first use, after the line that says why.
    if (!await recorder.permission()) {
      if (mounted) setState(() => _mic = _Mic.denied);
      return;
    }
    // #691 EX-8: the phone's dialog can outlast the task, as 0:00 submits
    // the paper under it. Gone, it records nothing: a take would be written
    // into an attempt already graded.
    if (!mounted) return;
    await recorder.stopPlaying();
    final path = await widget.recordingPath();
    // Heard from before `start`, so a call that takes the microphone while
    // the recorder starts still holds the time (#892).
    _interrupted = false;
    _interruptions = recorder.interrupted.listen((interrupted) {
      if (mounted) setState(() => _interrupted = interrupted);
    });
    try {
      await recorder.start(path);
    } on Object {
      unawaited(_interruptions?.cancel());
      _interruptions = null;
      rethrow;
    }
    widget.onTake();
    if (!mounted) {
      // The task left the screen while the recorder started: stop it, and
      // keep what little it has, as leaving mid-recording does.
      unawaited(_interruptions?.cancel());
      await recorder.stop();
      widget.onGiven(path);
      return;
    }
    setState(() {
      _path = path;
      _mic = _Mic.recording;
      _seconds = 0;
      _levels.clear();
    });
    _heard = recorder.levels.listen((level) {
      if (mounted) setState(() => _levels.add(level));
    });
    _finishing = null;
    widget.onRecording(_finish);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      // #624: the time is what was recorded, so it holds while the phone
      // has the microphone.
      if (!mounted || _interrupted) return;
      setState(() => _seconds++);
      // FR-L12S-02: the level's length, then it stops by itself.
      if (_seconds >= widget.task.seconds) unawaited(_finish());
    });
  }

  /// The recording's stop, once it is asked for (#372): Stop, the level's
  /// end, the runner's Submit and the 0:00 tick can meet, and it stops once.
  Future<void>? _finishing;

  Future<void> _finish({bool mounted = true}) =>
      _finishing ??= _stop(mounted: mounted);

  Future<void> _stop({required bool mounted}) async {
    final recorder = _recorder;
    _tick?.cancel();
    _tick = null;
    // Not awaited: a broadcast stream's cancel can wait for its controller,
    // and the recording must stop now.
    unawaited(_heard?.cancel());
    _heard = null;
    unawaited(_interruptions?.cancel());
    _interruptions = null;
    _interrupted = false;
    try {
      await recorder.stop();
    } on Object {
      // A recorder that can't stop has kept nothing to hand in (#372): the
      // take is lost, the task keeps what it had, and a submit goes on.
      _path = widget.given;
      if (mounted && this.mounted) {
        setState(() => _mic = _path == null ? _Mic.idle : _Mic.recorded);
      }
      return;
    } finally {
      widget.onRecording(null);
    }
    final path = _path;
    if (path != null) widget.onGiven(path);
    if (mounted && this.mounted) setState(() => _mic = _Mic.recorded);
  }

  Future<void> _play() async {
    final recorder = _recorder;
    final path = _path;
    if (path == null) return;
    if (_playing) {
      await recorder.stopPlaying();
      return;
    }
    setState(() => _playing = true);
    try {
      await recorder.play(path);
    } on Object catch (error) {
      // A take the phone can't read (half-written when the app was killed,
      // or restored from another phone) says so, and Play comes back (#732).
      debugPrint('play: $error');
      if (mounted) {
        SgToast.show(
          context,
          AppLocalizations.of(context).examSpeakingPlayFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  /// FR-L12S-04: the file gone and the section zero. Its ticks go with it:
  /// kept, they scored the next take before it was heard (#731).
  Future<void> _delete() async {
    final recorder = _recorder;
    final path = _path;
    await recorder.stopPlaying();
    // The empty answer first, and the file once that is written (#891): a
    // write that fails, its sheet closed, keeps the take and its answer,
    // rather than an answer pointing at a file already gone.
    if (path == null) {
      widget.onGiven('');
    } else if (!await widget.onDiscard(path)) {
      return;
    }
    if (_ticks.contains(true)) {
      _ticks = _padded(const <bool>[]);
      widget.onRubric(_ticks);
    }
    if (!mounted) return;
    setState(() {
      _mic = _Mic.idle;
      _path = null;
      _seconds = 0;
      _levels.clear();
      _playing = false;
    });
  }

  void _toggle(int i) {
    setState(() => _ticks = <bool>[..._ticks]..[i] = !_ticks[i]);
    widget.onRubric(_ticks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final task = widget.task;
    final topic = task.category ?? l10n.examWritingTopicFallback;
    final max = task.seconds;
    final retake = SgButton(
      label: l10n.examSpeakingRetake(_takesLeft),
      kind: SgButtonKind.secondary,
      compact: true,
      onPressed: _takesLeft > 0 ? () => unawaited(_record()) : null,
    );
    final delete = SgButton(
      label: l10n.examSpeakingDelete,
      kind: SgButtonKind.secondary,
      colour: tokens.surface.cardStrong,
      onColour: tokens.color.ink,
      compact: true,
      onPressed: () => unawaited(_delete()),
    );

    final (
      IconData icon,
      String label,
      Color fill,
      VoidCallback? onTap,
    ) = switch (_mic) {
      _Mic.idle || _Mic.denied => (
        Icons.mic,
        l10n.examSpeakingRecord,
        tokens.color.again,
        // #691 EX-6: the take and the retake used, deleted or not.
        _takesLeft > 0 ? () => unawaited(_record()) : null,
      ),
      _Mic.recording => (
        Icons.stop,
        l10n.examSpeakingStop,
        tokens.color.again,
        () => unawaited(_finish()),
      ),
      _Mic.recorded => (
        _playing ? Icons.stop : Icons.play_arrow,
        _playing ? l10n.examSpeakingStopPlaying : l10n.examSpeakingPlay,
        tokens.color.primary,
        () => unawaited(_play()),
      ),
    };

    // Each card a node of its own: merged, the task, the recorder and the
    // rubric would be read as one.
    Widget node(Widget child) => Semantics(container: true, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        node(
          examTaskPanel(
            tokens,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgText(
                  l10n.examSpeakingPrompt(
                    l10n.examSpeakingTask(task.level, topic),
                    max % 60 == 0
                        ? l10n.examSpeakingMinutes(max ~/ 60)
                        : l10n.examSpeakingLength(max),
                  ),
                  role: SgTextRole.body,
                  weight: 600,
                ),
                const SizedBox(height: 4),
                SgText(
                  l10n.examSpeakingHint,
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Flat with a light edge, as the artboard draws both cards.
        node(
          SgSurface(
            kind: SgSurfaceKind.bar,
            radius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _RoundButton(
                      icon: icon,
                      label: label,
                      fill: fill,
                      onTap: onTap,
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // "00:52 / 01:00": the time large, the length small.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              SgText(
                                l10n.digits(_mmss(_seconds)),
                                role: SgTextRole.title,
                                weight: 700,
                              ),
                              const SizedBox(width: 4),
                              // The length gives way, wrapping under itself:
                              // in Bangla at 200 % the two ran 5.9 dp past the
                              // card on iOS (#588).
                              Flexible(
                                child: SgText(
                                  l10n.examSpeakingOf(l10n.digits(_mmss(max))),
                                  role: SgTextRole.label,
                                  weight: 500,
                                  color: tokens.color.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          SgText(
                            switch (_mic) {
                              _Mic.idle when _takesLeft <= 0 =>
                                l10n.examSpeakingRetake(0),
                              _Mic.idle => l10n.examSpeakingReady,
                              _Mic.recording when _interrupted =>
                                l10n.examSpeakingInterrupted,
                              _Mic.recording => l10n.examSpeakingRecording,
                              _Mic.recorded => l10n.examSpeakingRecorded,
                              _Mic.denied => l10n.examSpeakingDenied,
                            },
                            role: SgTextRole.caption,
                            color: tokens.color.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_mic != _Mic.idle && _mic != _Mic.denied) ...<Widget>[
                  const SizedBox(height: 12),
                  ExcludeSemantics(child: _Bars(levels: _levels)),
                ],
                if (_mic == _Mic.recorded) ...<Widget>[
                  const SizedBox(height: 12),
                  // Widths as their labels need them: "Delete recording" is the
                  // longer, and half the card each wraps it. Past 130 % text
                  // they stack: side by side, "recording" broke (#165).
                  if (SgScript.large(context)) ...<Widget>[
                    retake,
                    const SizedBox(height: 8),
                    delete,
                  ] else
                    Row(
                      children: <Widget>[
                        Expanded(flex: 5, child: retake),
                        const SizedBox(width: 8),
                        Expanded(flex: 6, child: delete),
                      ],
                    ),
                ],
                if (_mic == _Mic.denied) ...<Widget>[
                  const SizedBox(height: 12),
                  SgButton(
                    label: l10n.examSpeakingOpenSettings,
                    kind: SgButtonKind.secondary,
                    compact: true,
                    onPressed: () => unawaited(_recorder.openSettings()),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        node(
          SgSurface(
            kind: SgSurfaceKind.bar,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SgText(
                    l10n.examSpeakingRubricTitle.toUpperCase(),
                    role: SgTextRole.caption,
                    weight: 700,
                    letterSpacing: 0.6,
                    color: tokens.color.textSecondary,
                  ),
                ),
                for (final (i, line) in examRubricLines(
                  l10n,
                  ExamSection.speaking,
                ).indexed)
                  ExamRubricTick(
                    label: line,
                    ticked: _ticks[i],
                    // #84 counts ticks only with a recording: dimmed until
                    // there is one, as L13 does (#396).
                    onTap: _mic == _Mic.recorded ? () => _toggle(i) : null,
                  ),
                const SizedBox(height: 6),
                SgText(
                  l10n.examSpeakingSelfAssessed,
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The recorder's 56 dp round button, raised as the artboard draws it.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.fill,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Its own node: folded into the card's, the card would read as the button.
    final button = Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: AdaptiveTooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: tokens.isGlass
                  ? null
                  : Border.all(color: tokens.color.ink, width: 2),
              boxShadow: tokens.isGlass
                  ? null
                  : <BoxShadow>[
                      BoxShadow(
                        color: tokens.surface.shadow,
                        offset: tokens.surface.shadowOffset,
                      ),
                    ],
            ),
            child: Icon(icon, color: tokens.color.onAccent, size: 26),
          ),
        ),
      ),
    );
    // Off, dimmed as a rubric tick that can't be ticked is.
    return onTap == null ? Opacity(opacity: 0.5, child: button) : button;
  }
}

/// The recording as bars: the levels heard, the latest 32; even bars for a
/// recording made before this visit.
class _Bars extends StatelessWidget {
  const _Bars({required this.levels});

  final List<double> levels;

  static const int count = 32;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final heard = levels.length > count
        ? levels.sublist(levels.length - count)
        : levels;
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < count; i++)
            Container(
              width: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: i < heard.length
                  ? 6 + 22 * heard[i]
                  : heard.isEmpty
                  ? 6 + 10 * (0.5 + 0.5 * math.sin(i * 0.9)).abs()
                  : 6,
              decoration: BoxDecoration(
                color: i < heard.length || heard.isEmpty
                    ? tokens.color.ink
                    : tokens.surface.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
