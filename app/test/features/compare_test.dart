import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/rating_service.dart'
    show CardMode;
import 'package:deutschplan/data/repositories/word_actions.dart';
import 'package:deutschplan/domain/compare_set.dart';
import 'package:deutschplan/features/study/study_back.dart'
    show StudyPlayButton;
import 'package:deutschplan/features/words/compare_screen.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import '../services/fake_tts.dart';
import 'compare_fixtures.dart';
import 'settings_fixtures.dart';
import 'word_fixtures.dart';

/// W2 · Compare words — #142, `compare.md`.
void main() {
  late AppLocalizations l10n;
  late FakeTts tts;
  late _Actions actions;
  QuizArgs? quiz;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(
    WidgetTester tester, {
    CompareView? view,
    Set<(String, String)> open = const <(String, String)>{},
    Size size = const Size(390, 844),
    double ratio = 3,
  }) async {
    quiz = null;
    tts = FakeTts();
    actions = _Actions();
    tester.view
      ..physicalSize = size * ratio
      ..devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const CompareScreen(uid: 'set-grund'),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) {
            quiz = state.extra as QuizArgs?;
            return const Scaffold(body: Text('L8'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          ...compareStub(view: view, open: open),
          ...settingsStub(),
          ...wordStub(),
          settingsProvider.overrideWithValue(StubSettings()),
          fakeVoice(tts),
          wordActionsProvider.overrideWithValue(actions),
          todayProvider.overrideWithValue('2026-09-21'),
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

  /// A member with nothing but its name.
  CompareMember bare(String headword) =>
      CompareMember(headword: headword, step: 'B2.1');

  group('FR-W2-01 the set', () {
    testWidgets('FR-W2-01 a column per member: article, headword, step', (
      tester,
    ) async {
      await pump(tester, size: const Size(1024, 768), ratio: 2);
      for (final name in <String>['der Grund', 'die Ursache', 'der Anlass']) {
        expect(find.text(name, findRichText: true), findsOneWidget);
      }
      expect(
        find.widgetWithText(DpChip, 'C1.1'),
        findsNWidgets(3),
        reason: 'a step chip under each',
      );
      expect(find.text(l10n.compareTitle), findsOneWidget);
      expect(find.text(l10n.compareSubtitleWide('C1.1')), findsOneWidget);
    });

    testWidgets('FR-W2-01 a header opens W1 for its word', (tester) async {
      await pump(tester);
      await tester.tap(find.text('die Ursache', findRichText: true));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
        'uid-ursache',
      );
    });

    testWidgets('FR-W2-01 a member the course has no word for opens nothing', (
      tester,
    ) async {
      await pump(
        tester,
        view: artboardCompare(members: <CompareMember>[bare('etwa')]),
      );
      await tester.tap(find.text('etwa', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
    });

    testWidgets('the header and the example say what they show', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel(l10n.wordPronounce('der Grund')));
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Aus diesem Grund bleibe ich zu Hause.'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(StudyPlayButton),
        ),
      );
      await tester.pump();
      expect(tts.spoken, <String>[
        'der Grund',
        'Aus diesem Grund bleibe ich zu Hause.',
      ]);
      expect(find.byType(WordDetailView), findsNothing, reason: 'played only');
    });
  });

  group('FR-W2-02 the cells', () {
    testWidgets('FR-W2-02 every row, its label and each member\'s cell', (
      tester,
    ) async {
      await pump(tester, size: const Size(1024, 768), ratio: 2);
      for (final label in <String>[
        l10n.compareMeaning,
        l10n.compareRegister,
        l10n.compareWith,
        l10n.compareExample,
        l10n.compareUseWhen,
      ]) {
        expect(find.text(label.toUpperCase()), findsOneWidget, reason: label);
      }
      expect(find.text('occasion, cause'), findsOneWidget);
      expect(find.text('formal'), findsOneWidget);
      expect(find.text('zu + Dat. · aus + Dat.'), findsOneWidget);
      expect(
        find.text('Aus Anlass des Jubiläums gab es ein Fest.'),
        findsOneWidget,
      );
      expect(
        find.text('the trigger or occasion for an action'),
        findsOneWidget,
      );
      expect(find.text(CompareTable.missing), findsNothing);
    });

    testWidgets('FR-W2-02 a cell the course leaves empty shows "—"', (
      tester,
    ) async {
      await pump(
        tester,
        view: artboardCompare(
          members: <CompareMember>[
            const CompareMember(
              headword: 'rund',
              step: 'A1.2',
              meaning: 'round',
            ),
            bare('etwa'),
          ],
        ),
      );
      // Register, with, example, use it when for rund; all five for etwa.
      expect(find.text(CompareTable.missing), findsNWidgets(4 + 5));
      expect(find.bySemanticsLabel(l10n.studyPlaySentence), findsNothing);
    });
  });

  group('FR-W2-03 Quiz these', () {
    testWidgets('FR-W2-03 a 5-item compare quiz of this set', (tester) async {
      await pump(tester);
      await tester.tap(find.text(l10n.compareQuiz(5)));
      await tester.pumpAndSettle();
      expect(quiz, isNotNull);
      expect(
        (quiz!.direction, quiz!.source, quiz!.sourceRef, quiz!.length),
        ('compare', 'compareSet', 'set-grund', 5),
      );
    });

    testWidgets('FR-W2-03 closed when no sentence names a member', (
      tester,
    ) async {
      await pump(tester, view: artboardCompare(quizItems: 0));
      final button = tester.widget<DpButton>(
        find.widgetWithText(DpButton, l10n.compareQuiz(0)),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Add all to today', () {
    testWidgets('FR-W1-01 every member To do joins today, then a toast', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(l10n.compareAddAll(3)));
      await tester.pumpAndSettle();
      expect(actions.added, <String>[
        'uid-grund C1.1 2026-09-21',
        'uid-ursache C1.1 2026-09-21',
        'uid-anlass C1.1 2026-09-21',
      ]);
      expect(find.text(l10n.compareAdded(3)), findsOneWidget);
      expect(actions.undone, isEmpty);
    });

    testWidgets('FR-W1-04 one Undo takes them all back out', (tester) async {
      await pump(tester);
      await tester.tap(find.text(l10n.compareAddAll(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(actions.undone, <String>[
        'uid-anlass',
        'uid-ursache',
        'uid-grund',
      ]);
    });

    testWidgets('one already in today\'s plan is not counted', (tester) async {
      await pump(tester, open: const <(String, String)>{('new', 'uid-grund')});
      await tester.tap(find.text(l10n.compareAddAll(2)));
      await tester.pumpAndSettle();
      expect(actions.added.map((a) => a.split(' ').first), <String>[
        'uid-ursache',
        'uid-anlass',
      ]);
    });

    testWidgets('nothing To do: no button', (tester) async {
      await pump(tester, view: artboardCompare(todo: const []));
      expect(
        find.widgetWithText(DpButton, l10n.compareAddAll(3)),
        findsNothing,
      );
      expect(find.byType(DpButton), findsOneWidget, reason: 'Quiz these only');
    });
  });

  group('FR-W2-04 the pinned column', () {
    testWidgets('FR-W2-04 on a phone the members scroll, the labels stay', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10n.compareDrag('Anlass')), findsOneWidget);
      expect(find.text(l10n.compareSubtitle('C1.1')), findsOneWidget);
      final label = find.text(l10n.compareMeaning.toUpperCase());
      final cell = find.text('reason, ground');
      final labelAt = tester.getTopLeft(label);
      final cellAt = tester.getTopLeft(cell);

      await tester.drag(cell, const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(label), labelAt, reason: 'pinned');
      expect(tester.getTopLeft(cell).dx, lessThan(cellAt.dx - 100));
      // The label is on top: a tap where it sits finds it, not the cell
      // scrolled under it.
      expect(label.hitTestable(), findsOneWidget);
    });

    testWidgets('FR-W2-04 a tablet shows every column, and no hint', (
      tester,
    ) async {
      await pump(tester, size: const Size(1024, 768), ratio: 2);
      for (final name in <String>['der Grund', 'die Ursache', 'der Anlass']) {
        final right = tester.getTopRight(find.text(name, findRichText: true));
        expect(right.dx, lessThan(1024 - 16), reason: name);
      }
      expect(find.text(l10n.compareDrag('Anlass')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CompareTable),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    testWidgets('FR-W2-04 a screen reader reads a row label first, then the '
        'members left to right', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final read = <String>[
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          node.label,
      ];
      int at(String label) => read.indexWhere((l) => l.startsWith(label));
      final order = <int>[
        at('der Grund'),
        at('die Ursache'),
        at('der Anlass'),
        at(l10n.compareMeaning.toUpperCase()),
        at('reason, ground'),
        at('cause'),
        at('occasion, cause'),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)), reason: '$read');
      expect(order, List<int>.of(order)..sort(), reason: '$read');
      semantics.dispose();
    });

    testWidgets('#314 nothing is cut at 200 % text', (tester) async {
      textAt(tester, 2);
      await pump(tester);
      expectNothingClipped(tester, within: find.byType(CompareScreen));
    });
  });
}

class _Actions implements WordActions {
  final List<String> added = <String>[];

  /// The uids whose add was undone, in the order it was.
  final List<String> undone = <String>[];

  @override
  Future<Undo> addToToday(
    String uid, {
    required String today,
    required String step,
  }) async {
    added.add('$uid $step $today');
    return () async => undone.add(uid);
  }

  @override
  Future<Undo> markKnown(String uid, {required String today}) =>
      throw UnimplementedError();

  @override
  Future<Undo> suspend(String uid, {required String today}) =>
      throw UnimplementedError();

  @override
  Future<Undo> resume(String uid) => throw UnimplementedError();

  @override
  Future<Undo> reset(String uid, {required String today}) =>
      throw UnimplementedError();

  @override
  Future<Undo> setCardMode(String uid, CardMode mode) =>
      throw UnimplementedError();
}
