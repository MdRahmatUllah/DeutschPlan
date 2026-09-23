import 'package:deutschplan/core/components/dp_coach_mark.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/today/today_screen.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// T1 · Today in progress — #95.
void main() {
  late GoRouter router;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(
    WidgetTester tester, {
    TodayView? view,
    Override? load,
    bool coachMark = false,
    Locale? locale,
    List<Override> also = const <Override>[],
  }) async {
    router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          load ??
              todayViewProvider.overrideWith(
                (ref) async => view ?? artboardToday(),
              ),
          if (coachMark)
            coachMarkProvider.overrideWith(_ShowingCoachMark.new)
          else
            coachMarkProvider.overrideWithValue(false),
          ...also,
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// What a pushed full-screen route was opened with. A push leaves the
  /// configuration's URI where it was, so it is read off the screen's own
  /// route state; the placeholder for [screen] is what is showing.
  Object? opened(WidgetTester tester, String screen) {
    expect(find.text(screen), findsOneWidget, reason: '$screen is not open');
    return GoRouterState.of(tester.element(find.text(screen))).extra;
  }

  SessionArgs? session(WidgetTester tester) =>
      opened(tester, 'T2') as SessionArgs?;

  Finder card(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(PlanSectionCard),
  );

  Future<void> tapCard(WidgetTester tester, String title) async {
    await tester.ensureVisible(card(title));
    // The jump lands on the next frame; tapping before it hits where the
    // card used to be.
    await tester.pump();
    await tester.tap(card(title));
    await tester.pumpAndSettle();
  }

  group('the header', () {
    testWidgets('German date and greeting, whatever the UI language', (
      tester,
    ) async {
      await pump(tester, locale: const Locale('bn'));

      expect(find.text('Montag, 21. September'), findsOneWidget);
      expect(find.text('Guten Morgen, Maruf'), findsOneWidget);
    });

    testWidgets('no name, no comma', (tester) async {
      await pump(tester, view: artboardToday(learnerName: null));
      expect(find.text('Guten Morgen'), findsOneWidget);
    });

    testWidgets('the streak opens Progress and the gear Settings', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel(l10n.todayStreak(12)));
      await tester.pumpAndSettle();
      expect(location(), '/me/progress');

      router.go('/today');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(l10n.todaySettings));
      await tester.pumpAndSettle();
      expect(location(), '/me/settings');
    });
  });

  group('the ring card', () {
    testWidgets('FR-T1-02 shows done over total and the time left', (
      tester,
    ) async {
      await pump(tester);

      final ring = tester.widget<DpProgressRing>(
        find.descendant(
          of: find.byType(ProgressRingCard),
          matching: find.byType(DpProgressRing),
        ),
      );
      expect((ring.completed, ring.total), (12, 20));
      expect(ring.caption, l10n.todayEstimate(6));
      expect(find.text(l10n.todayCourseDay(34)), findsOneWidget);
      expect(find.text(l10n.todayStepWords(184, 540, 'A2.1')), findsOneWidget);
    });

    testWidgets('FR-T1-08 the step chip switches to Learn and opens it', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('A2.1'));
      await tester.pumpAndSettle();

      expect(location(), '/learn/step/A2.1');
    });
  });

  group('FR-T1-04 the section cards', () {
    testWidgets('Revise starts a session with only its open words', (
      tester,
    ) async {
      await pump(tester, view: artboardToday(reviseDone: 7));
      await tapCard(tester, l10n.todayRevise(10));

      expect(session(tester)?.wordUids, <String>['r7', 'r8', 'r9']);
      expect(session(tester)?.planDate, '2026-09-21');
    });

    testWidgets('New today starts a session with only its open words', (
      tester,
    ) async {
      await pump(tester);
      await tapCard(tester, l10n.todayNew(7));

      expect(session(tester)?.wordUids, <String>['n2', 'n3', 'n4', 'n5', 'n6']);
    });

    testWidgets('a finished block has nothing to start', (tester) async {
      await pump(tester);
      // Revise is 10 of 10 on the artboard.
      await tapCard(tester, l10n.todayRevise(10));
      expect(location(), '/today');
    });

    testWidgets('Backlog opens T4', (tester) async {
      await pump(tester);
      await tapCard(tester, l10n.todayBacklog(14));
      expect(location(), '/today/backlog');
    });

    testWidgets('Practice sentences opens T5', (tester) async {
      await pump(tester);
      await tapCard(tester, l10n.todaySentences(3));
      opened(tester, 'T5');
    });

    testWidgets('Grammar due opens practice with the due topics', (
      tester,
    ) async {
      await pump(tester, view: artboardToday(grammarDue: 2));
      await tapCard(tester, l10n.todayGrammarDue(2));

      final args = opened(tester, 'L15') as GrammarPracticeArgs?;
      expect(args?.topicUids, <String>['g0', 'g1']);
    });

    testWidgets('the backlog card is only there with a backlog', (
      tester,
    ) async {
      await pump(tester, view: artboardToday(backlog: 0));
      expect(card(l10n.todayBacklog(0)), findsNothing);
    });

    testWidgets('it says when the waiting words were planned', (tester) async {
      await pump(tester);
      expect(
        find.text(l10n.todayBacklogRange(14, 'Tue', 'Wed')),
        findsOneWidget,
      );
    });

    testWidgets('on the first day Revise says when it starts', (tester) async {
      await pump(
        tester,
        view: TodayView(
          date: '2026-09-21',
          hour: 9,
          revise: BlockProgress.none,
          newToday: const BlockProgress(done: 0, total: 7),
          openRevise: const <String>[],
          openNew: const <String>['n0'],
          grammarDue: const <String>[],
          backlog: 0,
          streak: 0,
          estimate: const Duration(minutes: 5),
          courseDay: 1,
          stepWords: (done: 0, learning: 0, todo: 637, total: 637),
          step: 'A1.1',
        ),
      );
      expect(find.text(l10n.todayReviseFirstDay), findsOneWidget);
    });

    testWidgets('each block shows a ring, or a check when done', (
      tester,
    ) async {
      await pump(tester);
      PlanSectionCard of(String title) =>
          tester.widget<PlanSectionCard>(card(title));

      expect(of(l10n.todayRevise(10)).trailing, SectionTrailing.done);
      expect(of(l10n.todayNew(7)).trailing, SectionTrailing.progress);
      expect(of(l10n.todayBacklog(14)).trailing, SectionTrailing.open);
    });
  });

  group('the grammar card', () {
    testWidgets('shows the next topic and the start of its rule', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Konjunktiv II – Höflichkeit'), findsOneWidget);
    });

    testWidgets('FR-T1-08 switches to Learn and opens the topic', (
      tester,
    ) async {
      await pump(tester);
      await tester.ensureVisible(find.byType(GrammarPreviewCard));
      await tester.pump();
      await tester.tap(find.byType(GrammarPreviewCard));
      await tester.pumpAndSettle();

      expect(location(), '/learn/grammar/konj2');
    });
  });

  group('the docked button', () {
    String label(WidgetTester tester) =>
        tester.widget<PrimaryActionBar>(find.byType(PrimaryActionBar)).label;

    testWidgets('before anything is done it starts the day', (tester) async {
      await pump(tester, view: artboardToday(reviseDone: 0, newDone: 0));
      expect(label(tester), l10n.todayStart(20));
    });

    testWidgets('once started it says what is left', (tester) async {
      await pump(tester);
      expect(label(tester), l10n.todayContinue(8));
    });

    testWidgets('FR-T1-03 it starts every open block: Revise, New, Grammar', (
      tester,
    ) async {
      await pump(tester, view: artboardToday(reviseDone: 8, grammarDue: 1));
      await tester.tap(find.byType(PrimaryActionBar));
      await tester.pumpAndSettle();

      final blocks = session(tester)!.blocks;
      expect(blocks.map((b) => b.kind), <SessionBlockKind>[
        SessionBlockKind.revise,
        SessionBlockKind.newWords,
        SessionBlockKind.grammar,
      ]);
      expect(blocks[0].uids, <String>['r8', 'r9']);
      expect(blocks[1].uids, <String>['n2', 'n3', 'n4', 'n5', 'n6']);
      expect(blocks[2].uids, <String>['g0']);
    });

    testWidgets('a finished block is left out', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(PrimaryActionBar));
      await tester.pumpAndSettle();

      expect(session(tester)!.blocks.map((b) => b.kind), <SessionBlockKind>[
        SessionBlockKind.newWords,
      ]);
    });

    testWidgets('with the study blocks done it practises sentences', (
      tester,
    ) async {
      await pump(tester, view: artboardToday(reviseDone: 10, newDone: 7));
      expect(label(tester), l10n.todaySentencesAction(3));

      await tester.tap(find.byType(PrimaryActionBar));
      await tester.pumpAndSettle();
      opened(tester, 'T5');
    });

    testWidgets('with the day done it reviews the backlog', (tester) async {
      await pump(
        tester,
        view: artboardToday(reviseDone: 10, newDone: 7, sentencesDone: 3),
      );
      expect(label(tester), l10n.todayBacklogAction(14));

      await tester.tap(find.byType(PrimaryActionBar));
      await tester.pumpAndSettle();
      expect(location(), '/today/backlog');
    });

    testWidgets('on a rest day it revises, and only revises', (tester) async {
      await pump(tester, view: artboardToday(reviseDone: 4, isStudyDay: false));
      expect(label(tester), l10n.todayReviseAnyway(6));

      await tester.tap(find.byType(PrimaryActionBar));
      await tester.pumpAndSettle();
      final blocks = session(tester)!.blocks;
      expect(blocks.single.kind, SessionBlockKind.revise);
      expect(blocks.single.uids, hasLength(6));
    });

    testWidgets('with nothing left it is done, and disabled', (tester) async {
      await pump(
        tester,
        view: TodayView(
          date: '2026-09-21',
          hour: 20,
          revise: const BlockProgress(done: 10, total: 10),
          newToday: const BlockProgress(done: 7, total: 7),
          openRevise: const <String>[],
          openNew: const <String>[],
          grammarDue: const <String>[],
          backlog: 0,
          streak: 12,
          estimate: Duration.zero,
          courseDay: 34,
          stepWords: (done: 184, learning: 60, todo: 296, total: 540),
          step: 'A2.1',
        ),
      );
      expect(label(tester), l10n.todayAllDone);
      expect(
        tester
            .widget<PrimaryActionBar>(find.byType(PrimaryActionBar))
            .onPressed,
        isNull,
      );
      // TodayDone: Lime, and the ink stays ink rather than greying out.
      final button = tester.widget<DpButton>(find.byType(DpButton));
      expect(button.colour, DpPalette.light.easy);
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(DpButton),
          matching: find.text(l10n.todayAllDone),
        ),
      );
      expect(text.style?.color, DpPalette.light.onAccent);
    });

    testWidgets('FR-S2-03 carries the one-time coach mark', (tester) async {
      await pump(tester, coachMark: true);
      final mark = tester.widget<DpCoachMark>(find.byType(DpCoachMark));
      expect(mark.visible, isTrue);
      expect(find.text(l10n.todayCoachMark), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DpCoachMark),
          matching: find.byType(PrimaryActionBar),
        ),
        findsOneWidget,
      );
    });
  });

  group('#96 all done', () {
    testWidgets('the day collapses into one row, and tomorrow appears', (
      tester,
    ) async {
      await pump(tester, view: artboardDone());

      expect(find.text('Tag geschafft, Maruf'), findsOneWidget);
      expect(find.byType(PlanSectionCard), findsNothing);
      expect(find.text(l10n.todayDoneTitle), findsOneWidget);
      expect(
        find.text(
          '${l10n.todayDoneRevise(10)} · ${l10n.todayDoneNew(7)} · '
          '${l10n.todayDoneSentences(3)} · ${l10n.todayBacklogCleared}',
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.todayDoneLine(34, 17, 12)), findsOneWidget);
    });

    testWidgets("the Tomorrow card reads the preview's numbers", (
      tester,
    ) async {
      await pump(tester, view: artboardDone());

      expect(find.text(l10n.todayTomorrowRevisions(12)), findsOneWidget);
      expect(find.text(l10n.todayTomorrowNew(7)), findsOneWidget);
      expect(find.text(l10n.todayGrammarDue(1)), findsOneWidget);
      expect(
        find.text(l10n.todayTomorrowContinues(13, 'Wohnen & Haushalt')),
        findsOneWidget,
      );
    });

    testWidgets('the ring turns Lime, with a tick for the time', (
      tester,
    ) async {
      await pump(tester, view: artboardDone());
      final ring = tester.widget<DpProgressRing>(
        find.descendant(
          of: find.byType(ProgressRingCard),
          matching: find.byType(DpProgressRing),
        ),
      );
      expect(ring.colour, DpPalette.light.easy);
      expect(ring.caption, isNull);
      expect(ring.captionIcon, Icons.check);
    });

    testWidgets('the grammar card keeps only the topic', (tester) async {
      await pump(tester, view: artboardDone());
      expect(find.text('Konjunktiv II – Höflichkeit'), findsOneWidget);
      expect(
        find.text('Könnten Sie …? — polite requests with könnte and würde'),
        findsNothing,
      );
    });

    testWidgets('BR-PLAN-01 a rest day tomorrow says so, not a plan', (
      tester,
    ) async {
      await pump(
        tester,
        view: artboardDone(
          tomorrow: const TomorrowPreview(
            revise: 6,
            newWords: 0,
            grammar: 0,
            estimate: Duration(minutes: 3),
            restDay: true,
          ),
        ),
      );
      expect(find.text(l10n.todayTomorrowRest), findsOneWidget);
      expect(find.text(l10n.todayTomorrowRevisions(6)), findsNothing);
      expect(find.text(l10n.todayEstimate(3)), findsNothing);
    });

    testWidgets('a backlog is not "cleared", and the button offers it', (
      tester,
    ) async {
      await pump(tester, view: artboardDone(backlog: 4));
      expect(find.textContaining(l10n.todayBacklogCleared), findsNothing);
      expect(
        tester.widget<PrimaryActionBar>(find.byType(PrimaryActionBar)).label,
        l10n.todayBacklogAction(4),
      );
    });
  });

  group('#97 a rest day', () {
    testWidgets('says so, with no plan and a safe streak', (tester) async {
      await pump(tester, view: artboardRest());

      expect(find.text(l10n.todayRestDay), findsOneWidget, reason: 'no name');
      expect(find.text(l10n.todayRestOff('Sunday')), findsOneWidget);
      final ring = tester.widget<DpProgressRing>(
        find.descendant(
          of: find.byType(ProgressRingCard),
          matching: find.byType(DpProgressRing),
        ),
      );
      expect(ring.countLabel, l10n.todayRestFree);
      expect(ring.caption, l10n.todayRestNoPlan);
      expect(find.text(l10n.todayStreak(12)), findsNothing);
      expect(find.bySemanticsLabel(l10n.todayStreak(12)), findsOneWidget);
    });

    testWidgets('Revise is optional, and opens a Revise-only session', (
      tester,
    ) async {
      await pump(tester, view: artboardRest());
      expect(find.text(l10n.todayReviseOptional(6)), findsOneWidget);

      await tapCard(tester, l10n.todayRevise(6));
      final blocks = session(tester)!.blocks;
      expect(blocks.single.kind, SessionBlockKind.revise);
      expect(blocks.single.uids, hasLength(6));
    });

    testWidgets('the note says what revising anyway buys: 12 → 6', (
      tester,
    ) async {
      await pump(tester, view: artboardRest());
      expect(find.text(l10n.todayRestNote), findsOneWidget);
      expect(find.text(l10n.todayRestLighterLead), findsOneWidget);
      expect(find.text(l10n.todayRestLighter(12, 6)), findsOneWidget);
    });

    testWidgets('with today revised, the note has nothing to promise', (
      tester,
    ) async {
      await pump(tester, view: artboardRest(reviseDone: 6));
      expect(find.text(l10n.todayRestNote), findsOneWidget);
      // Nothing open to revise: neither the lead nor a "12 → 12" after it.
      expect(find.text(l10n.todayRestLighterLead), findsNothing);
      expect(find.text(l10n.todayRestLighter(12, 12)), findsNothing);
    });

    testWidgets('the study-days link opens Reminder & days', (tester) async {
      await pump(tester, view: artboardRest());
      await tester.tap(find.text(l10n.todayRestStudyDays));
      await tester.pumpAndSettle();
      expect(location(), '/me/settings/reminder');
    });

    testWidgets('there is no grammar card and no new-word card', (
      tester,
    ) async {
      await pump(tester, view: artboardRest());
      expect(find.byType(GrammarPreviewCard), findsNothing);
      expect(card(l10n.todayNew(0)), findsNothing);
    });
  });

  group('FR-T1-06 the contextual card', () {
    late AppDatabase db;
    late SettingsRepository settings;

    /// Today with [offer], over real settings, so what a card writes can be
    /// read back.
    Future<void> show(WidgetTester tester, ContextualOffer offer) async {
      db = AppDatabase.memory();
      addTearDown(db.close);
      settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      await pump(
        tester,
        view: artboardToday(contextual: offer),
        also: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
      await tester.ensureVisible(find.byType(ContextualCard));
      await tester.pump();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ContextualCard),
          matching: find.text(text),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> dismiss(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(l10n.todayCardDismiss));
      await tester.pumpAndSettle();
    }

    testWidgets('sits after the plan, before the grammar card', (tester) async {
      await show(tester, const ContextualOffer(ContextualKind.voice));
      final card = tester.getTopLeft(find.byType(ContextualCard)).dy;
      expect(card, greaterThan(tester.getTopLeft(firstSection()).dy));
      expect(
        card,
        lessThan(tester.getTopLeft(find.byType(GrammarPreviewCard)).dy),
      );
    });

    testWidgets('BR-PLAN-07 the pause offer turns the pause on', (
      tester,
    ) async {
      await show(
        tester,
        const ContextualOffer(ContextualKind.pauseOffer, backlog: 30),
      );
      expect(find.text(l10n.todayCardPauseBody(30)), findsOneWidget);

      await tapText(tester, l10n.todayCardPauseAction);
      expect(settings.read(SettingKeys.pauseNewWhenBacklog), isTrue);
    });

    testWidgets('dismissing an offer records it in dismissed_cards', (
      tester,
    ) async {
      await show(tester, const ContextualOffer(ContextualKind.voice));
      await dismiss(tester);

      expect(settings.read(SettingKeys.dismissedCards), '["voice"]');
    });

    testWidgets('and keeps what was dismissed before', (tester) async {
      await show(
        tester,
        const ContextualOffer(ContextualKind.examsUnlocked, step: 'A2.1'),
      );
      await settings.write(SettingKeys.dismissedCards, '["voice"]');
      await dismiss(tester);

      expect(
        settings.read(SettingKeys.dismissedCards),
        '["voice","exams:A2.1"]',
      );
    });

    testWidgets('BR-CONTENT-03 dismissing an update marks it seen', (
      tester,
    ) async {
      await show(
        tester,
        const ContextualOffer(
          ContextualKind.contentUpdate,
          version: '202609201200',
          added: 12,
          removed: 3,
          changed: 40,
        ),
      );
      await db.customStatement(
        "INSERT INTO content_updates (version, seen, recorded_at) "
        "VALUES ('202609201200', 0, '2026-09-20T12:00:00Z')",
      );
      expect(find.text(l10n.todayCardUpdateBody(12, 3, 40)), findsOneWidget);

      await dismiss(tester);
      final row = await db
          .customSelect('SELECT seen FROM content_updates')
          .getSingle();
      expect(row.read<int>('seen'), 1);
      expect(settings.read(SettingKeys.dismissedCards), isNull);
    });

    testWidgets("BR-EXAM-01 exams open the step's exams tab", (tester) async {
      await show(
        tester,
        const ContextualOffer(
          ContextualKind.examsUnlocked,
          step: 'A2.1',
          percent: 91,
        ),
      );
      expect(find.text(l10n.todayCardExamsBody(91, 'A2.1')), findsOneWidget);

      await tapText(tester, l10n.todayCardExamsAction);
      expect(location(), '/learn/step/A2.1?tab=exams');
    });

    testWidgets('the voice card opens Voice & translation', (tester) async {
      await show(tester, const ContextualOffer(ContextualKind.voice));
      await tapText(tester, l10n.todayCardVoiceAction);
      expect(location(), '/me/models');
    });

    testWidgets('BR-COURSE-05 a finished step asks, and cannot be dismissed', (
      tester,
    ) async {
      await show(
        tester,
        const ContextualOffer(ContextualKind.stepComplete, step: 'A2.2'),
      );
      expect(find.text(l10n.todayCardStepBody('A2.2')), findsOneWidget);
      expect(find.text(l10n.todayCardStepAction), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.todayCardDismiss), findsNothing);
    });
  });

  group('FR-T1-05 midnight, on a real plan', () {
    late DateTime now;

    Future<void> open(WidgetTester tester, {DateTime? at}) async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      now = at ?? DateTime(2026, 9, 21, 23, 50);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            settingsProvider.overrideWithValue(settings),
            clockProvider.overrideWithValue(() => now),
            coachMarkProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const TodayScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Montag, 21. September'), findsOneWidget);
    }

    /// Away and back, step by step as the platform reports it: the listener
    /// only hears a transition it can make.
    Future<void> leaveUntil(WidgetTester tester, DateTime then) async {
      for (final state in const <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      now = then;
      for (final state in const <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('coming back after midnight is the next day', (tester) async {
      await open(tester);
      await leaveUntil(tester, DateTime(2026, 9, 22, 0, 10));

      expect(find.text('Dienstag, 22. September'), findsOneWidget);
    });

    testWidgets('coming back the same evening says good evening', (
      tester,
    ) async {
      await open(tester, at: DateTime(2026, 9, 21, 8));
      expect(find.text('Guten Morgen'), findsOneWidget);

      await leaveUntil(tester, DateTime(2026, 9, 21, 20));

      expect(find.text('Guten Abend'), findsOneWidget);
      expect(find.text('Montag, 21. September'), findsOneWidget);
    });

    testWidgets('and so is a pull after midnight', (tester) async {
      await open(tester);

      now = DateTime(2026, 9, 22, 0, 10);
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Dienstag, 22. September'), findsOneWidget);
    });
  });

  testWidgets('a pull that fails does not throw past the screen', (
    tester,
  ) async {
    var reads = 0;
    await pump(
      tester,
      load: todayViewProvider.overrideWith((ref) async {
        if (reads++ > 0) throw StateError('db');
        return artboardToday();
      }),
    );

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(reads, 2, reason: 'the pull read the plan again');
  });

  testWidgets("the Grammar due tile takes Cobalt's own ink", (tester) async {
    await pump(tester, view: artboardToday(grammarDue: 1));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: card(l10n.todayGrammarDue(1)),
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
    );
    expect(icon.color, DpPalette.light.onDer);
  });

  testWidgets('a failed load says so, with Retry', (tester) async {
    await pump(
      tester,
      load: todayViewProvider.overrideWith(
        (ref) async => throw StateError('db'),
      ),
    );
    expect(find.byType(DpErrorPanel), findsOneWidget);
    expect(find.text(l10n.todayLoadFailed), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
  });
}

/// A first launch's coach mark, without the settings behind it.
class _ShowingCoachMark extends CoachMark {
  @override
  bool build() => true;

  @override
  Future<void> markShown() async {}
}

/// The first section card, Revise, whichever state the day is in.
Finder firstSection() => find.byType(PlanSectionCard).first;
