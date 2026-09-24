import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_run_fixtures.dart';

/// A question after Speaking, so *Next* moves on from it.
const WordQuestion after = WordQuestion(
  ExamSection.vocabulary,
  'v1',
  prompt: 'das Haus',
  expected: 'house',
);

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
  }) async {
    // A tall phone: the rubric's last line is on screen.
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    run = StubExamRun(items: items, given: given ?? <int, String>{});
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
          l10n.examSpeakingLength('60'),
        ),
      ),
      findsOneWidget,
    );
    expect(l10n.examSpeakingLength('60'), '1 minute');
    expect(l10n.examSpeakingLength('90'), '90 seconds');
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

  testWidgets('leaving mid-recording keeps what was said', (tester) async {
    await pump(tester);
    await press(tester, Icons.mic);
    await tester.pump(const Duration(seconds: 12));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(mic.stopped, 1);
    expect(run.answers, <(int, String?)>[(1, path)]);
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
}
