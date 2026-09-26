import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart'
    show connectorsUsed, targetsUsed, textWords;
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart' show FormLabel;
import 'package:deutschplan/features/learn/grammar_practice_screen.dart'
    show itemKind;
import 'package:deutschplan/features/quiz/quiz_item_view.dart';
import 'package:deutschplan/features/study/study_cloze.dart'
    show StudyAnswerField;
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/services/exam_recorder.dart';
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
  WordQuestion(:final section) => section != ExamSection.articles,
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
class ExamQuestionView extends ConsumerWidget {
  const ExamQuestionView({
    required this.item,
    required this.given,
    required this.field,
    required this.onGiven,
    required this.plays,
    required this.onPlay,
    super.key,
    this.rubric = const <bool>[],
    this.onRubric,
    this.recordingPath,
    this.onDiscard,
    this.onRecording,
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

  /// Speaking's rubric ticks so far, and where a tick goes (FR-L12S-03).
  final List<bool> rubric;
  final ValueChanged<List<bool>>? onRubric;

  /// Where Speaking records (FR-L12S-02), and the recording deleted from the
  /// phone (FR-L12S-04).
  final Future<String> Function()? recordingPath;
  final Future<void> Function(String path)? onDiscard;

  /// Speaking: how to stop the recording and keep it while one runs, and
  /// null once it doesn't. *Submit exam* stops it first (#372).
  final ValueChanged<Future<void> Function()?>? onRecording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    if (item case final WritingTask task) {
      return ExamWriting(task: task, field: field);
    }
    if (item case final SpeakingTask task) {
      return ExamSpeaking(
        task: task,
        given: given,
        rubric: rubric,
        onGiven: onGiven,
        onRubric: onRubric ?? (_) {},
        recordingPath:
            recordingPath ?? () => throw StateError('no recording path'),
        onDiscard: onDiscard ?? (_) async {},
        onRecording: onRecording ?? (_) {},
      );
    }

    Widget speaker(String word, {double size = 48}) => DpSpeakerButton(
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
      WordQuestion(:final section, :final prompt, :final form) =>
        switch (section) {
          ExamSection.articles => (
            l10n.examRunAskArticle,
            _Centred(<Widget>[
              Flexible(child: GermanWord(prompt, role: DpTextRole.display)),
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
                DpSpeakerButton(
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
                DpText(
                  l10n.examRunPlaysLeft(examPlays - plays),
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.wordForms => (
            l10n.examRunAskForm,
            DpText(
              examFormPrompt(l10n, prompt, form),
              role: DpTextRole.headline,
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          ExamSection.reverse => (
            l10n.examRunAskGerman,
            DpText(
              prompt,
              role: DpTextRole.headline,
              weight: 600,
              textAlign: TextAlign.center,
            ),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
          _ => (
            l10n.examRunAskMeaning,
            _Centred(<Widget>[
              Flexible(child: GermanWord(prompt, role: DpTextRole.display)),
              const SizedBox(width: 14),
              speaker(prompt),
            ]),
            null,
            _Field(field: field, onGiven: onGiven),
          ),
        },
      GapQuestion(:final before, :final after, :final translation) => (
        l10n.examRunAskGap,
        _Gap(before: before, after: after, translation: translation),
        null,
        _Field(field: field, onGiven: onGiven),
      ),
      GrammarQuestion(:final item) => switch (item) {
        GapFill(:final before, :final after, :final translation) => (
          itemKind(l10n, item),
          _Gap(before: before, after: after, translation: translation),
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
          DpText(
            l10n.practiceRecallQuestion(question),
            role: DpTextRole.title,
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
      // Drawn above, whole.
      WritingTask() ||
      SpeakingTask() => throw StateError('a task is drawn whole'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          caption.toUpperCase(),
          role: DpTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 12),
        prompt,
        if (hint != null) ...<Widget>[
          const SizedBox(height: 12),
          DpText(
            hint,
            role: DpTextRole.caption,
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
  });

  final String before;
  final String after;
  final String translation;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      children: <Widget>[
        DpText(
          <String>[
            if (before.isNotEmpty) before,
            '_____',
            if (after.isNotEmpty) after,
          ].join(' '),
          role: DpTextRole.title,
          weight: 600,
          textAlign: TextAlign.center,
        ),
        if (translation.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          DpText(
            translation,
            role: DpTextRole.body,
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
            child: DpSurface(
              kind: DpSurfaceKind.bar,
              selected: picked.contains(i),
              radius: context.tokens.shape.button,
              onTap: () => onTap(i),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: DpText(word, role: DpTextRole.bodyLarge, weight: 600),
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

/// L12's Writing (`exam-writing-speaking.md`, the ExamWriting artboard): the
/// task and its ten target words, which turn Lime as the text uses them
/// (FR-L12W-01); the text; and, live, its length against the level's
/// minimum (FR-L12W-02) and the connectors in it. The text is the runner's
/// typed answer, so it is kept in `exam_answers.given` and never leaves the
/// phone (FR-L12W-04).
class ExamWriting extends StatelessWidget {
  const ExamWriting({required this.task, required this.field, super.key});

  final WritingTask task;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    final topic = task.category ?? l10n.examWritingTopicFallback;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: field,
      builder: (context, value, _) {
        final text = value.text;
        final used = targetsUsed(text, task.targets).toSet();
        final connectors = connectorsUsed(text, task.connectors);
        Widget panel(Widget child) => _taskPanel(tokens, child);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Nodes of their own: merged, the task and the counts would be
            // read as the text field's label.
            Semantics(
              container: true,
              child: panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(
                      <String>[
                        l10n.examWritingTask(task.level, topic),
                        l10n.examWritingUse,
                      ].join(' '),
                      role: DpTextRole.body,
                      weight: 600,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final target in task.targets)
                          _Target(word: target, used: used.contains(target)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DpText(
                      l10n.examWritingUsed(
                        used.length,
                        task.targets.length,
                        task.minWords,
                        task.level,
                      ),
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            DpText(
              l10n.examWritingYourText.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: TextField(
                controller: field,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                // An exam: the keyboard must not spell or complete the German,
                // as the runner's other typed answers don't let it.
                autocorrect: false,
                enableSuggestions: false,
                textAlignVertical: TextAlignVertical.top,
                style: DpText.styleFor(
                  tokens,
                  DpTextRole.body,
                ).copyWith(fontSize: 16, height: 22 / 16),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.surface.cardStrong,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: edge,
                  enabledBorder: edge,
                  focusedBorder: edge,
                  // "Your text" above is its own line; the hint is what a
                  // screen reader hears on the field, not a bare edit box.
                  hintText: l10n.examWritingFieldHint,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    l10n.examWritingCount(
                      textWords(text).length,
                      task.minWords,
                    ),
                    role: DpTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  if (connectors.isNotEmpty)
                    Expanded(
                      child: DpText(
                        l10n.examWritingConnectors(connectors.join(', ')),
                        role: DpTextRole.caption,
                        color: tokens.color.correctText,
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A target word: an outline until the text uses it, then Lime with a tick.
class _Target extends StatelessWidget {
  const _Target({required this.word, required this.used});

  final String word;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Lime is light in both modes: its ink is Sun's, the dark one.
    final ink = used ? tokens.color.onAccent : tokens.color.ink;
    // A node each, so a screen reader steps through the words.
    return Semantics(
      container: true,
      label: used
          ? AppLocalizations.of(context).examWritingTargetUsed(word)
          : word,
      excludeSemantics: true,
      // The artboard's 26, grown with the text size: a fixed 26 cut
      // "Wohnung" at 150 % (#165).
      child: Container(
        height: DpScript.grow(context, 26),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: used ? tokens.color.easy : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: used ? ink : tokens.surface.outline,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (used) ...<Widget>[
              Icon(Icons.check, size: 12, color: ink),
              const SizedBox(width: 4),
            ],
            DpText(word, role: DpTextRole.caption, weight: 600, color: ink),
          ],
        ),
      ),
    );
  }
}

/// A flat Oat panel on paper, as the task artboards draw their prompt — no
/// edge, no shadow, which every DpSurface kind has; the frosted card under
/// glass.
Widget _taskPanel(DpTokens tokens, Widget child) => tokens.isGlass
    ? DpSurface(radius: 12, padding: _taskPadding, child: child)
    : Container(
        padding: _taskPadding,
        decoration: BoxDecoration(
          color: tokens.surface.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

const EdgeInsets _taskPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

/// "00:52".
String _mmss(int seconds) =>
    '${'${seconds ~/ 60}'.padLeft(2, '0')}:${'${seconds % 60}'.padLeft(2, '0')}';

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
  final Future<void> Function(String path) onDiscard;

  /// Told how to stop and keep a recording while one runs, and null after.
  final ValueChanged<Future<void> Function()?> onRecording;

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
  late List<bool> _ticks = <bool>[
    for (var i = 0; i < ExamSpeaking.ticks; i++)
      i < widget.rubric.length && widget.rubric[i],
  ];

  /// While recording, the seconds so far; once recorded, its length.
  int _seconds = 0;

  // ponytail: in memory, so a resumed attempt offers the retake again.
  int _retakesLeft = ExamSpeaking.retakes;

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

  @override
  void dispose() {
    // Leaving mid-recording keeps what was said.
    if (_mic == _Mic.recording) unawaited(_finish(mounted: false));
    _tick?.cancel();
    unawaited(_heard?.cancel());
    unawaited(_recorder.stopPlaying());
    _held.close();
    super.dispose();
  }

  // Each takes the recorder before its first await: dispose closes the
  // subscription, and a recording left mid-way still has to be stopped.

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
    await recorder.stopPlaying();
    final retake = _mic == _Mic.recorded;
    final path = await widget.recordingPath();
    await recorder.start(path);
    if (!mounted) {
      // The task left the screen while the recorder started: stop it, and
      // keep what little it has, as leaving mid-recording does.
      await recorder.stop();
      widget.onGiven(path);
      return;
    }
    setState(() {
      if (retake) _retakesLeft--;
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
      if (!mounted) return;
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
    await recorder.play(path);
    if (mounted) setState(() => _playing = false);
  }

  /// FR-L12S-04: the file gone and the section zero.
  Future<void> _delete() async {
    final recorder = _recorder;
    final path = _path;
    await recorder.stopPlaying();
    if (path != null) await widget.onDiscard(path);
    widget.onGiven('');
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
    final retake = DpButton(
      label: l10n.examSpeakingRetake(_retakesLeft),
      kind: DpButtonKind.secondary,
      compact: true,
      onPressed: _retakesLeft > 0 ? () => unawaited(_record()) : null,
    );
    final delete = DpButton(
      label: l10n.examSpeakingDelete,
      kind: DpButtonKind.secondary,
      colour: tokens.surface.cardStrong,
      onColour: tokens.color.ink,
      compact: true,
      onPressed: () => unawaited(_delete()),
    );

    final (
      IconData icon,
      String label,
      Color fill,
      VoidCallback onTap,
    ) = switch (_mic) {
      _Mic.idle || _Mic.denied => (
        Icons.mic,
        l10n.examSpeakingRecord,
        tokens.color.again,
        () => unawaited(_record()),
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
          _taskPanel(
            tokens,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DpText(
                  l10n.examSpeakingPrompt(
                    l10n.examSpeakingTask(task.level, topic),
                    max % 60 == 0
                        ? l10n.examSpeakingMinutes(max ~/ 60)
                        : l10n.examSpeakingLength(max),
                  ),
                  role: DpTextRole.body,
                  weight: 600,
                ),
                const SizedBox(height: 4),
                DpText(
                  l10n.examSpeakingHint,
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Flat with a light edge, as the artboard draws both cards.
        node(
          DpSurface(
            kind: DpSurfaceKind.bar,
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
                              DpText(
                                l10n.digits(_mmss(_seconds)),
                                role: DpTextRole.title,
                                weight: 700,
                              ),
                              const SizedBox(width: 4),
                              DpText(
                                l10n.examSpeakingOf(l10n.digits(_mmss(max))),
                                role: DpTextRole.label,
                                weight: 500,
                                color: tokens.color.textSecondary,
                              ),
                            ],
                          ),
                          DpText(
                            switch (_mic) {
                              _Mic.idle => l10n.examSpeakingReady,
                              _Mic.recording => l10n.examSpeakingRecording,
                              _Mic.recorded => l10n.examSpeakingRecorded,
                              _Mic.denied => l10n.examSpeakingDenied,
                            },
                            role: DpTextRole.caption,
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
                  if (DpScript.large(context)) ...<Widget>[
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
                  DpButton(
                    label: l10n.examSpeakingOpenSettings,
                    kind: DpButtonKind.secondary,
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
          DpSurface(
            kind: DpSurfaceKind.bar,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: DpText(
                    l10n.examSpeakingRubricTitle.toUpperCase(),
                    role: DpTextRole.caption,
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
                DpText(
                  l10n.examSpeakingSelfAssessed,
                  role: DpTextRole.caption,
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
    return Semantics(
      container: true,
      button: true,
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
              Expanded(child: DpText(label, role: DpTextRole.body)),
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
