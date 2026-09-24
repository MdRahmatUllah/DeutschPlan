import 'dart:async';

import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';
import 'exam_run_fixtures.dart';

/// L12 · Exam runner — #130.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late StubExamRun run;

  Future<void> pump(
    WidgetTester tester, {
    StubExamRun? stub,
    List<Override> more = const <Override>[],
  }) async {
    run = stub ?? StubExamRun();
    final routes = GoRouter(
      initialLocation: '/opener',
      routes: <RouteBase>[
        GoRoute(
          path: '/opener',
          builder: (_, _) => const Scaffold(body: Text('opener')),
        ),
        GoRoute(
          path: '/exam',
          builder: (_, _) => ExamRunnerScreen(
            attemptId: 7,
            results: (_) => const Scaffold(body: Text('L13')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[...examRunStub(run), ...more],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    unawaited(routes.push('/exam'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('FR-L12-01 it resumes on the first unanswered question', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.examRunQuestion(21, 40)), findsOneWidget);
    expect(
      find.text(l10n.examRunSection(l10n.examSectionArticles, 3, 6)),
      findsOneWidget,
    );
    expect(find.text('Wohnung'), findsOneWidget);
    expect(find.text(l10n.examRunAskArticle.toUpperCase()), findsOneWidget);
  });

  testWidgets('FR-L12-01 a tap is written at once; FR-L12-02 no verdict', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, 'der');
    expect(run.answers, [(21, 'der')]);
    expect(find.byType(DpVerdictRow), findsNothing, reason: 'BR-EXAM-05');
    await tap(tester, 'die');
    expect(run.answers.last, (21, 'die'), reason: 'an answer can change');
  });

  testWidgets('FR-L12-01 a typed answer is written when the learner moves on', (
    tester,
  ) async {
    await pump(tester, stub: StubExamRun(given: <int, String>{}));
    expect(find.text(l10n.examRunQuestion(1, 40)), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'word 1');
    await tap(tester, l10n.examRunNext);
    expect(run.answers, [(1, 'word 1')]);
    expect(find.text(l10n.examRunQuestion(2, 40)), findsOneWidget);

    await tap(tester, l10n.examRunPrevious);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'word 1',
      reason: 'the field comes back with what was written',
    );
  });

  testWidgets('the flag is written as it is set and cleared', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel(l10n.examRunFlag));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(l10n.examRunFlagged));
    await tester.pumpAndSettle();
    expect(run.flags, [(21, true), (21, false)]);
    semantics.dispose();
  });

  group('FR-L12-03 the clock', () {
    testWidgets('counts down and is written every 10 s', (tester) async {
      await pump(tester);
      expect(find.text('14:32'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('14:31'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(run.times, [(10, 0)]);
    });

    testWidgets('pause stops it, hides the paper and keeps paused apart', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await tester.tap(find.bySemanticsLabel(l10n.examRunPause));
      await tester.pumpAndSettle();
      expect(find.text(l10n.examRunPaused), findsOneWidget);
      expect(find.text('Wohnung'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('14:32'), findsOneWidget, reason: 'stopped');
      expect(run.times, [(0, 10)]);

      await tap(tester, l10n.examRunResume);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('14:31'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('at 0:00 the exam submits itself', (tester) async {
      await pump(
        tester,
        stub: StubExamRun(attempt: artboardAttempt(durationSec: 20 * 60 - 3)),
      );
      expect(find.text('0:03'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(run.submitted, 1);
      expect(find.text('L13'), findsOneWidget);
      expect(run.times, [(3, 0)], reason: 'the last seconds are written');
    });

    testWidgets('the last two minutes are Coral', (tester) async {
      Color? fill(String time) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: find.text(time),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      await pump(
        tester,
        stub: StubExamRun(attempt: artboardAttempt(durationSec: 20 * 60 - 121)),
      );
      expect(fill('2:01'), isNot(DpPalette.light.again));
      await tester.pump(const Duration(seconds: 1));
      expect(fill('2:00'), DpPalette.light.again);
    });

    testWidgets('off: no clock, no submit, the time still counted', (
      tester,
    ) async {
      // Past its 20 minutes already: with the timer off that means nothing.
      await pump(
        tester,
        stub: StubExamRun(
          timed: false,
          attempt: artboardAttempt(durationSec: 25 * 60),
        ),
      );
      expect(find.text('0:00'), findsNothing);
      await tester.pump(const Duration(minutes: 21));
      expect(run.submitted, 0);
      expect(run.times, isNotEmpty, reason: 'the time is still counted');
    });
  });

  group('FR-L12-05 submit', () {
    final two = <ExamItem>[
      const WordQuestion(
        ExamSection.articles,
        'a',
        prompt: 'Tür',
        expected: 'die',
      ),
      const WordQuestion(
        ExamSection.articles,
        'b',
        prompt: 'Haus',
        expected: 'das',
      ),
    ];

    testWidgets('with questions unanswered it asks first', (tester) async {
      await pump(
        tester,
        stub: StubExamRun(items: two, given: <int, String>{1: 'die'}),
      );
      await tap(tester, l10n.examRunSubmit);
      expect(find.text(l10n.examRunSubmitUnanswered(1)), findsOneWidget);
      await tap(tester, l10n.examRunKeepAnswering);
      expect(run.submitted, 0);

      await tap(tester, l10n.examRunSubmit);
      await tap(tester, l10n.examRunSubmitConfirm);
      expect(run.submitted, 1);
      expect(find.text('L13'), findsOneWidget);
    });

    testWidgets('with every answer given it does not ask', (tester) async {
      await pump(
        tester,
        stub: StubExamRun(items: two, given: <int, String>{1: 'die', 2: 'das'}),
      );
      await tap(tester, l10n.examRunNext);
      await tap(tester, l10n.examRunSubmit);
      expect(run.submitted, 1);
    });
  });

  testWidgets('a finished attempt opens on its results', (tester) async {
    await pump(
      tester,
      stub: StubExamRun(attempt: artboardAttempt(status: 'finished')),
    );
    expect(find.text('L13'), findsOneWidget);
  });

  testWidgets('an attempt that is not there says so', (tester) async {
    await pump(tester, stub: StubExamRun(missing: true));
    expect(find.text(l10n.examRunLoadFailed), findsOneWidget);
  });

  group('grammar questions record what #84 grades', () {
    Future<void> one(WidgetTester tester, GrammarItem item) => pump(
      tester,
      stub: StubExamRun(
        items: <ExamItem>[GrammarQuestion('t#0', item)],
        given: <int, String>{},
      ),
    );

    testWidgets('rule recall: the rule index', (tester) async {
      await one(
        tester,
        const RuleRecall(
          question: 'Konjunktiv II',
          options: <String>['polite', 'verb last', 'dative', 'v2'],
          answer: 0,
        ),
      );
      await tap(tester, 'verb last');
      expect(run.answers, [(1, '1')]);
    });

    testWidgets('spot the error: the word index', (tester) async {
      await one(
        tester,
        const SpotTheError(
          tokens: <String>['Können', 'Sie', 'helfen?'],
          wrong: 0,
          correction: 'Könnten',
        ),
      );
      await tap(tester, 'Können');
      expect(run.answers, [(1, '0')]);
    });

    testWidgets('order the sentence: the words, in order', (tester) async {
      await one(
        tester,
        const OrderTheSentence(
          chips: <String>['Sie', 'helfen?', 'Könnten'],
          answer: <String>['Könnten', 'Sie', 'helfen?'],
        ),
      );
      await tap(tester, 'Könnten');
      await tap(tester, 'Sie');
      await tester.tap(find.text('helfen?').last);
      await tester.pumpAndSettle();
      expect(run.answers.last, (1, 'Könnten Sie helfen?'));
    });

    testWidgets('pick the form: the form', (tester) async {
      await one(
        tester,
        const PickTheForm(
          before: '',
          after: 'Sie mir helfen?',
          options: <String>['Könnten', 'Können'],
          answer: 'Könnten',
          translation: '',
        ),
      );
      await tap(tester, 'Können');
      expect(run.answers, [(1, 'Können')]);
    });
  });

  testWidgets('FR-L12-06 a Listening word plays once and replays twice', (
    tester,
  ) async {
    late AppDatabase db;
    late SettingsRepository settings;
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    final spoken = <String>[];
    await pump(
      tester,
      stub: StubExamRun(
        items: <ExamItem>[
          const WordQuestion(
            ExamSection.listening,
            'l',
            prompt: 'das Haus',
            expected: 'das Haus',
          ),
        ],
        given: <int, String>{},
      ),
      more: <Override>[
        settingsProvider.overrideWithValue(settings),
        ttsProvider.overrideWithValue(FakeTts(spoken: spoken)),
      ],
    );
    for (var left = 3; left > 0; left--) {
      expect(find.text(l10n.examRunPlaysLeft(left)), findsOneWidget);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();
    }
    expect(find.text(l10n.examRunPlaysLeft(0)), findsOneWidget);
    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pumpAndSettle();
    expect(spoken, <String>['das Haus', 'das Haus', 'das Haus']);
  });
}
