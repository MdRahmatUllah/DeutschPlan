import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/features/exam/exam_runner_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'exam_run_fixtures.dart';

const SpeakingTask speaking = SpeakingTask(
  'speaking:1',
  level: 'A1',
  category: 'Wohnen',
  seconds: 60,
);

/// L12 · Writing — #133.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late StubExamRun run;

  /// The runner on [items]: Writing, then Speaking, unless said otherwise.
  Future<void> pump(
    WidgetTester tester, {
    List<ExamItem> items = const <ExamItem>[artboardWriting, speaking],
  }) async {
    run = StubExamRun(items: items, given: <int, String>{});
    final routes = GoRouter(
      initialLocation: '/exam',
      routes: <RouteBase>[
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
        overrides: examRunStub(run),
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

  Future<void> write(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  Finder used(String word) =>
      find.bySemanticsLabel(l10n.examWritingTargetUsed(word));

  testWidgets('the task for the level and category, and its ten words', (
    tester,
  ) async {
    await pump(tester);

    expect(
      find.text(
        '${l10n.examWritingTask('A1', 'Wohnen')} ${l10n.examWritingUse}',
      ),
      findsOneWidget,
    );
    for (final target in artboardWriting.targets) {
      expect(find.text(target), findsOneWidget, reason: target);
    }
    expect(find.text(l10n.examWritingUsed(0, 10, 30, 'A1')), findsOneWidget);
    expect(find.byType(DpUmlautBar), findsOneWidget);
    expect(find.text(l10n.examWritingSubmit), findsOneWidget);
  });

  testWidgets('FR-L12W-01 a target turns Lime as the text uses it: '
      '"Heizungen" uses Heizung', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    await write(tester, 'Die Heizungen sind kaputt.');

    expect(used('Heizung'), findsOneWidget);
    expect(used('kaputt'), findsOneWidget);
    expect(used('Termin'), findsNothing);
    expect(find.text(l10n.examWritingUsed(2, 10, 30, 'A1')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets("FR-L12W-02 its length against the level's minimum", (
    tester,
  ) async {
    const b1 = WritingTask(
      'writing:2',
      level: 'B1',
      category: 'Arbeit',
      targets: <String>['Chef'],
      minWords: 100,
      connectors: <String>[],
    );
    await pump(tester, items: const <ExamItem>[b1]);
    expect(find.text(l10n.examWritingCount(0, 100)), findsOneWidget);

    await write(tester, 'Mein Chef ist nett.');
    expect(find.text(l10n.examWritingCount(4, 100)), findsOneWidget);
    expect(find.text(l10n.examWritingUsed(1, 1, 100, 'B1')), findsOneWidget);
  });

  testWidgets('the connectors in it, as they come', (tester) async {
    await pump(tester);
    expect(find.textContaining('Connectors'), findsNothing);

    await write(tester, 'Ich gehe, ohne dass es regnet, und esse.');
    expect(
      find.text(l10n.examWritingConnectors('und, ohne dass')),
      findsOneWidget,
    );
  });

  group('FR-L12W-04 the text is the answer', () {
    testWidgets('written on Submit text', (tester) async {
      await pump(tester);
      await write(tester, artboardWritingText);
      await tester.tap(find.text(l10n.examWritingSubmit));
      await tester.pumpAndSettle();

      expect(run.answers, <(int, String?)>[(1, artboardWritingText)]);
    });

    testWidgets('and with the clock, before it moves on', (tester) async {
      await pump(tester);
      await write(tester, 'Die Heizung ist kaputt.');

      await tester.pump(const Duration(seconds: 10));
      expect(run.answers, <(int, String?)>[(1, 'Die Heizung ist kaputt.')]);
    });
  });

  testWidgets('with no category, a topic still', (tester) async {
    const none = WritingTask(
      'writing:3',
      level: 'A2',
      category: null,
      targets: <String>['Haus'],
      minWords: 60,
      connectors: <String>[],
    );
    await pump(tester, items: const <ExamItem>[none]);
    expect(
      find.textContaining(
        l10n.examWritingTask('A2', l10n.examWritingTopicFallback),
      ),
      findsOneWidget,
    );
  });
}
