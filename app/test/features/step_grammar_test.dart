import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/step_detail_screen.dart';
import 'package:deutschplan/features/learn/step_grammar.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L2 · Grammar tab — #115.
void main() {
  const today = '2026-09-21';
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  group('FR-L2-05 where a topic stands, from grammar_state', () {
    final topics = artboardTopics();

    test('learned and not yet come round: scheduled', () {
      expect(topicDue(topics[0], today), TopicDue.scheduled);
    });

    test('learned and its day has come, or gone: due', () {
      expect(topicDue(topics[2], today), TopicDue.due, reason: 'today');
      expect(topicDue(topics[3], today), TopicDue.due, reason: 'overdue');
    });

    test('never practised: not learned', () {
      expect(topicDue(topics[4], today), TopicDue.notLearned);
    });

    test(
      'a state row that is still To do is not learned, whatever its due',
      () {
        final untouched = TopicWithState(
          topic: topics[2].topic,
          state: topics[2].state,
          status: WordStatus.todo,
        );
        expect(topicDue(untouched, today), TopicDue.notLearned);
      },
    );

    test('suspended is neither due nor scheduled', () {
      final paused = TopicWithState(
        topic: topics[2].topic,
        state: topics[2].state,
        status: WordStatus.suspended,
      );
      expect(topicDue(paused, today), TopicDue.suspended);
    });
  });

  late String? went;
  late Object? extra;
  late GoRouter routes;

  Future<void> pump(WidgetTester tester, {List<Override>? overrides}) async {
    went = null;
    extra = null;
    Widget away(GoRouterState state) {
      went = state.uri.path;
      extra = state.extra;
      return const Scaffold(body: Text('away'));
    }

    routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const StepDetailScreen(code: 'A2.1', tab: StepTab.grammar),
        ),
        GoRoute(path: '/learn/grammar/:uid', builder: (_, s) => away(s)),
        GoRoute(path: '/grammar-practice', builder: (_, s) => away(s)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides ?? todayStub(),
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

  testWidgets('numbered topics, their rule and when they come round', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Modalverben im Präteritum'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text(l10n.stepTopicNextIn(4)), findsOneWidget);
    expect(find.text(l10n.stepTopicNextIn(9)), findsOneWidget);
    expect(find.text(l10n.stepTopicDueToday), findsNWidgets(2));
  });

  testWidgets('Practise all due opens L15 with every due topic', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.stepPractiseDue(2)));
    await tester.pumpAndSettle();
    expect(went, '/grammar-practice');
    expect((extra! as GrammarPracticeArgs).topicUids, <String>['g2', 'g3']);
  });

  testWidgets('nothing due, no button', (tester) async {
    await pump(
      tester,
      overrides: <Override>[
        stepProgressProvider.overrideWith(
          (ref) => Stream.value(artboardCourse()),
        ),
        todayProvider.overrideWithValue(today),
        // Only the six not learned yet.
        stepTopicsProvider.overrideWith(
          (ref, code) => Stream.value(artboardTopics().skip(4).toList()),
        ),
      ],
    );
    expect(find.byType(TopicRow), findsWidgets);
    expect(find.textContaining('Practise all due'), findsNothing);
  });

  testWidgets('a topic opens L4 over the tab, and back returns to it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Perfekt mit sein'));
    await tester.pumpAndSettle();
    expect(went, '/learn/grammar/g2');
    routes.pop();
    await tester.pumpAndSettle();
    expect(find.text('Perfekt mit sein'), findsOneWidget);
  });

  group('rule previews: one line, cut at a word', () {
    const rule = 'konnte, musste, wollte — no umlaut, no ge-';

    Future<String> shown(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Center(
            child: SizedBox(
              width: width,
              child: const DpOneLine(rule, role: DpTextRole.label),
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.byType(Text)).data!;
    }

    testWidgets('whole when it fits', (tester) async {
      expect(await shown(tester, 800), rule);
    });

    testWidgets('otherwise whole words and an ellipsis, never half a word', (
      tester,
    ) async {
      for (final width in <double>[60, 90, 120, 160, 200, 240]) {
        final text = await shown(tester, width);
        expect(text, endsWith(DpOneLine.ellipsis), reason: '$width');
        final kept = text.substring(0, text.length - 1);
        expect(rule.startsWith(kept), isTrue, reason: '$width: $text');
        // What follows the kept part is a space or punctuation, so no word
        // was cut.
        final next = rule.substring(kept.length);
        expect(next, matches(RegExp(r'^[\s,—-]')), reason: '$width: $text');
      }
    });

    testWidgets('under a spaced-out ambient style, still never clipped', (
      tester,
    ) async {
      for (final width in <double>[90, 150, 210]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Center(
              child: DefaultTextStyle(
                style: const TextStyle(letterSpacing: 2),
                child: SizedBox(
                  width: width,
                  child: const DpOneLine(rule, role: DpTextRole.label),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(width + 0.5),
          reason: '$width: ${paragraph.text.toPlainText()}',
        );
      }
    });

    testWidgets('read out whole', (tester) async {
      await shown(tester, 90);
      expect(tester.widget<Text>(find.byType(Text)).semanticsLabel, rule);
    });
  });
}
