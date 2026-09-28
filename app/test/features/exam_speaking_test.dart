import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart'
    show AudioInterruptionMode, AudioRecorder, RecordConfig;
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/features/exam/exam_runner_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/services/exam_recorder.dart';

import '../db/content_fixture.dart' show tempDir;
import 'exam_run_fixtures.dart';

/// A question after Speaking, so *Next* moves on from it.
const WordQuestion after = WordQuestion(
  ExamSection.vocabulary,
  'v1',
  prompt: 'das Haus',
  expected: 'house',
);

/// The `record` plugin without a phone: a take writes its file as it starts,
/// as the plugin opens it, and [fails] makes the stop throw.
class _Plugin implements AudioRecorder {
  String? path;
  bool fails = false;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.path = path;
    File(path).writeAsStringSync('take');
  }

  @override
  Future<String?> stop() async {
    if (fails) throw StateError('the recorder failed');
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// L12 · Speaking — #134.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late StubExamRun run;
  late FakeRecorder mic;
  const path = '/recordings/7.m4a';

  Future<void> pump(
    WidgetTester tester, {
    List<ExamItem> items = const <ExamItem>[artboardSpeaking, after],
    Map<int, String>? given,
    FakeRecorder? recorder,
    int? durationSec,
  }) async {
    // A tall phone: the rubric's last line is on screen.
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    run = StubExamRun(
      items: items,
      given: given ?? <int, String>{},
      attempt: durationSec == null
          ? null
          : artboardAttempt(durationSec: durationSec),
    );
    mic = recorder ?? FakeRecorder();
    final routes = GoRouter(
      initialLocation: '/exam',
      routes: <RouteBase>[
        GoRoute(
          path: '/exam',
          builder: (_, _) => ExamRunnerScreen(
            attemptId: 7,
            results: (_) => const Scaffold(body: Text('L13')),
            onLeft: (_) {},
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...examRunStub(run),
          examRecorderProvider.overrideWithValue(mic),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The round button by what it shows: mic, stop, play.
  Future<void> press(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    // The recorder's awaits resolve after the first frame; the second draws
    // what they changed.
    await tester.pump();
    await tester.pump();
  }

  testWidgets("the task for the level, its length, and what's ticked after", (
    tester,
  ) async {
    await pump(tester);

    expect(
      find.text(
        l10n.examSpeakingPrompt(
          l10n.examSpeakingTask('A1', 'Wohnen'),
          l10n.examSpeakingMinutes(1),
        ),
      ),
      findsOneWidget,
    );
    expect(l10n.examSpeakingMinutes(1), '1 minute');
    expect(l10n.examSpeakingMinutes(2), '2 minutes');
    expect(l10n.examSpeakingLength(90), '90 seconds');
    expect(find.text(l10n.examSpeakingReady), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text(l10n.examSpeakingOf('01:00')), findsOneWidget);
    expect(find.text(l10n.examSpeakingSelfAssessed), findsOneWidget);
  });

  group('FR-L12S-01 the microphone', () {
    testWidgets('asked on the first record, after the line that says why', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(mic.asked, 0);
      expect(find.bySemanticsLabel(l10n.examSpeakingRecord), findsOneWidget);

      await press(tester, Icons.mic);
      expect(mic.asked, 1);
      expect(mic.started, <String>[path]);
      semantics.dispose();
    });

    testWidgets('refused: the section can be skipped, and the settings are '
        'a tap away', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, recorder: FakeRecorder(allowed: false));

      await press(tester, Icons.mic);
      await tester.pumpAndSettle();
      expect(find.text(l10n.examSpeakingDenied), findsOneWidget);
      expect(mic.started, isEmpty);

      await tester.tap(find.text(l10n.examSpeakingOpenSettings));
      expect(mic.openedSettings, isTrue);

      await tester.tap(find.text(l10n.examRunNext));
      await tester.pumpAndSettle();
      expect(find.text('das Haus'), findsOneWidget);
      expect(run.answers, isEmpty, reason: 'nothing recorded, 0 points');
      semantics.dispose();
    });
  });

  group('FR-L12S-02 the recording', () {
    testWidgets("to the attempt's file, stopped by itself at the level's "
        'length', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await press(tester, Icons.mic);

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('00:30'), findsOneWidget);
      expect(mic.stopped, 0);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(mic.stopped, 1);
      expect(run.answers, <(int, String?)>[(1, path)]);
      expect(find.text(l10n.examSpeakingRecorded), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('stopped by hand, then played back', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await press(tester, Icons.mic);
      await tester.pump(const Duration(seconds: 5));
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();

      expect(find.text('00:05'), findsOneWidget);
      await press(tester, Icons.play_arrow);
      expect(mic.played, <String>[path]);
      semantics.dispose();
    });

    testWidgets('a double tap on Record starts once', (tester) async {
      final slow = FakeRecorder()..starting = Completer<void>();
      await pump(tester, recorder: slow);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      slow.starting!.complete();
      await tester.pump();
      await tester.pump();

      expect(slow.started, <String>[path]);
    });

    testWidgets('leaving while the recorder starts still stops it', (
      tester,
    ) async {
      final slow = FakeRecorder()..starting = Completer<void>();
      await pump(tester, recorder: slow);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      slow.starting!.complete();
      await tester.pump();

      expect(slow.stopped, 1, reason: 'no microphone left running');
      expect(run.answers, <(int, String?)>[(1, path)]);
    });

    testWidgets('one retake', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.examSpeakingRetake(1)));
      await tester.pump();
      expect(mic.started, <String>[path, path]);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();

      expect(find.text(l10n.examSpeakingRetake(0)), findsOneWidget);
      await tester.tap(find.text(l10n.examSpeakingRetake(0)));
      await tester.pump();
      expect(mic.started, hasLength(2));
      semantics.dispose();
    });

    testWidgets('#731 the retake used stays used when the learner leaves '
        'the task and comes back', (tester) async {
      await pump(tester);
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.examSpeakingRetake(1)));
      await tester.pump();
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.examRunNext));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.examRunPrevious));
      await tester.pumpAndSettle();

      expect(find.text(l10n.examSpeakingRetake(0)), findsOneWidget);
      expect(find.text(l10n.examSpeakingRetake(1)), findsNothing);
    });

    testWidgets('#691 EX-6 Delete, then Record, is the retake: after it, no '
        'take is left', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.examSpeakingDelete));
      await tester.pumpAndSettle();

      // The retake, though the first take is gone.
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();
      expect(mic.started, <String>[path, path]);
      expect(find.text(l10n.examSpeakingRetake(0)), findsOneWidget);

      await tester.tap(find.text(l10n.examSpeakingDelete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.examSpeakingRetake(0)), findsOneWidget);
      expect(find.text(l10n.examSpeakingReady), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.examSpeakingRecord)),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );
      await press(tester, Icons.mic);
      expect(mic.started, hasLength(2), reason: 'no third take');
      semantics.dispose();
    });

    testWidgets('#691 EX-6 a recording there on resume is the first take', (
      tester,
    ) async {
      await pump(
        tester,
        items: const <ExamItem>[artboardSpeaking],
        given: <int, String>{1: path},
      );
      await tester.tap(find.text(l10n.examSpeakingDelete));
      await tester.pumpAndSettle();
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();
      expect(find.text(l10n.examSpeakingRetake(0)), findsOneWidget);
    });

    testWidgets('#691 EX-8 FR-L12S-01 a task gone while the phone asks '
        'records nothing', (tester) async {
      final asking = FakeRecorder()..asking = Completer<void>();
      await pump(tester, recorder: asking);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      expect(asking.asked, 1);

      // 0:00 submitted the paper under the dialog, and the task went.
      await tester.pumpWidget(const SizedBox());
      asking.asking!.complete();
      await tester.pump();
      await tester.pump();

      expect(asking.started, isEmpty);
      expect(run.answers, isEmpty);
    });

    test('#691 EX-5 FR-L12S-02 a take records beside the recording and '
        'replaces it once it stops; one that fails leaves it whole', () async {
      final folder = tempDir('sg_take');
      final kept = File('${folder.path}/7.m4a')..writeAsStringSync('kept');
      final plugin = _Plugin();
      final recorder = PlatformExamRecorder(recorder: plugin);

      await recorder.start(kept.path);
      expect(kept.readAsStringSync(), 'kept', reason: 'recording elsewhere');
      plugin.fails = true;
      await expectLater(recorder.stop(), throwsStateError);
      expect(kept.readAsStringSync(), 'kept');
      expect(File(plugin.path!).existsSync(), isFalse, reason: 'no take left');

      plugin.fails = false;
      await recorder.start(kept.path);
      await recorder.stop();
      expect(kept.readAsStringSync(), 'take');
      expect(File(plugin.path!).existsSync(), isFalse);

      // A take cut off by the app's being killed goes with the recording.
      File(ModelRepository.takeOf(kept.path)).writeAsStringSync('cut off');
      await ModelRepository.deleteRecordingAt(kept.path);
      expect(folder.listSync(), isEmpty);
    });

    test('FR-L12S-02 #624 the phone pauses a recording for a call and '
        'resumes it after, never leaves it paused for good', () {
      expect(
        PlatformExamRecorder.config.audioInterruption,
        AudioInterruptionMode.pauseResume,
      );
      expect(PlatformExamRecorder.config.bitRate, 32000);
      expect(PlatformExamRecorder.config.numChannels, 1);
    });

    testWidgets('#624 a call, an alarm or an assistant holds the recording '
        'and its time, which go on after', (tester) async {
      await pump(tester);
      await press(tester, Icons.mic);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:02'), findsOneWidget);

      // The event lands after the first frame; the second draws it.
      mic.interruptions.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.examSpeakingInterrupted), findsOneWidget);
      await tester.pump(const Duration(seconds: 90));
      expect(find.text('00:02'), findsOneWidget);
      expect(mic.stopped, 0, reason: 'past the length, the time is held');

      mic.interruptions.add(false);
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.examSpeakingRecording), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:03'), findsOneWidget);
    });

    testWidgets('#892 #624 a call while the recorder starts holds the time '
        'too', (tester) async {
      final slow = FakeRecorder()..starting = Completer<void>();
      await pump(tester, recorder: slow);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      slow.interruptions.add(true);
      await tester.pump();
      slow.starting!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.examSpeakingInterrupted), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('#670 the app going to the background stops and keeps it', (
      tester,
    ) async {
      await pump(tester);
      await press(tester, Icons.mic);
      await tester.pump(const Duration(seconds: 12));

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(mic.stopped, 1);
      expect(run.answers, <(int, String?)>[(1, path)]);

      // No frames while the app is hidden: the screen shows it on return.
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(l10n.examSpeakingRecorded), findsOneWidget);
    });

    testWidgets('#732 a take that cannot be played says so, and Play comes '
        'back', (tester) async {
      await pump(tester, recorder: FakeRecorder()..playFails = true);
      await press(tester, Icons.mic);
      await press(tester, Icons.stop);
      await tester.pumpAndSettle();

      await press(tester, Icons.play_arrow);
      expect(find.text(l10n.examSpeakingPlayFailed), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('one made before shows as recorded, with its length', (
      tester,
    ) async {
      await pump(
        tester,
        items: const <ExamItem>[artboardSpeaking],
        given: <int, String>{1: path},
        recorder: FakeRecorder(recorded: const Duration(seconds: 52)),
      );
      expect(find.text(l10n.examSpeakingRecorded), findsOneWidget);
      expect(find.text('00:52'), findsOneWidget);
    });
  });

  testWidgets('#372 Submit while recording grades the saved recording', (
    tester,
  ) async {
    await pump(tester, items: const <ExamItem>[artboardSpeaking]);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));

    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pumpAndSettle();

    expect(mic.stopped, 1);
    expect(
      find.text(l10n.examRunSubmitTitle),
      findsNothing,
      reason: 'the task was answered, so nothing to confirm',
    );
    expect(run.submitted, 1);
    expect(run.answersAtSubmit, <(int, String?)>[(1, path)]);
  });

  testWidgets('#372 a recording stopped by hand is not stopped again', (
    tester,
  ) async {
    await pump(tester, items: const <ExamItem>[artboardSpeaking]);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));
    await press(tester, Icons.stop);

    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pumpAndSettle();

    expect(mic.stopped, 1);
    expect(run.submitted, 1);
  });

  testWidgets("#372 a recording stopped by moving back is its own task's", (
    tester,
  ) async {
    // Speaking second, where the paper resumes.
    await pump(
      tester,
      items: const <ExamItem>[after, artboardSpeaking],
      given: <int, String>{1: 'house'},
    );
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));

    await tester.tap(find.text(l10n.examRunPrevious));
    await tester.pumpAndSettle();

    expect(mic.stopped, 1);
    expect(run.answers, <(int, String?)>[(2, path)]);

    // And the runner holds it as the task's: nothing is left to ask about.
    await tester.tap(find.text(l10n.examRunNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.examRunSubmitTitle), findsNothing);
    expect(run.submitted, 1);
  });

  testWidgets('#372 a second Submit, or Stop, while it stops grades once', (
    tester,
  ) async {
    await pump(tester, items: const <ExamItem>[artboardSpeaking]);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));
    final stopping = mic.stopping = Completer<void>();

    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pump();
    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pump();
    await press(tester, Icons.stop);
    stopping.complete();
    await tester.pumpAndSettle();

    expect(mic.stopped, 1);
    expect(find.text(l10n.examRunSubmitTitle), findsNothing);
    expect(run.submitted, 1);
    expect(run.answersAtSubmit, <(int, String?)>[(1, path)]);
  });

  testWidgets('#372 a recorder that fails to stop never holds the exam', (
    tester,
  ) async {
    await pump(tester, items: const <ExamItem>[artboardSpeaking]);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));
    mic.stopFails = true;

    await tester.tap(find.text(l10n.examRunSubmit));
    await tester.pumpAndSettle();

    // The take is lost: the recorder is ready again, the task is empty, and
    // the submit asks.
    expect(find.text(l10n.examSpeakingReady), findsOneWidget);
    expect(find.text(l10n.examRunSubmitTitle), findsOneWidget);
    await tester.tap(find.text(l10n.examRunSubmitConfirm));
    await tester.pumpAndSettle();
    expect(run.submitted, 1);
    expect(find.text('L13'), findsOneWidget);
  });

  testWidgets('#372 FR-L12-03 at 0:00 a live recording is saved and graded', (
    tester,
  ) async {
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      durationSec: 20 * 60 - 3,
    );
    await press(tester, Icons.mic);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(mic.stopped, 1);
    expect(run.submitted, 1);
    expect(run.answersAtSubmit, <(int, String?)>[(1, path)]);
  });

  testWidgets('leaving mid-recording keeps what was said', (tester) async {
    await pump(tester);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(mic.stopped, 1);
    expect(run.answers, <(int, String?)>[(1, path)]);
  });

  testWidgets('#671 Leave stops a live recording before the attempt, and '
      'its recording, go', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));
    final stopping = mic.stopping = Completer<void>();

    await tester.tap(find.bySemanticsLabel(l10n.examRunPause));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.examLeaveConfirm));
    await tester.pump();
    expect(run.abandoned, 0, reason: 'the recorder is still writing');

    stopping.complete();
    await tester.pumpAndSettle();
    expect(mic.stopped, 1);
    expect(run.abandoned, 1);
    semantics.dispose();
  });

  testWidgets('a screen reader hears the task, the recorder and the rubric '
      'apart', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final recorder = tester
        .getSemantics(find.text(l10n.examSpeakingReady))
        .label;
    expect(recorder, isNot(contains(l10n.examSpeakingHint)));
    expect(recorder, isNot(contains(l10n.examSpeakingSelfAssessed)));
    semantics.dispose();
  });

  testWidgets('FR-L12S-03 each tick is written as it is ticked', (
    tester,
  ) async {
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      given: <int, String>{1: path},
    );

    await tester.tap(find.text(l10n.examSpeakingRubricTask));
    await tester.pump();
    await tester.tap(find.text(l10n.examSpeakingRubricVocabulary));
    await tester.pump();

    expect(run.rubrics.last.$1, 1);
    expect(run.rubrics.last.$2, <bool>[true, false, false, true]);
  });

  testWidgets('FR-L12S-03 #396 the rubric waits for a recording', (
    tester,
  ) async {
    await pump(tester, items: const <ExamItem>[artboardSpeaking]);

    await tester.tap(find.text(l10n.examSpeakingRubricTask));
    await tester.pump();
    expect(run.rubrics, isEmpty, reason: 'nothing recorded to tick');

    await press(tester, Icons.mic);
    await press(tester, Icons.stop);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.examSpeakingRubricTask));
    await tester.pump();
    expect(run.rubrics.last.$2, <bool>[true, false, false, false]);
  });

  testWidgets('FR-L12S-04 delete removes the file and zeros the section', (
    tester,
  ) async {
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      given: <int, String>{1: path},
    );

    await tester.tap(find.text(l10n.examSpeakingDelete));
    await tester.pumpAndSettle();

    expect(run.discarded, <String>[path]);
    expect(run.answers, <(int, String?)>[(1, null)]);
    expect(find.text(l10n.examSpeakingReady), findsOneWidget);
  });

  testWidgets('FR-L12S-04 #891 a delete whose write fails, its sheet closed, '
      'keeps the take and its file', (tester) async {
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      given: <int, String>{1: path},
    );
    run.failWrites = true;
    await tester.tap(find.text(l10n.examSpeakingDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.saveAnswerFailed), findsOneWidget);
    Navigator.of(tester.element(find.text(l10n.saveAnswerFailed))).pop();
    await tester.pumpAndSettle();

    // The answer still points at the file, and the file is still there.
    expect(run.discarded, isEmpty);
    expect(find.text(l10n.examSpeakingDelete), findsOneWidget);
    expect(find.text(l10n.examSpeakingReady), findsNothing);

    // Written this time, the file goes after it.
    run.failWrites = false;
    await tester.tap(find.text(l10n.examSpeakingDelete));
    await tester.pumpAndSettle();
    expect(run.answers.last, (1, null));
    expect(run.discarded, <String>[path]);
    expect(find.text(l10n.examSpeakingReady), findsOneWidget);
  });

  testWidgets("FR-L12S-04 #731 delete clears the take's ticks", (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      given: <int, String>{1: path},
    );
    await tester.tap(find.text(l10n.examSpeakingRubricTask));
    await tester.pump();

    await tester.tap(find.text(l10n.examSpeakingDelete));
    await tester.pumpAndSettle();
    expect(run.rubrics.last.$2, <bool>[false, false, false, false]);

    await press(tester, Icons.mic);
    await press(tester, Icons.stop);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.examSpeakingRubricTask)),
      isSemantics(isChecked: false, hasCheckedState: true),
      reason: 'the new take starts unticked',
    );
    semantics.dispose();
  });

  testWidgets('#730 a tick that is not written is taken back', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      items: const <ExamItem>[artboardSpeaking],
      given: <int, String>{1: path},
    );
    run.failWrites = true;
    await tester.tap(find.text(l10n.examSpeakingRubricTask));
    await tester.pumpAndSettle();
    expect(find.text(l10n.saveAnswerFailed), findsOneWidget);
    Navigator.of(tester.element(find.text(l10n.saveAnswerFailed))).pop();
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.examSpeakingRubricTask)),
      isSemantics(isChecked: false, hasCheckedState: true),
    );
    semantics.dispose();
  });
}
