import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/learn/grammar_topic_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';
import '../core/text_clipping.dart';

import 'today_fixtures.dart';

/// L4 · Grammar topic — #118.
void main() {
  late AppLocalizations l10n;
  late AppDatabase db;
  late SettingsRepository settings;
  late List<String> spoken;
  late List<String> marked;
  late String? went;
  late Object? extra;
  late GoRouter routes;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(
    WidgetTester tester, {
    TopicWithState? topic,
    bool voice = true,
    Future<CourseText>? course,
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    spoken = <String>[];
    marked = <String>[];
    went = null;
    extra = null;
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
    Widget away(GoRouterState state) {
      went = state.uri.path;
      extra = state.extra;
      return const Scaffold(body: Text('away'));
    }

    routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const GrammarTopicScreen(uid: 'g3'),
        ),
        GoRoute(path: '/learn/grammar/:uid', builder: (_, s) => away(s)),
        GoRoute(path: '/grammar-practice', builder: (_, s) => away(s)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...todayStub(null, null, null, topic, course),
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(FakeTts(voice: voice, spoken: spoken)),
          grammarRatingServiceProvider.overrideWithValue(_Rating(marked)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
          builder: (_, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR-L4-02 #386 the rule shows while the course loads; only '
      'Practise waits, for its count', (tester) async {
    final course = Completer<CourseText>();
    await pump(tester, course: course.future);
    expect(find.text('Konjunktiv II – Höflichkeit'), findsOneWidget);
    expect(find.textContaining('Practise this rule'), findsNothing);

    course.complete(CourseText.none);
    await tester.pumpAndSettle();
    expect(find.textContaining('Practise this rule'), findsOneWidget);
  });

  testWidgets('the header: step, place in it, and title', (tester) async {
    await pump(tester);
    expect(find.text('A2.1'), findsWidgets);
    expect(find.text(l10n.topicPlace(4, 10)), findsOneWidget);
    expect(find.text('Konjunktiv II – Höflichkeit'), findsOneWidget);
  });

  testWidgets('the rule, each example with its translation, and Watch out', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('To ask politely'), findsOneWidget);
    expect(find.text('Könnten Sie mir bitte helfen?'), findsOneWidget);
    expect(find.text('Could you help me, please?'), findsOneWidget);
    expect(find.text('Ich hätte gern einen Kaffee.'), findsOneWidget);
    expect(find.text("I'd like a coffee."), findsOneWidget);
    expect(find.text(l10n.topicWatchOut.toUpperCase()), findsOneWidget);
  });

  testWidgets('FR-L4-03 play speaks the German example', (tester) async {
    await pump(tester);
    await tester.tap(
      find.bySemanticsLabel(l10n.topicPlay('Könnten Sie mir bitte helfen?')),
    );
    await tester.pump();
    expect(spoken, <String>['Könnten Sie mir bitte helfen?']);
  });

  testWidgets('V01 no German voice: play says how to install one', (
    tester,
  ) async {
    await pump(tester, voice: false);
    await tester.tap(
      find.bySemanticsLabel(l10n.topicPlay('Könnten Sie mir bitte helfen?')),
    );
    await tester.pump();
    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
  });

  testWidgets('FR-L4-02 Practise opens L15 for this topic, as many items as '
      'it will ask', (tester) async {
    await pump(tester);
    final count = practiceItemsFor(
      artboardTopic(),
      artboardTopics(),
      '2026-09-21',
      CourseText.none,
    ).length;
    await tester.tap(find.text(l10n.topicPractise(count)));
    await tester.pumpAndSettle();
    expect(went, '/grammar-practice');
    expect((extra! as GrammarPracticeArgs).topicUids, <String>['g3']);
  });

  testWidgets('FR-L4-01 Mark as learned schedules the topic, once however '
      'fast the taps', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.topicMarkLearned));
    await tester.tap(find.text(l10n.topicMarkLearned));
    await tester.pump();
    expect(marked, <String>['g3']);
    // The write done, the button is live again until the topic re-emits.
    release!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.topicMarkLearned));
    expect(marked, <String>['g3', 'g3']);
  });

  testWidgets('once learned: when it comes round, and no Mark as learned', (
    tester,
  ) async {
    await pump(
      tester,
      topic: artboardTopic(
        state: const GrammarStateData(
          grammarUid: 'g3',
          status: 'learning',
          due: '2026-09-25',
          stability: 4,
          difficulty: 5,
          reps: 1,
          lapses: 0,
          lastReview: '2026-09-21T09:00:00Z',
        ),
      ),
    );
    expect(find.text(l10n.topicMarkLearned), findsNothing);
    expect(find.text(l10n.topicLearnedNext(4)), findsOneWidget);
  });

  testWidgets('FR-L4-04 previous and next stay within the step', (
    tester,
  ) async {
    await pump(tester);
    // A2.1's third and fifth: Perfekt mit sein, Dativ nach Präpositionen.
    expect(find.text('Perfekt mit sein'), findsOneWidget);
    final next = find.bySemanticsLabel(
      l10n.topicNext('Dativ nach Präpositionen'),
    );
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(went, '/learn/grammar/g4');
    // In place of this topic, not on top of it: back leaves the topics.
    expect(routes.canPop(), isFalse);
  });

  testWidgets('#404 at 200 % text the back row keeps its label whole, in '
      'either chrome', (tester) async {
    textAt(tester, 2);
    for (final chrome in AdaptiveChrome.values) {
      await pump(tester, chrome: chrome);
      expectNothingClipped(tester, within: find.byType(AdaptiveBackButton));
    }
  });
}

/// Holds each markLearned open until [release] completes, as a real write
/// takes a moment.
Completer<void>? release;

class _Rating implements GrammarRatingService {
  _Rating(this.marked);

  final List<String> marked;

  @override
  Future<void> markLearned(String uid) {
    marked.add(uid);
    release = Completer<void>();
    return release!.future;
  }

  @override
  Future<void> ratePractice(
    String uid, {
    required int items,
    required int correct,
  }) async {}
}
