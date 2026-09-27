import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/features/backlog/backlog_screen.dart';
import 'package:sogda/features/learn/categories_screen.dart';
import 'package:sogda/features/learn/category_words_screen.dart';
import 'package:sogda/features/learn/exam_intro_screen.dart';
import 'package:sogda/features/learn/grammar_library_screen.dart';
import 'package:sogda/features/learn/grammar_practice_screen.dart';
import 'package:sogda/features/learn/grammar_topic_screen.dart';
import 'package:sogda/features/learn/step_exams.dart';
import 'package:sogda/features/learn/step_grammar.dart';
import 'package:sogda/features/learn/step_words.dart';
import 'package:sogda/features/quiz/quiz_result_screen.dart';
import 'package:sogda/features/sentences/sentences_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart' show QuizArgs;
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_fixtures.dart';
import 'today_fixtures.dart';

/// #677: a screen whose read fails shows the shared panel with Retry, and a
/// way out where its back row is part of what failed, never a blank page.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  final step = artboardCourse().firstWhere((s) => s.code == 'A2.1');

  /// [screen] over a page it can go back to, with [failing] making its read
  /// throw. Returns how often that read ran.
  Future<List<int>> pump(
    WidgetTester tester,
    Widget screen,
    Override Function(List<int> calls) failing,
  ) async {
    final calls = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsProvider.overrideWithValue(StubSettings()),
          todayProvider.overrideWithValue('2026-09-21'),
          failing(calls),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(pageBuilder: (_, _, _) => screen),
                ),
                child: const Text('under'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('under'));
    await tester.pumpAndSettle();
    return calls;
  }

  Future<void> expectPanel(
    WidgetTester tester,
    List<int> calls,
    String message, {
    required bool back,
  }) async {
    expect(find.byType(SgLoadFailed), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    final before = calls.length;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(calls.length, before + 1, reason: 'Retry reads it again');
    if (back) {
      await tester.tap(find.text(l10n.back));
      await tester.pumpAndSettle();
      expect(find.text('under'), findsOneWidget, reason: 'Back leaves it');
    } else {
      expect(find.text(l10n.back), findsNothing);
    }
  }

  Never fail() => throw StateError('the read failed');

  testWidgets('#677 FR-L2 the Words tab', (tester) async {
    final calls = await pump(
      tester,
      Scaffold(body: StepWordsTab(step: step)),
      (calls) => stepWordsProvider.overrideWith((ref, code) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L2 the Grammar tab', (tester) async {
    final calls = await pump(
      tester,
      const Scaffold(body: StepGrammarTab(code: 'A2.1')),
      (calls) => stepTopicsProvider.overrideWith((ref, code) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L2 the Exams tab', (tester) async {
    final calls = await pump(
      tester,
      // An open step: a locked one never reads its hub.
      Scaffold(
        body: StepExamsTab(
          step: artboardCourse().firstWhere((s) => s.unlocked),
        ),
      ),
      (calls) => examHubProvider.overrideWith((ref, code) async {
        calls.add(1);
        fail();
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L10 a mock exam intro', (tester) async {
    final calls = await pump(
      tester,
      const ExamIntroScreen(step: 'A2.1', seed: 1),
      (calls) => examIntroProvider.overrideWith((ref, args) async {
        calls.add(1);
        fail();
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L5 the categories', (tester) async {
    final calls = await pump(
      tester,
      const CategoriesScreen(),
      (calls) => categoriesProvider.overrideWith((ref) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets("#677 FR-L6 a category's words", (tester) async {
    final calls = await pump(
      tester,
      const CategoryWordsScreen(id: 1),
      (calls) => categoryWordsProvider.overrideWith((ref, id) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L3 the grammar library', (tester) async {
    final calls = await pump(
      tester,
      const GrammarLibraryScreen(),
      (calls) => libraryTopicsProvider.overrideWith((ref) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: false);
  });

  testWidgets('#677 FR-L4 a grammar topic: Back too', (tester) async {
    final calls = await pump(
      tester,
      const GrammarTopicScreen(uid: 'g1'),
      (calls) => grammarTopicProvider.overrideWith((ref, uid) {
        calls.add(1);
        return Stream.error(StateError('the read failed'));
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  testWidgets('#677 FR-L15 a practice topic that will not read: Back too', (
    tester,
  ) async {
    final calls = await pump(
      tester,
      const GrammarPracticeScreen(topicUids: <String>['stale-uid']),
      (calls) => practiceSetProvider.overrideWith((ref, uid) async {
        calls.add(1);
        fail();
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  testWidgets("#677 FR-L9 a quiz's result: Back too", (tester) async {
    final calls = await pump(
      tester,
      const QuizResultView(
        attemptId: 1,
        args: QuizArgs(
          direction: 'deEn',
          source: 'stepLearned',
          sourceRef: 'A2.1',
          seed: 7,
          length: 20,
          timer: true,
        ),
      ),
      (calls) => quizResultProvider.overrideWith((ref, id) async {
        calls.add(1);
        fail();
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  // The issue's L15 case: a stale uid reads fine but finds no topic (null),
  // which is no error, and the page stayed blank with no way out.
  testWidgets('#677 FR-L15 a stale uid, read as no topic: the panel too', (
    tester,
  ) async {
    final calls = await pump(
      tester,
      const GrammarPracticeScreen(topicUids: <String>['stale-uid']),
      (calls) => practiceSetProvider.overrideWith((ref, uid) async {
        calls.add(1);
        return null;
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  testWidgets('#677 FR-L4 a stale uid, read as no topic: the panel too', (
    tester,
  ) async {
    final calls = await pump(
      tester,
      const GrammarTopicScreen(uid: 'stale-uid'),
      (calls) => grammarTopicProvider.overrideWith((ref, uid) {
        calls.add(1);
        return Stream.value(null);
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  testWidgets("#677 FR-L9 an attempt that isn't there: the panel too", (
    tester,
  ) async {
    final calls = await pump(
      tester,
      const QuizResultView(
        attemptId: 404,
        args: QuizArgs(
          direction: 'deEn',
          source: 'stepLearned',
          sourceRef: 'A2.1',
          seed: 7,
          length: 20,
          timer: true,
        ),
      ),
      (calls) => quizResultProvider.overrideWith((ref, id) async {
        calls.add(1);
        return null;
      }),
    );
    await expectPanel(tester, calls, l10n.learnLoadFailed, back: true);
  });

  testWidgets("#677 FR-T5 the day's sentences", (tester) async {
    final calls = await pump(
      tester,
      const SentencesScreen(),
      (calls) => practiceSentencesProvider.overrideWith(
        () => _FailingSentences(calls),
      ),
    );
    await expectPanel(tester, calls, l10n.todayLoadFailed, back: false);
  });

  testWidgets('#677 FR-T4 the backlog: Back too', (tester) async {
    final calls = await pump(
      tester,
      const BacklogScreen(),
      (calls) => backlogProvider.overrideWith(() => _FailingBacklog(calls)),
    );
    await expectPanel(tester, calls, l10n.todayLoadFailed, back: true);
  });
}

class _FailingSentences extends PracticeSentences {
  _FailingSentences(this.calls);

  final List<int> calls;

  @override
  Future<List<PracticeSentence>> build() async {
    calls.add(1);
    throw StateError('the read failed');
  }
}

class _FailingBacklog extends Backlog {
  _FailingBacklog(this.calls);

  final List<int> calls;

  @override
  Stream<List<BacklogWord>> build() {
    calls.add(1);
    return Stream.error(StateError('the read failed'));
  }
}
