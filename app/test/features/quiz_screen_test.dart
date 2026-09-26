import 'dart:async';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/quiz/quiz_result_screen.dart';
import 'package:deutschplan/features/quiz/quiz_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart' show AndroidTextScaler;
import 'quiz_fixtures.dart';

/// L8 · Quiz runner — #123.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const standard = QuizArgs(
    direction: 'deEn',
    source: 'stepLearned',
    sourceRef: 'A2.1',
    seed: 7,
    length: 20,
  );

  Quiz quizOf(List<QuizItem> items) => Quiz(
    direction: QuizDirection.deEn,
    source: QuizSource.allLearned,
    seed: 1,
    items: items,
  );

  const haus = QuizItem(
    ord: 1,
    wordUid: 'haus',
    direction: QuizDirection.deEn,
    prompt: 'das Haus',
    expected: 'house',
  );
  const vertrag = QuizItem(
    ord: 2,
    wordUid: 'vertrag',
    direction: QuizDirection.enDe,
    prompt: 'rental contract, lease',
    expected: 'der Mietvertrag',
  );

  late StubQuizRun run;

  Future<void> pump(
    WidgetTester tester, {
    QuizArgs args = standard,
    StubQuizRun? stub,
    TextScaler? textScaler,
  }) async {
    run = stub ?? StubQuizRun();
    final routes = GoRouter(
      initialLocation: '/opener',
      routes: <RouteBase>[
        GoRoute(
          path: '/opener',
          builder: (_, _) => const Scaffold(body: Text('opener')),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) => QuizScreen(args: state.extra! as QuizArgs),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          todayProvider.overrideWithValue('2026-09-21'),
          ...quizStub(run),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
        ),
      ),
    );
    unawaited(routes.push('/quiz', extra: args));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.text(l10n.quizCheck));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text(l10n.practiceNext));
    await tester.pumpAndSettle();
  }

  Finder close() => find.bySemanticsLabel(l10n.quizClose);

  String field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('FR-L8-01 the quiz is built from its args, seed and all', (
    tester,
  ) async {
    await pump(tester);
    expect(run.started, [
      (QuizDirection.deEn, QuizSource.stepLearned, 'A2.1', 20, 7),
    ]);
  });

  testWidgets('the top bar: the title, the counter; the item and its ask', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Standard · DE → EN'), findsOneWidget);
    expect(find.text('1 / 20'), findsOneWidget);
    expect(find.text(l10n.quizAskMeaning), findsOneWidget);
    expect(find.text('das Wort1'), findsOneWidget);
  });

  testWidgets('Check waits for an answer', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.quizCheck));
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(run.answers, isEmpty);
    expect(find.text(l10n.quizCorrect), findsNothing);
  });

  testWidgets('FR-L8-02 answers are graded and persisted per item', (
    tester,
  ) async {
    await pump(tester);
    await answer(tester, 'word 1');
    expect(find.text(l10n.quizCorrect), findsOneWidget);
    expect(run.answers, [(1, 'word 1', Verdict.correct)]);

    await next(tester);
    expect(find.text('2 / 20'), findsOneWidget);
    expect(find.text('das Wort2'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'each item starts with an empty field',
    );

    // The keyboard's done key checks too.
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(l10n.quizAnswerIs('word 2')), findsOneWidget);
    expect(run.answers.last, (2, 'nope', Verdict.wrong));
  });

  testWidgets('almost: "watch the spelling" with the answer', (tester) async {
    await pump(tester, stub: StubQuizRun(quiz: artboardQuiz()));
    for (var i = 1; i < 7; i++) {
      await answer(tester, 'x');
      await next(tester);
    }
    expect(find.text('7 / 20'), findsOneWidget);
    expect(find.text(l10n.quizAskGerman), findsOneWidget);
    await answer(tester, 'der Mietvertag');
    expect(find.text(l10n.quizAlmost('der Mietvertrag')), findsOneWidget);
    expect(run.answers.last, (7, 'der Mietvertag', Verdict.almost));
  });

  testWidgets('the last answer finishes the run, scored, and shows L9', (
    tester,
  ) async {
    await pump(
      tester,
      stub: StubQuizRun(quiz: quizOf(<QuizItem>[haus, vertrag])),
    );
    await answer(tester, 'house');
    await next(tester);
    await answer(tester, 'der Mietvertag');
    expect(run.finished, isNull);
    await next(tester);

    // FR-L8-03: the almost is asked once more at the end, unscored.
    expect(find.text(l10n.quizOnceMore), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('rental contract, lease'), findsOneWidget);
    await answer(tester, 'der Mietvertrag');
    expect(run.again, [2]);
    expect(run.answers, hasLength(2), reason: 'the first answer stands');
    expect(run.finished, isNull);

    await next(tester);
    expect(run.finished, 1.5, reason: 'correct 1 + almost 0.5, not the re-ask');
    expect(find.byType(QuizResultView), findsOneWidget);

    await tester.tap(find.text(l10n.done));
    await tester.pumpAndSettle();
    expect(find.text('opener'), findsOneWidget);
  });

  group('FR-L8-04 closing asks first', () {
    testWidgets('Keep going stays; Stop leaves', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await answer(tester, 'word 1');

      await tester.tap(close());
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsOneWidget);
      expect(find.text(l10n.quizStopBody), findsOneWidget);
      await tester.tap(find.text(l10n.quizKeepGoing));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);

      await tester.tap(close());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.quizStop));
      await tester.pumpAndSettle();
      expect(find.text('opener'), findsOneWidget);
      expect(run.answers, hasLength(1), reason: 'what was answered stays');
      expect(run.finished, isNull);
      semantics.dispose();
    });

    testWidgets('back asks as close does', (tester) async {
      await pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsOneWidget);
      expect(find.byType(QuizScreen), findsOneWidget);
    });

    testWidgets('an empty quiz says so and closes without asking', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, stub: StubQuizRun(quiz: quizOf(const <QuizItem>[])));
      expect(find.text(l10n.quizEmpty), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      await tester.tap(close());
      await tester.pumpAndSettle();
      expect(find.text(l10n.quizStopTitle), findsNothing);
      expect(find.text('opener'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('FR-L8-05 the timer', () {
    const timed = QuizArgs(
      direction: 'deEn',
      source: 'stepLearned',
      sourceRef: 'A2.1',
      seed: 7,
      length: 20,
      timer: true,
    );

    testWidgets('auto-submits an empty answer as wrong at 0', (tester) async {
      await pump(tester, args: timed);
      expect(find.text(l10n.quizSecondsLeft(15)), findsOneWidget);
      await tester.pump(const Duration(seconds: 14));
      expect(find.text(l10n.quizSecondsLeft(1)), findsOneWidget);
      expect(run.answers, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, '', Verdict.wrong)]);
      expect(find.text(l10n.quizTimeUp('word 1')), findsOneWidget);
      expect(find.text(l10n.quizSecondsLeft(0)), findsNothing);

      await next(tester);
      expect(
        find.text(l10n.quizSecondsLeft(15)),
        findsOneWidget,
        reason: 'each question has its own 15 s',
      );
    });

    testWidgets(
      'FR-L8-04 the clock stops under the Stop dialog, and Keep going '
      'carries on from the seconds left',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, args: timed);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text(l10n.quizSecondsLeft(10)), findsOneWidget);

        await tester.tap(close());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 20));
        expect(run.answers, isEmpty, reason: 'no time runs out under it');

        await tester.tap(find.text(l10n.quizKeepGoing));
        await tester.pumpAndSettle();
        expect(find.text(l10n.quizSecondsLeft(10)), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(run.answers, [(1, '', Verdict.wrong)]);
        semantics.dispose();
      },
    );

    testWidgets('an answer in time stops the clock', (tester) async {
      await pump(tester, args: timed);
      await tester.pump(const Duration(seconds: 5));
      await answer(tester, 'word 1');
      await tester.pump(const Duration(seconds: 20));
      expect(run.answers, [(1, 'word 1', Verdict.correct)]);
    });

    testWidgets('off: no clock, and nothing is sent for you', (tester) async {
      await pump(tester);
      expect(find.text(l10n.quizSecondsLeft(15)), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(run.answers, isEmpty);
    });
  });

  testWidgets('a quiz that could not be built offers a retry', (tester) async {
    await pump(tester, stub: StubQuizRun(error: StateError('no db')));
    expect(find.text(l10n.quizLoadFailed), findsOneWidget);
    run.error = null;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('das Wort1'), findsOneWidget);
    expect(run.started, hasLength(2));
  });

  testWidgets('a forms item names its form; listening plays, not shows', (
    tester,
  ) async {
    await pump(
      tester,
      args: const QuizArgs(direction: 'mixed', source: 'allLearned', seed: 1),
      stub: StubQuizRun(
        quiz: quizOf(<QuizItem>[
          const QuizItem(
            ord: 1,
            wordUid: 'arbeiten',
            direction: QuizDirection.forms,
            prompt: 'arbeiten',
            expected: 'hat gearbeitet',
            form: FormLabel.perfekt,
          ),
          const QuizItem(
            ord: 2,
            wordUid: 'haus',
            direction: QuizDirection.listening,
            prompt: 'das Haus',
            expected: 'das Haus',
          ),
        ]),
      ),
    );
    expect(find.text(l10n.quizFormPerfekt('arbeiten')), findsOneWidget);
    expect(find.text(l10n.quizAskForm), findsOneWidget);
    await answer(tester, 'hat gearbeitet');
    expect(find.text(l10n.quizCorrect), findsOneWidget);

    await next(tester);
    expect(find.text(l10n.quizAskListening), findsOneWidget);
    expect(find.byType(DpSpeakerButton), findsOneWidget);
    expect(find.text('das Haus'), findsNothing);
  });

  group('the item layouts', () {
    Future<void> one(WidgetTester tester, QuizItem item) => pump(
      tester,
      args: const QuizArgs(direction: 'mixed', source: 'allLearned', seed: 1),
      stub: StubQuizRun(quiz: quizOf(<QuizItem>[item, haus])),
    );

    testWidgets('DE → বাংলা: four tiles, and a tap answers', (tester) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'haus',
          direction: QuizDirection.deBn,
          prompt: 'das Haus',
          expected: 'বাড়ি',
          options: <String>['গাড়ি', 'বাড়ি', 'দরজা', 'রাস্তা'],
        ),
      );
      expect(find.text(l10n.quizAskPick), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(l10n.quizCheck), findsNothing, reason: 'a tap answers');
      await tester.tap(find.text('দরজা'));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, 'দরজা', Verdict.wrong)]);
      expect(find.text(l10n.quizAnswerIs('বাড়ি')), findsOneWidget);
      // #539: a Bangla answer in its own voice, not German's.
      expect(
        tester.widget<DpVerdictRow>(find.byType(DpVerdictRow)).germanEmphasis,
        isFalse,
      );
      bool selected(String tile) => tester
          .widget<DpSurface>(
            find
                .ancestor(of: find.text(tile), matching: find.byType(DpSurface))
                .first,
          )
          .selected;
      expect((selected('দরজা'), selected('গাড়ি')), (true, false));

      await tester.tap(find.text('বাড়ি'));
      await tester.pumpAndSettle();
      expect(run.answers, hasLength(1), reason: 'graded once');
    });

    testWidgets('FR-W2-03 compare: the gapped sentence, its English, the '
        "set's tiles", (tester) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'uid-grund',
          direction: QuizDirection.compare,
          prompt: 'Aus diesem ___ bleibe ich zu Hause.',
          expected: 'Grund',
          options: <String>['Anlass', 'Grund', 'Ursache'],
          hint: "For this reason I'm staying at home.",
        ),
      );
      expect(find.text(l10n.quizAskCompare), findsOneWidget);
      expect(find.text('Aus diesem ___ bleibe ich zu Hause.'), findsOneWidget);
      expect(find.text("For this reason I'm staying at home."), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'tiles');
      await tester.tap(find.text('Grund'));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, 'Grund', Verdict.correct)]);
    });

    testWidgets('articles: der, die, das, and a tap answers', (tester) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'tuer',
          direction: QuizDirection.articles,
          prompt: 'Tür',
          expected: 'die',
        ),
      );
      expect(find.text(l10n.quizAskArticle), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final xs = [
        for (final a in <String>['der', 'die', 'das'])
          tester.getCenter(find.text(a)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()), reason: 'der, die, das');
      await tester.tap(find.text('die'));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, 'die', Verdict.correct)]);
      expect(find.text(l10n.quizCorrect), findsOneWidget);
    });

    testWidgets('BR-ANS-02 a right noun under the wrong article names both', (
      tester,
    ) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'vertrag',
          direction: QuizDirection.enDe,
          prompt: 'rental contract, lease',
          expected: 'der Mietvertrag',
          hint: 'ভাড়ার চুক্তি',
        ),
      );
      await answer(tester, 'Die Mietvertrag');
      expect(find.text(l10n.quizArticleWrong('der', 'die')), findsOneWidget);
      expect(run.answers, [(1, 'Die Mietvertrag', Verdict.wrongArticle)]);
    });

    testWidgets('EN → DE: the Bangla line under it, and the umlaut row', (
      tester,
    ) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'tuer',
          direction: QuizDirection.enDe,
          prompt: 'door',
          expected: 'die Tür',
          hint: 'দরজা',
        ),
      );
      expect(find.text('দরজা'), findsOneWidget);
      expect(find.byType(DpUmlautBar), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'die T');
      await tester.tap(find.text('ü'));
      await tester.enterText(find.byType(TextField), '${field(tester)}r');
      await tester.pump();
      await tester.tap(find.text(l10n.quizCheck));
      await tester.pumpAndSettle();
      expect(run.answers, [(1, 'die Tür', Verdict.correct)]);
    });

    testWidgets('a meaning is typed without the umlaut row', (tester) async {
      await one(tester, haus);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(DpUmlautBar), findsNothing);
      expect(find.byType(DpSpeakerButton), findsOneWidget, reason: 'play');
    });

    testWidgets('almost: the answer is set apart in ink', (tester) async {
      await one(
        tester,
        const QuizItem(
          ord: 1,
          wordUid: 'vertrag',
          direction: QuizDirection.enDe,
          prompt: 'rental contract, lease',
          expected: 'der Mietvertrag',
        ),
      );
      await answer(tester, 'der Mietvertag');
      final row = tester.widget<DpVerdictRow>(find.byType(DpVerdictRow));
      expect(row.emphasis, <String>['der Mietvertrag']);
      // #539: a German answer, read in a German voice.
      expect(row.germanEmphasis, isTrue);

      // Its speaker is drawn small and tapped at 48 dp.
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final node = tester.getSemantics(find.bySemanticsLabel(l10n.quizPlay));
      expect(node.rect.width, greaterThanOrEqualTo(48));
      expect(node.rect.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });
  });

  group('L8 #554 typing at large text', () {
    const keyboardTop = 731.0 - 300;

    // #561: a prompt that wraps, and one whose Bangla hint is its second
    // line (the meaning language Both), as SQA found them on 5556.
    const wraps = QuizItem(
      ord: 1,
      wordUid: 'bitte',
      direction: QuizDirection.enDe,
      prompt: "here you are / you're welcome",
      expected: 'bitte',
    );
    const withHint = QuizItem(
      ord: 1,
      wordUid: 'wiedersehen',
      direction: QuizDirection.enDe,
      prompt: 'goodbye',
      expected: 'Auf Wiedersehen',
      hint: 'বিদায় (আনুষ্ঠানিক)',
    );

    // SQA's 731 dp phone, its status bar, and a 300 dp keyboard.
    Future<void> typing(
      WidgetTester tester,
      QuizItem item, {
      required TextScaler textScaler,
      double width = 390,
      double keyboard = 300,
    }) async {
      tester.view
        ..physicalSize = Size(width, 731) * 3
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: 24 * 3);
      addTearDown(tester.view.reset);
      await pump(
        tester,
        args: const QuizArgs(direction: 'mixed', source: 'allLearned', seed: 1),
        stub: StubQuizRun(quiz: quizOf(<QuizItem>[item, haus])),
        textScaler: textScaler,
      );
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
      await tester.pumpAndSettle();
    }

    // #561: on SQA's 5556 (1080 × 1920 at 420 dpi: 411 × 731 dp) Gboard
    // left about 7 dp less than the prompt, its gap and the field need (a
    // keyboard of about 330 dp here), and a two-line prompt lost the top of
    // its first line under the progress strip. While typing past 130 % the
    // prompt's gap to the field and the list's foot give 12 and 8 dp back;
    // at 335 dp both are needed.
    for (final item in <QuizItem>[wraps, withHint]) {
      testWidgets('#561 ${item.wordUid}: at 200 % on a 411 dp phone with a '
          'taller keyboard, both lines of the prompt show whole above the '
          'field', (tester) async {
        await typing(
          tester,
          item,
          textScaler: AndroidTextScaler(2),
          width: 411,
          keyboard: 335,
        );
        final room = tester.getRect(find.byType(ListView));
        final lines = <Finder>[
          find.text(item.prompt),
          if (item.hint case final hint?) find.text(hint),
        ];
        for (final line in lines) {
          expect(
            tester.getRect(line).top,
            greaterThanOrEqualTo(room.top),
            reason: 'line ${lines.indexOf(line) + 1} is under the strip',
          );
        }
        expect(
          tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(room.bottom),
          reason: 'the field shows whole',
        );
      });
    }

    for (final item in <QuizItem>[
      const QuizItem(
        ord: 1,
        wordUid: 'sorry',
        direction: QuizDirection.enDe,
        prompt: "I'm sorry",
        expected: 'Es tut mir leid',
        hint: 'আমি দুঃখিত',
      ),
      wraps,
      withHint,
      const QuizItem(
        ord: 1,
        wordUid: 'benehmen',
        direction: QuizDirection.forms,
        prompt: 'sich benehmen',
        expected: 'hat sich benommen',
        form: FormLabel.perfekt,
      ),
    ]) {
      for (final percent in <int>[200, 150]) {
        testWidgets('${item.direction.name}: at $percent % with the keyboard '
            'up, the prompt shows whole above the field, with Check and the '
            "umlaut row; the header and caption come back with the keyboard's "
            'going', (tester) async {
          await typing(
            tester,
            item,
            textScaler: AndroidTextScaler(percent / 100),
          );
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
            reason: 'the field kept the keyboard',
          );
          expect(close(), findsNothing, reason: 'the header gave its row');
          final prompt = find.text(
            item.form == null ? item.prompt : l10n.quizFormPerfekt(item.prompt),
          );
          // What the list shows: under the status bar, above Check.
          final room = tester.getRect(find.byType(ListView));
          expect(room.bottom, lessThanOrEqualTo(keyboardTop));
          for (final (name, shown) in <(String, Finder)>[
            ('the prompt', prompt),
            ('the field', find.byType(TextField)),
          ]) {
            final rect = tester.getRect(shown);
            expect(rect.top, greaterThanOrEqualTo(room.top), reason: name);
            expect(rect.bottom, lessThanOrEqualTo(room.bottom), reason: name);
          }
          expect(
            tester
                .getRect(find.widgetWithText(DpButton, l10n.quizCheck))
                .bottom,
            lessThanOrEqualTo(keyboardTop),
          );
          expect(
            tester.getRect(find.byType(DpUmlautBar)).bottom,
            lessThanOrEqualTo(keyboardTop),
          );

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(close(), findsOneWidget, reason: 'the header row');
          expect(find.text(l10n.quizYourAnswer.toUpperCase()), findsOneWidget);
        });
      }
    }

    testWidgets('at 100 % the keyboard leaves the header and caption be', (
      tester,
    ) async {
      await typing(tester, vertrag, textScaler: TextScaler.noScaling);
      expect(close(), findsOneWidget, reason: 'the header row');
      expect(find.text(l10n.quizYourAnswer.toUpperCase()), findsOneWidget);
    });
  });

  test('the title: the length names the kind; Forms is Forms', () {
    QuizArgs args(String direction, int length) =>
        QuizArgs(direction: direction, source: 'x', seed: 0, length: length);
    expect(quizTitle(l10n, args('deEn', 20)), 'Standard · DE → EN');
    expect(quizTitle(l10n, args('deBn', 10)), 'Quick · DE → বাংলা');
    expect(quizTitle(l10n, args('enDe', 30)), 'Long · EN → DE');
    expect(quizTitle(l10n, args('mixed', 15)), 'Custom · Mixed');
    expect(quizTitle(l10n, args('forms', 20)), l10n.quizForms);
    expect(quizTitle(l10n, args('compare', 5)), l10n.quizDirectionCompare);
  });
}
