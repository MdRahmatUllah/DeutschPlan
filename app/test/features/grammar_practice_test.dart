import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/learn/grammar_practice_screen.dart';
import 'package:deutschplan/features/learn/grammar_topic_screen.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import 'today_fixtures.dart';

/// L15 · Grammar practice — #119.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const pick = PickTheForm(
    before: '',
    after: 'Sie mir bitte helfen?',
    options: <String>['Könnten', 'Können', 'Konnten'],
    answer: 'Könnten',
    translation: 'Could you help me, please?',
  );
  const gap = GapFill(
    before: 'Ich',
    after: 'gern einen Kaffee.',
    answer: 'hätte',
    translation: "I'd like a coffee.",
  );
  // Seven letters: one typo is *almost* (BR-ANS-01's typoMinLength).
  const longGap = GapFill(
    before: 'Du',
    after: 'auf den Bus.',
    answer: 'wartest',
    translation: "You're waiting for the bus.",
  );
  const spot = SpotTheError(
    tokens: <String>['Können', 'Sie', 'mir', 'helfen?'],
    wrong: 0,
    correction: 'Könnten',
  );
  const order = OrderTheSentence(
    chips: <String>['Sie', 'helfen?', 'Könnten'],
    answer: <String>['Könnten', 'Sie', 'helfen?'],
  );
  const recall = RuleRecall(
    question: 'Konjunktiv II – Höflichkeit',
    options: <String>[
      'könnte for polite requests',
      'verb last',
      'dative',
      'v2',
    ],
    answer: 0,
  );

  late List<(String, int, int)> rated;
  late _Rating rating;
  late String? went;
  late GoRouter routes;

  Future<void> pump(
    WidgetTester tester, {
    required List<GrammarItem> items,
    List<String> topics = const <String>['g3'],
    bool dayDone = false,
  }) async {
    rated = <(String, int, int)>[];
    rating = _Rating(rated);
    went = null;
    routes = GoRouter(
      initialLocation: '/opener',
      routes: <RouteBase>[
        GoRoute(
          path: '/opener',
          builder: (_, _) => const Scaffold(body: Text('opener')),
        ),
        GoRoute(
          path: '/practice',
          builder: (_, _) => GrammarPracticeScreen(topicUids: topics),
        ),
        GoRoute(
          path: '/day-complete',
          builder: (_, state) {
            went = state.uri.path;
            return const Scaffold(body: Text('T6'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...todayStub(),
          practiceSetProvider.overrideWith(
            (ref, uid) async => (
              topic: artboardTopic(),
              items: uid == 'g3' ? items : <GrammarItem>[pick, gap, spot],
            ),
          ),
          grammarRatingServiceProvider.overrideWithValue(rating),
          studyNextProvider.overrideWith(
            (ref, date) async =>
                StudyNext(sentences: 0, backlog: 0, dayDone: dayDone),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    unawaited(routes.push('/practice'));
    await tester.pumpAndSettle();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.text(l10n.practiceNext));
    await tester.pumpAndSettle();
  }

  testWidgets('the header: the topic and the place in its run', (tester) async {
    await pump(tester, items: <GrammarItem>[pick, gap, spot]);
    expect(find.text('Konjunktiv II – Höflichkeit'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text(l10n.practicePickTheForm), findsOneWidget);
  });

  group('FR-L15-02 immediate feedback', () {
    testWidgets('pick the form, right', (tester) async {
      await pump(tester, items: <GrammarItem>[pick, gap, spot]);
      await tester.tap(find.text('Könnten'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceRight), findsOneWidget);
      expect(find.textContaining(l10n.practiceRuleLine('')), findsNothing);
    });

    testWidgets('pick the form, wrong: the answer, the rule, See rule', (
      tester,
    ) async {
      await pump(tester, items: <GrammarItem>[pick, gap, spot]);
      await tester.tap(find.text('Können'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceNotQuite('Könnten')), findsOneWidget);
      expect(find.textContaining('Rule: To ask politely'), findsOneWidget);
      await tester.tap(find.text(l10n.practiceSeeRule));
      await tester.pumpAndSettle();
      expect(find.byType(RuleSheet), findsOneWidget);
      expect(find.byType(WatchOut), findsOneWidget);
      await tester.tap(find.text(l10n.practiceBackToItem));
      await tester.pumpAndSettle();
      // Back on the same, answered item.
      expect(find.text(l10n.practiceNotQuite('Könnten')), findsOneWidget);
    });

    testWidgets('an answer is final: a second tap changes nothing', (
      tester,
    ) async {
      await pump(tester, items: <GrammarItem>[pick, gap, spot]);
      // Two taps inside one frame: both reach the tiles as they were built.
      await tester.tap(find.text('Können'));
      await tester.tap(find.text('Könnten'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceNotQuite('Könnten')), findsOneWidget);
      await tester.tap(find.text('Könnten'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceNotQuite('Könnten')), findsOneWidget);
    });

    testWidgets('gap fill, typed and checked as German', (tester) async {
      await pump(tester, items: <GrammarItem>[gap, pick, spot]);
      await tester.enterText(find.byType(TextField), 'habe');
      // Check enables on the frame after the typing.
      await tester.pump();
      await tester.tap(find.text(l10n.practiceCheck));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceNotQuite('hätte')), findsOneWidget);
    });

    testWidgets('#345 gap fill, one letter off: almost, as T2 says it, with '
        'no rule line', (tester) async {
      await pump(tester, items: <GrammarItem>[longGap, pick, spot]);
      await tester.enterText(find.byType(TextField), 'wartets');
      await tester.pump();
      await tester.tap(find.text(l10n.practiceCheck));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceAlmost('wartest')), findsOneWidget);
      expect(find.text(l10n.practiceNotQuite('wartest')), findsNothing);
      expect(find.text(l10n.practiceSeeRule), findsNothing);
    });

    testWidgets('gap fill, an umlaut typed plainly is still right', (
      tester,
    ) async {
      await pump(tester, items: <GrammarItem>[gap, pick, spot]);
      await tester.enterText(find.byType(TextField), 'haette');
      await tester.pump();
      await tester.tap(find.text(l10n.practiceCheck));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceRight), findsOneWidget);
    });

    testWidgets('spot the error: the wrong word tapped is right', (
      tester,
    ) async {
      await pump(tester, items: <GrammarItem>[spot, pick, gap]);
      await tester.tap(find.text('Können'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceRight), findsOneWidget);
    });

    testWidgets('spot the error: another word tapped is wrong', (tester) async {
      await pump(tester, items: <GrammarItem>[spot, pick, gap]);
      await tester.tap(find.text('mir'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceNotQuite('Könnten')), findsOneWidget);
    });

    testWidgets('order the sentence: placed, taken back, placed, checked', (
      tester,
    ) async {
      await pump(tester, items: <GrammarItem>[order, pick, gap]);
      await tester.tap(find.text('Sie'));
      await tester.pump();
      // Wrong first: take it back.
      await tester.tap(find.text('Sie'));
      await tester.pump();
      for (final word in <String>['Könnten', 'Sie', 'helfen?']) {
        await tester.tap(find.text(word));
        await tester.pump();
      }
      await tester.tap(find.text(l10n.practiceCheck));
      await tester.pumpAndSettle();
      expect(find.text(l10n.practiceRight), findsOneWidget);
    });

    testWidgets('order the sentence: the wrong order is wrong', (tester) async {
      await pump(tester, items: <GrammarItem>[order, pick, gap]);
      for (final word in <String>['Sie', 'Könnten', 'helfen?']) {
        await tester.tap(find.text(word));
        await tester.pump();
      }
      await tester.tap(find.text(l10n.practiceCheck));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.practiceNotQuite('Könnten Sie helfen?')),
        findsOneWidget,
      );
    });

    testWidgets('rule recall: four options, one right', (tester) async {
      await pump(tester, items: <GrammarItem>[recall, pick, gap]);
      expect(
        find.text(l10n.practiceRecallQuestion('Konjunktiv II – Höflichkeit')),
        findsOneWidget,
      );
      await tester.tap(find.text('dative'));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.practiceNotQuite('könnte for polite requests')),
        findsOneWidget,
      );
    });
  });

  testWidgets('#164 under reduce motion the topic banner has no size '
      'animation', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    // Two topics, so the banner is there at all.
    await pump(
      tester,
      items: <GrammarItem>[pick, gap, spot],
      topics: <String>['g3', 'g4'],
    );
    // A zero-duration AnimatedSize breaks its layout: it isn't there.
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets('Next only once answered, then the next item', (tester) async {
    await pump(tester, items: <GrammarItem>[pick, gap, spot]);
    await tapNext(tester);
    expect(find.text('1 / 3'), findsOneWidget, reason: 'not answered yet');
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text(l10n.practiceGapFill), findsOneWidget);
  });

  testWidgets('FR-L15-03 the topic rated as a whole on its last item', (
    tester,
  ) async {
    await pump(tester, items: <GrammarItem>[pick, spot, recall]);
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    await tester.tap(find.text('mir'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(rated, isEmpty, reason: 'not before the last');
    await tester.tap(find.text('könnte for polite requests'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(rated, <(String, int, int)>[('g3', 3, 2)]);
  });

  testWidgets('#345 FR-L15-03 an almost counts as right in the topic\'s '
      'rating', (tester) async {
    await pump(tester, items: <GrammarItem>[longGap, pick, recall]);
    await tester.enterText(find.byType(TextField), 'wartets');
    await tester.pump();
    await tester.tap(find.text(l10n.practiceCheck));
    await tester.pumpAndSettle();
    await tapNext(tester);
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    await tester.tap(find.text('könnte for polite requests'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(rated, <(String, int, int)>[('g3', 3, 3)]);
  });

  testWidgets('FR-L15-04 due topics back to back, a banner between', (
    tester,
  ) async {
    await pump(
      tester,
      items: <GrammarItem>[pick],
      topics: <String>['g3', 'g4'],
    );
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.practiceNext));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(l10n.practiceNextTopic(2, 2, 'Konjunktiv II – Höflichkeit')),
      findsOneWidget,
    );
    expect(find.text('1 / 3'), findsOneWidget, reason: 'the next topic');
    await tester.pump(GrammarPracticeScreen.bannerTime);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.practiceNextTopic(2, 2, 'Konjunktiv II – Höflichkeit')),
      findsNothing,
    );
    expect(rated.single.$1, 'g3');
  });

  testWidgets('the last topic done: back to the opener', (tester) async {
    await pump(tester, items: <GrammarItem>[pick]);
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(find.text('opener'), findsOneWidget);
  });

  testWidgets('or T6, if that completes the day', (tester) async {
    await pump(tester, items: <GrammarItem>[pick], dayDone: true);
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(went, '/day-complete');
  });

  testWidgets('Z05 FR-L15-03 a result that fails to save keeps the topic; '
      'Retry writes it and moves on', (tester) async {
    await pump(tester, items: <GrammarItem>[pick]);
    rating.failures = 1;
    await tester.tap(find.text('Könnten'));
    await tester.pumpAndSettle();
    await tapNext(tester);

    expect(find.text(l10n.saveAnswerFailed), findsOneWidget);
    expect(rated, isEmpty);
    expect(find.text('opener'), findsNothing, reason: 'the topic stays');

    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();

    expect(rated, <(String, int, int)>[('g3', 1, 1)]);
    expect(find.text('opener'), findsOneWidget);
  });

  test(
    'FR-L15-01 the items are the generator\'s, seeded per topic and day',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final directory = Directory.systemTemp.createTempSync('dp_practice');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          todayProvider.overrideWithValue('2026-09-21'),
        ],
      );
      addTearDown(container.dispose);
      final hold = container.listen(practiceSetProvider('g1'), (_, _) {});
      addTearDown(hold.close);
      final set = (await container.read(practiceSetProvider('g1').future))!;
      final topic = set.topic;
      final expected = generateItems(
        grammarSource(topic),
        seed: practiceSeed('g1', '2026-09-21'),
      );
      expect(set.items.length, expected.length);
      expect(
        set.items.map((item) => item.runtimeType),
        expected.map((item) => item.runtimeType),
      );
      expect(set.items.length, inInclusiveRange(3, 5));
    },
  );
}

class _Rating implements GrammarRatingService {
  _Rating(this.rated);

  final List<(String, int, int)> rated;

  /// How many writes fail before one goes through (#174).
  int failures = 0;

  @override
  Future<void> markLearned(String uid) async {}

  @override
  Future<void> ratePractice(
    String uid, {
    required int items,
    required int correct,
  }) async {
    if (failures > 0) {
      failures--;
      throw StateError('disk I/O error');
    }
    rated.add((uid, items, correct));
  }
}
