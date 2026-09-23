@TestOn('vm')
library;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/placement_test.dart' show wordFor;

/// S3 · the placement check on screen — #93. The walk itself is
/// `placement_test.dart`'s; this is the screen around it.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const steps = <String>[
    'A1.1', 'A1.2', 'A2.1', 'A2.2', 'B1.1', 'B1.2', //
    'B2.1', 'B2.2', 'C1.1', 'C1.2', 'C2.1', 'C2.2',
  ];

  late _PoolDao dao;
  late List<String?> done;
  late AppDatabase db;

  Future<void> pump(
    WidgetTester tester, {
    DpMode mode = DpMode.light,
    double textScale = 1,
    MeaningLanguage meaning = MeaningLanguage.english,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = AppDatabase.memory();
    addTearDown(db.close);
    dao = _PoolDao(db);
    done = <String?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          contentDaoProvider.overrideWithValue(dao),
          courseStepsProvider.overrideWith(
            (ref) async => <CourseStep>[
              for (final code in steps)
                (code: code, levelCode: code.split('.').first, wordCount: 12),
            ],
          ),
          systemTtsProvider.overrideWithValue(_SilentTts()),
          languagesProvider.overrideWith(() => _FixedLanguages(meaning)),
        ],
        child: MaterialApp(
          theme: switch (mode) {
            DpMode.light => AppTheme.light(),
            DpMode.dark => AppTheme.dark(),
            DpMode.glass => AppTheme.glass(),
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: PlacementScreen(seed: 11, onDone: done.add),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Finder options() => find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(DpSurface),
  );

  /// Picks the right option when [right], a wrong one otherwise, and moves
  /// on — the screen's own answer, read off the item it drew.
  Future<void> answer(WidgetTester tester, {required bool right}) async {
    final item = tester
        .state<PlacementScreenState>(find.byType(PlacementScreen))
        .currentItem!;
    final index = right ? item.answer : (item.answer + 1) % item.options.length;

    await tester.tap(options().at(index));
    await tester.pump();
    await tester.tap(find.widgetWithText(DpButton, l10n.placementNext));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  /// A check that settles on A2.2 after nine answers.
  Future<void> finish(WidgetTester tester, {DpMode mode = DpMode.light}) async {
    await pump(tester, mode: mode);
    for (final right in <bool>[
      true, true, true, true, true, true, true, false, true, //
    ]) {
      await answer(tester, right: right);
    }
  }

  group('the check', () {
    testWidgets('starts at A1.1, question 1 of 20', (tester) async {
      await pump(tester);

      expect(find.text(l10n.placementQuestionOf(1, 20)), findsOneWidget);
      expect(dao.asked.first, 'A1.1');
      expect(options(), findsWidgets);
    });

    testWidgets('Next waits for an answer', (tester) async {
      await pump(tester);

      final next = find.widgetWithText(DpButton, l10n.placementNext);
      expect(tester.widget<DpButton>(next).onPressed, isNull);

      await tester.tap(options().first);
      await tester.pump();
      expect(tester.widget<DpButton>(next).onPressed, isNotNull);
    });

    testWidgets('FR-S3-01 two right move it up a step', (tester) async {
      await pump(tester);

      await answer(tester, right: true);
      await answer(tester, right: true);

      expect(find.text(l10n.placementQuestionOf(3, 20)), findsOneWidget);
      expect(dao.asked.last, 'A1.2');
    });

    testWidgets('and it ends on the step it settled on', (tester) async {
      // Six right climb to A2.2; then right, wrong, right hold it there for
      // three, and after the ninth the check stops — on the result.
      await finish(tester);

      expect(find.text('A2.2'), findsOneWidget);
      expect(done, isEmpty, reason: 'the result waits for a choice');
    });

    testWidgets('FR-S3-02 each step is read once, however often it returns', (
      tester,
    ) async {
      await pump(tester);
      // Up to A1.2 and back down to A1.1.
      await answer(tester, right: true);
      await answer(tester, right: true);
      await answer(tester, right: false);
      await answer(tester, right: false);
      await answer(tester, right: true);

      expect(dao.asked.where((s) => s == 'A1.1'), hasLength(1));
    });
  });

  group('#94 the result', () {
    testWidgets('says the score, the step and why', (tester) async {
      await finish(tester);

      expect(find.text(l10n.placementResultTitle), findsOneWidget);
      expect(find.text(l10n.placementScore(8, 9)), findsOneWidget);
      expect(find.text(l10n.placementSuggest.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.placementRationale('A2.2')), findsOneWidget);
    });

    testWidgets("breaks it down by the session's own items", (tester) async {
      // Nine items: A1 had the first four, A2 the other five — word items by
      // level, and the article items apart, whatever step they were at.
      await finish(tester);
      final state = tester.state<PlacementScreenState>(
        find.byType(PlacementScreen),
      );
      final areas = state.currentResult!.areas;

      expect(areas.fold(0, (sum, a) => sum + a.total), 9);
      for (final area in areas) {
        final label = area.area == PlacementSession.articles
            ? l10n.placementAreaArticles(area.correct, area.total)
            : l10n.placementAreaWords(area.area, area.correct, area.total);
        expect(find.text(label), findsOneWidget, reason: area.area);
      }
    });

    testWidgets('and colours an area Lime from nine in ten, Sun below', (
      tester,
    ) async {
      await finish(tester);
      final tokens = tester.element(find.byType(PlacementScreen)).tokens;
      final areas = tester
          .state<PlacementScreenState>(find.byType(PlacementScreen))
          .currentResult!
          .areas;

      for (final area in areas) {
        final label = area.area == PlacementSession.articles
            ? l10n.placementAreaArticles(area.correct, area.total)
            : l10n.placementAreaWords(area.area, area.correct, area.total);
        final pill = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        final fill = (pill.decoration! as BoxDecoration).color;
        expect(
          fill,
          area.correct / area.total >= 0.9
              ? tokens.color.easy
              : tokens.color.accent,
          reason: '${area.area} ${area.correct}/${area.total}',
        );
      }
    });

    for (final mode in <DpMode>[DpMode.light, DpMode.glass]) {
      testWidgets("draws the ${mode.name} artboard's card and pills", (
        tester,
      ) async {
        // Paper: a 2 px ink card, pills edged in ink. Glass: a plain panel,
        // pills edged like it — a selected glass card would ring in Lagoon.
        await finish(tester, mode: mode);
        final tokens = tester.element(find.byType(PlacementScreen)).tokens;
        final glass = mode == DpMode.glass;

        final card = tester.widget<DpSurface>(
          find
              .ancestor(
                of: find.text(l10n.placementRationale('A2.2')),
                matching: find.byType(DpSurface),
              )
              .first,
        );
        expect(card.selected, !glass);

        BoxDecoration pill(String label) =>
            tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        final score = pill(l10n.placementScore(8, 9));
        final articles = tester
            .state<PlacementScreenState>(find.byType(PlacementScreen))
            .currentResult!
            .areas
            .singleWhere((a) => a.area == PlacementSession.articles);
        final area = pill(
          l10n.placementAreaArticles(articles.correct, articles.total),
        );
        expect(
          (score.border! as Border).top.color,
          glass ? tokens.surface.outline : tokens.color.ink,
        );
        expect(
          (area.border! as Border).top.color,
          (score.border! as Border).top.color,
        );
        // The score pill is the artboard's smaller one.
        expect(score.borderRadius, BorderRadius.circular(8));
        expect(area.borderRadius, BorderRadius.circular(14));
      });
    }

    test("Lime is the artboard's 9 / 10 and 5 / 5; its 4 / 5 is Sun", () {
      expect(PlacementResultView.strong(9, 10), isTrue);
      expect(PlacementResultView.strong(5, 5), isTrue);
      expect(PlacementResultView.strong(4, 5), isFalse);
      expect(PlacementResultView.strong(0, 0), isFalse, reason: 'no items');
    });

    testWidgets('BR-COURSE-04 says the steps skipped stay browsable', (
      tester,
    ) async {
      await finish(tester);

      expect(find.text(l10n.placementBrowsable), findsOneWidget);
    });

    testWidgets('FR-S3-03 Use takes the step back to page 3', (tester) async {
      await finish(tester);

      await tester.tap(find.text(l10n.placementUse('A2.2')));
      await tester.pump();

      expect(done, <String?>['A2.2']);
    });

    testWidgets('FR-S3-04 Choose myself takes nothing back', (tester) async {
      await finish(tester);
      await tester.tap(find.text(l10n.placementChooseMyself));
      await tester.pump();
      expect(done, <String?>[null]);
    });

    testWidgets('and nor does closing the result', (tester) async {
      await finish(tester);
      await tester.tap(find.bySemanticsLabel(l10n.placementClose));
      await tester.pump();
      expect(done, <String?>[null]);
    });
  });

  group('the meanings', () {
    testWidgets('are in the language page 2 chose', (tester) async {
      // A learner who reads meanings in Bangla, tested on their English,
      // would place below their German.
      await pump(tester, meaning: MeaningLanguage.bangla);

      final item = tester
          .state<PlacementScreenState>(find.byType(PlacementScreen))
          .currentItem!;
      expect(item.kind, PlacementKind.meaning);
      expect(find.text(item.word.bangla!), findsOneWidget);
      expect(find.text(item.word.english), findsNothing);
    });

    testWidgets('and in English otherwise', (tester) async {
      await pump(tester);

      final item = tester
          .state<PlacementScreenState>(find.byType(PlacementScreen))
          .currentItem!;
      expect(find.text(item.word.english), findsOneWidget);
    });
  });

  group('Next', () {
    testWidgets('twice in one frame answers once', (tester) async {
      await pump(tester);
      final state = tester.state<PlacementScreenState>(
        find.byType(PlacementScreen),
      );

      await tester.tap(options().first);
      await tester.pump();
      final next = find.widgetWithText(DpButton, l10n.placementNext);
      await tester.tap(next);
      await tester.tap(next);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // One answer: question 2, not 3.
      expect(find.text(l10n.placementQuestionOf(2, 20)), findsOneWidget);
      expect(state.currentItem, isNotNull);
    });
  });

  group('FR-S3-04 closing', () {
    testWidgets('hands back nothing, however far in', (tester) async {
      await pump(tester);
      await answer(tester, right: true);
      await answer(tester, right: true);

      await tester.tap(find.bySemanticsLabel(l10n.placementClose));
      await tester.pump();

      expect(done, <String?>[null]);
    });
  });

  group('FR-S3-03 nothing is written', () {
    testWidgets('word_state stays empty through a whole check', (tester) async {
      await pump(tester);
      for (final right in <bool>[true, true, false, true, false, false]) {
        await answer(tester, right: right);
      }

      final rows = await tester.runAsync(
        () =>
            db.customSelect('SELECT COUNT(*) AS n FROM word_state').getSingle(),
      );
      expect(rows!.read<int>('n'), 0);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(RadioListTile<int>), findsNothing);
    });

    for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
      testWidgets('and ${mode.name} renders it', (tester) async {
        await pump(tester, mode: mode);
        expect(options(), findsWidgets);
        // Glass has no paper of its own: without the aurora behind it the
        // screen is black, and every option still "renders".
        expect(
          find.byType(AuroraBackdrop),
          mode == DpMode.glass ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('accessibility', () {
    testWidgets('the options are one group, and the picked one says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(options().first);
      await tester.pump();

      expect(
        tester.getSemantics(options().first),
        isSemantics(
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          isButton: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('and it holds together at 200 % text', (tester) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}

class _PoolDao extends ContentDao {
  _PoolDao(super.db);

  final List<String> asked = <String>[];

  @override
  Future<List<PlacementWord>> placementPool(String step) async {
    asked.add(step);
    return <PlacementWord>[for (var i = 0; i < 12; i++) wordFor(step, i)];
  }
}

class _SilentTts implements TtsEngine {
  @override
  Future<bool> speak(String text, {double rate = 1}) async => true;

  @override
  Future<void> stop() async {}
}

class _FixedLanguages extends Languages {
  _FixedLanguages(this.meaning);

  final MeaningLanguage meaning;

  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() =>
      (meaning: meaning, ui: UiLanguage.english);
}
