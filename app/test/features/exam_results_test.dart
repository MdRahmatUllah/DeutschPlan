import 'dart:math' as math;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_results_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import 'exam_result_fixtures.dart';

/// L13 · Exam results — #135 (`exam-results.md`).
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late StubExamResult stub;
  late List<String> hub;
  late List<String> step;

  Future<void> pump(
    WidgetTester tester, {
    StubExamResult? with_,
    bool settle = true,
    int frames = 2,
  }) async {
    stub = with_ ?? StubExamResult();
    hub = <String>[];
    step = <String>[];
    tester.view
      ..physicalSize = const Size(390, 900) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...examResultStub(stub),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 20)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: ExamResultsScreen(
            attemptId: 7,
            onHub: hub.add,
            onStep: step.add,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The result's future and the frame that shows it, then one more.
      await tester.pump();
      if (frames > 1) await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  DpTokens tokens(WidgetTester tester) =>
      tester.element(find.byType(ExamResultsScreen)).tokens;

  testWidgets('FR-L13-01 a pass: Bestanden!, the score, the pass mark and '
      'the previous attempt', (tester) async {
    await pump(tester);
    expect(find.text(l10n.examResultPassed), findsOneWidget);
    expect(find.text(l10n.examResultPercent(77)), findsOneWidget);
    expect(find.text(l10n.examResultPoints('37', '48')), findsOneWidget);
    expect(find.text(l10n.examResultPassMark(60)), findsOneWidget);
    expect(
      find.text(
        '${l10n.examResultLine('A1.2', 2, '18:41')} · '
        '${l10n.examResultCompare('+7', 1, 62)}',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == tokens(tester).color.easy,
      ),
      findsWidgets,
      reason: 'on Lime',
    );
  });

  testWidgets('FR-L13-01 a fail: Noch nicht on Coral, and no comparison '
      'for a first attempt', (tester) async {
    await pump(
      tester,
      with_: StubExamResult(
        result: (
          attempt: resultAttempt(score: 25, passed: false),
          rows: artboardRows(),
          previous: null,
          passPercent: 60,
          missed: const <String>[],
        ),
      ),
    );
    expect(find.text(l10n.examResultFailed), findsOneWidget);
    expect(find.text(l10n.examResultPercent(52)), findsOneWidget);
    expect(find.text(l10n.examResultLine('A1.2', 2, '18:41')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == tokens(tester).color.again,
      ),
      findsWidgets,
      reason: 'on Coral',
    );
  });

  testWidgets('BR-EXAM-04 59.9 % reads 59 %, never the 60 % that passes', (
    tester,
  ) async {
    await pump(
      tester,
      with_: StubExamResult(
        result: (
          attempt: resultAttempt(score: 28.75, passed: false),
          rows: artboardRows(),
          previous: null,
          passPercent: 60,
          missed: const <String>[],
        ),
      ),
    );
    expect(find.text(l10n.examResultPercent(59)), findsOneWidget);
    expect(find.text(l10n.examResultPoints('28.8', '48')), findsOneWidget);
  });

  testWidgets('BR-EXAM-03 the sections in order, with their points', (
    tester,
  ) async {
    await pump(tester);
    final names = <String>[
      l10n.examSectionVocabulary,
      l10n.examSectionReverse,
      l10n.examSectionArticles,
      l10n.examSectionWordForms,
      l10n.examSectionGapFill,
      l10n.examSectionGrammar,
      l10n.examSectionListening,
      l10n.examSectionWriting,
      l10n.examSectionSpeaking,
    ];
    final ys = <double>[
      for (final name in names) tester.getTopLeft(find.text(name)).dy,
    ];
    expect(ys, List<double>.of(ys)..sort(), reason: 'in BR-EXAM-03 order');
    expect(find.text(l10n.examResultSectionPoints('8', 10)), findsOneWidget);
    expect(find.text(l10n.examResultSectionPoints('1', 2)), findsOneWidget);
    expect(find.text(l10n.examResultSelfAssessed), findsNWidgets(2));
  });

  testWidgets('FR-L13-02 the missed words go to revision, once', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.examResultAddMissed(9));
    expect(stub.added.single.$1, hasLength(9));
    expect(
      stub.added.single.$2,
      '2026-09-21',
      reason: 'the service adds a day',
    );
    expect(find.text(l10n.examResultAdded(9)), findsOneWidget);
    await tap(tester, l10n.examResultAddMissed(9));
    expect(stub.added, hasLength(1), reason: 'done once');
  });

  testWidgets('FR-L13-03 a Writing tick grades the paper again', (
    tester,
  ) async {
    await pump(tester);
    // Word forms, Writing and Speaking.
    expect(find.text(l10n.examResultSectionPoints('3', 4)), findsNWidgets(3));
    await tap(tester, l10n.examSectionWriting);
    expect(find.text(l10n.examWritingRubricTask), findsOneWidget);
    await tap(tester, l10n.examWritingRubricTask);
    expect(stub.rubrics.single.$1, 41);
    expect(stub.rubrics.single.$2, <bool>[true, false]);
    expect(find.text(l10n.examResultSectionPoints('3.5', 4)), findsOneWidget);
    expect(find.text(l10n.examResultPercent(78)), findsOneWidget);
  });

  testWidgets('Speaking opens its four ticks as the runner left them', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.examSectionSpeaking);
    expect(find.text(l10n.examSpeakingRubricVocabulary), findsOneWidget);
    expect(
      tester.getSemantics(find.text(l10n.examSpeakingRubricTask)),
      isSemantics(isChecked: true, hasCheckedState: true),
    );
  });

  testWidgets('close and Try another mock go to the hub, Back to step to '
      'L2, and Review answers to L14', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.bySemanticsLabel(l10n.examResultClose));
    await tap(tester, l10n.examResultAnotherMock);
    await tap(tester, l10n.examResultBackToStep);
    expect(hub, <String>['A1.2', 'A1.2']);
    expect(step, <String>['A1.2']);
    // #136: L14 in L13's place, and back.
    await tap(tester, l10n.examResultReview);
    expect(find.text(l10n.examReviewAll(40)), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.examResultPassed), findsOneWidget);
    semantics.dispose();
  });

  // The smallest scale over the badge: its own, whatever else is above.
  double badgeScale(WidgetTester tester) => <double>[
    for (final element
        in find
            .ancestor(
              of: find.text(l10n.examResultPassed),
              matching: find.byType(Transform),
            )
            .evaluate())
      (element.widget as Transform).transform.storage[0], // its x scale
  ].reduce(math.min);

  testWidgets('the badge scales in with one pulse', (tester) async {
    // Motion on, whatever the host's own setting says.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester, settle: false);
    expect(badgeScale(tester), lessThan(1), reason: 'on its way in');
    await tester.pumpAndSettle();
    expect(badgeScale(tester), 1);
  });

  testWidgets('with reduce motion the badge stands still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester, settle: false, frames: 1);
    expect(badgeScale(tester), 1, reason: 'at its first frame already');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('back is the close button: the exam hub, never L11', (
    tester,
  ) async {
    await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(hub, <String>['A1.2']);
  });

  testWidgets('FR-L13-03 no text: the Writing ticks are there but count '
      'nothing', (tester) async {
    final rows = <ExamResultRow>[
      for (final row in artboardRows())
        row.item is WritingTask
            ? (
                ord: row.ord,
                item: row.item,
                given: null,
                points: 0.0,
                rubric: row.rubric,
                flagged: false,
              )
            : row,
    ];
    await pump(
      tester,
      with_: StubExamResult(
        result: (
          attempt: resultAttempt(),
          rows: rows,
          previous: null,
          passPercent: 60,
          missed: const <String>[],
        ),
      ),
    );
    await tap(tester, l10n.examSectionWriting);
    expect(find.text(l10n.examResultRubricNoText), findsOneWidget);
    await tap(tester, l10n.examWritingRubricTask);
    expect(stub.rubrics, isEmpty);
  });

  testWidgets('FR-L12S-04 from L13: Delete recording, asked first', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.examSectionSpeaking);
    await tap(tester, l10n.examSpeakingDelete);
    expect(find.text(l10n.examResultDeleteTitle), findsOneWidget);
    await tap(tester, l10n.examResultDeleteKeep);
    expect(stub.deleted, isEmpty);
    await tap(tester, l10n.examSpeakingDelete);
    await tap(tester, l10n.examSpeakingDelete);
    expect(stub.deleted, <int>[42]);
    expect(find.text(l10n.examResultSectionPoints('0', 4)), findsOneWidget);
  });

  testWidgets('FR-L13-02 a failed add can be tried again', (tester) async {
    await pump(tester, with_: StubExamResult()..failAdd = true);
    await tap(tester, l10n.examResultAddMissed(9));
    expect(find.text(l10n.examResultAddFailed), findsOneWidget);
    stub.failAdd = false;
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tap(tester, l10n.examResultAddMissed(9));
    expect(stub.added, hasLength(1));
  });

  testWidgets('at 200 % text nothing is clipped', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    expectNothingClipped(tester);
  });

  testWidgets('an attempt that is not there says so', (tester) async {
    await pump(tester, with_: StubExamResult(missing: true));
    expect(find.text(l10n.examRunLoadFailed), findsOneWidget);
  });
}
