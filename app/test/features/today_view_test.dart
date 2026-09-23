import 'package:deutschplan/features/today/today_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'today_fixtures.dart';

/// T1's arithmetic, without a screen — #95.
void main() {
  group('FR-T1-02 the ring', () {
    test('is done over revise + new + grammar + sentences', () {
      // The artboard: Revise 10/10, New 2/7, no grammar, sentences 0/3.
      final view = artboardToday(grammarDue: 2);

      expect(view.completed, 12);
      expect(view.total, 10 + 7 + 2 + 3);
      expect(view.left, 10);
    });

    test('an empty day is 0 of 0, not a division', () {
      final view = artboardToday(reviseDone: 0, newDone: 0);
      expect(view.completed, 0);
    });
  });

  group('BR-PLAN-09 the caption', () {
    TodayView after(Duration estimate, {bool done = false}) => TodayView(
      date: '2026-09-21',
      hour: 9,
      revise: BlockProgress(done: done ? 1 : 0, total: 1),
      newToday: BlockProgress.none,
      openRevise: const <String>[],
      openNew: const <String>[],
      grammarDue: const <String>[],
      backlog: 0,
      streak: 0,
      estimate: estimate,
      courseDay: 2,
      stepWords: (done: 0, learning: 0, todo: 0, total: 0),
    );

    test('rounds up to whole minutes', () {
      expect(after(const Duration(seconds: 61)).estimateMinutes, 2);
      expect(after(const Duration(minutes: 6)).estimateMinutes, 6);
    });

    test('is never "≈ 0 min" while a card is open', () {
      expect(after(const Duration(seconds: 5)).estimateMinutes, 1);
    });

    test('is 0 with nothing left', () {
      expect(after(Duration.zero, done: true).estimateMinutes, 0);
    });
  });

  group('FR-T1-03 the button, every transition', () {
    TodayViewState of(TodayView view) => todayViewState(view);

    test('nothing done: Start today · every card', () {
      expect(
        of(artboardToday(reviseDone: 0, newDone: 0)),
        const TodayViewState(TodayAction.start, 20),
      );
    });

    test('something done: Continue · what is left, sentences included', () {
      // The artboard's 12 / 20: five new words and three sentences left.
      expect(of(artboardToday()), const TodayViewState(TodayAction.resume, 8));
    });

    test('grammar alone still open is still a study block', () {
      expect(
        of(artboardToday(reviseDone: 10, newDone: 7, grammarDue: 1)).action,
        TodayAction.resume,
      );
    });

    test('the study blocks done: Practice sentences · those left', () {
      expect(
        of(artboardToday(reviseDone: 10, newDone: 7, sentencesDone: 1)),
        const TodayViewState(TodayAction.sentences, 2),
      );
    });

    test('the day done with a backlog: Review backlog · its size', () {
      expect(
        of(artboardToday(reviseDone: 10, newDone: 7, sentencesDone: 3)),
        const TodayViewState(TodayAction.backlog, 14),
      );
    });

    test('the backlog waits until the day is done', () {
      // Sentences are still open, so they come first.
      expect(
        of(artboardToday(reviseDone: 10, newDone: 7)).action,
        TodayAction.sentences,
      );
    });

    test('nothing left and no backlog: All done, disabled', () {
      final state = of(
        artboardToday(reviseDone: 10, newDone: 7, sentencesDone: 3, backlog: 0),
      );
      expect(state, const TodayViewState(TodayAction.done));
      expect(state.enabled, isFalse);
    });

    test('BR-PLAN-01 a rest day with revisions: Revise anyway · those due', () {
      expect(
        of(artboardToday(reviseDone: 4, isStudyDay: false)),
        const TodayViewState(TodayAction.reviseAnyway, 6),
      );
    });

    test('a rest day with nothing due is done', () {
      expect(
        of(artboardToday(reviseDone: 10, isStudyDay: false)).action,
        TodayAction.done,
      );
    });

    test('only done is disabled', () {
      for (final action in TodayAction.values) {
        expect(
          TodayViewState(action).enabled,
          action != TodayAction.done,
          reason: action.name,
        );
      }
    });
  });

  group('#96 done', () {
    test('is a study day with everything planned done', () {
      expect(artboardDone().isDone, isTrue);
      expect(artboardToday().isDone, isFalse);
    });

    test('an empty day is not done: nothing was done on it', () {
      final empty = TodayView(
        date: '2026-09-21',
        hour: 9,
        revise: BlockProgress.none,
        newToday: BlockProgress.none,
        openRevise: const <String>[],
        openNew: const <String>[],
        grammarDue: const <String>[],
        backlog: 0,
        streak: 0,
        estimate: Duration.zero,
        courseDay: 3,
        stepWords: (done: 0, learning: 0, todo: 0, total: 0),
      );
      expect(empty.isDone, isFalse);
    });

    test('a rest day is never TodayDone', () {
      expect(
        artboardToday(
          reviseDone: 10,
          newDone: 7,
          sentencesDone: 3,
          isStudyDay: false,
        ).isDone,
        isFalse,
      );
    });
  });

  group('#97 rest day', () {
    test('revising anyway takes today\'s open revisions off tomorrow', () {
      expect(artboardRest().dueTomorrowIfRevised, 12 - 6);
      expect(artboardRest(reviseDone: 2).dueTomorrowIfRevised, 12 - 4);
    });

    test('never below zero', () {
      final view = artboardRest();
      expect(
        TodayView(
          date: view.date,
          hour: view.hour,
          revise: view.revise,
          newToday: view.newToday,
          openRevise: view.openRevise,
          openNew: view.openNew,
          grammarDue: view.grammarDue,
          isStudyDay: false,
          backlog: 0,
          streak: 0,
          estimate: Duration.zero,
          courseDay: 1,
          stepWords: view.stepWords,
          dueTomorrow: 2,
        ).dueTomorrowIfRevised,
        0,
      );
    });
  });

  group('FR-T1-06 contextual cards', () {
    ContextualKind? kind(ContextualFacts facts) => contextualFor(facts)?.kind;

    // Every offer applies at once, so each test can take one away.
    const everything = ContextualFacts(
      stepComplete: true,
      nextStep: 'A2.2',
      contentUpdate: (
        version: '202609201200',
        added: 12,
        removed: 3,
        changed: 40,
      ),
      backlog: 30,
      step: 'A2.1',
      introduced: 500,
      stepWords: 540,
      systemVoice: true,
    );

    test('nothing applies, nothing shows', () {
      expect(contextualFor(const ContextualFacts()), isNull);
    });

    test('the order: finished step, update, pause, exams, voice', () {
      expect(kind(everything), ContextualKind.stepComplete);
      expect(
        kind(
          const ContextualFacts(
            contentUpdate: (version: 'v', added: 1, removed: 0, changed: 0),
            backlog: 30,
            step: 'A2.1',
            introduced: 500,
            stepWords: 540,
            systemVoice: true,
          ),
        ),
        ContextualKind.contentUpdate,
      );
      expect(
        kind(
          const ContextualFacts(
            backlog: 30,
            step: 'A2.1',
            introduced: 500,
            stepWords: 540,
            systemVoice: true,
          ),
        ),
        ContextualKind.pauseOffer,
      );
      expect(
        kind(
          const ContextualFacts(
            step: 'A2.1',
            introduced: 500,
            stepWords: 540,
            systemVoice: true,
          ),
        ),
        ContextualKind.examsUnlocked,
      );
      expect(
        kind(const ContextualFacts(systemVoice: true)),
        ContextualKind.voice,
      );
    });

    test('BR-COURSE-05 the last step finished is the course', () {
      expect(
        kind(const ContextualFacts(stepComplete: true)),
        ContextualKind.courseComplete,
      );
      expect(contextualFor(everything)?.step, 'A2.2');
    });

    test('BR-CONTENT-03 the update carries its counts', () {
      final offer = contextualFor(
        const ContextualFacts(
          contentUpdate: (version: 'v1', added: 12, removed: 3, changed: 40),
        ),
      )!;
      expect(
        (offer.added, offer.removed, offer.changed, offer.version),
        (12, 3, 40, 'v1'),
      );
    });

    test('BR-PLAN-07 the pause offer needs more than 3 × daily_new', () {
      expect(kind(const ContextualFacts(backlog: 21)), isNull, reason: '= 3×');
      expect(
        kind(const ContextualFacts(backlog: 22)),
        ContextualKind.pauseOffer,
      );
      expect(
        kind(const ContextualFacts(backlog: 22, pauseOn: true)),
        isNull,
        reason: 'already paused',
      );
      expect(
        kind(const ContextualFacts(backlog: 16, dailyNew: 5)),
        ContextualKind.pauseOffer,
      );
    });

    test('BR-EXAM-01 exams unlock at exam_unlock_percent of the step', () {
      const at90 = ContextualFacts(
        step: 'A2.1',
        introduced: 486,
        stepWords: 540,
      );
      expect(kind(at90), ContextualKind.examsUnlocked);
      expect(contextualFor(at90)?.percent, 90);
      expect(
        kind(
          const ContextualFacts(step: 'A2.1', introduced: 485, stepWords: 540),
        ),
        isNull,
      );
      expect(
        kind(
          const ContextualFacts(
            step: 'A2.1',
            introduced: 400,
            stepWords: 540,
            examUnlockPercent: 70,
          ),
        ),
        ContextualKind.examsUnlocked,
      );
    });

    test('a dismissed offer gives way to the next', () {
      expect(
        kind(
          const ContextualFacts(
            dismissed: <String>{'pause'},
            backlog: 30,
            systemVoice: true,
          ),
        ),
        ContextualKind.voice,
      );
      expect(
        kind(
          const ContextualFacts(
            dismissed: <String>{'pause', 'voice'},
            backlog: 30,
            systemVoice: true,
          ),
        ),
        isNull,
      );
    });

    test("a step's exams dismissed do not hide the next step's", () {
      const facts = ContextualFacts(
        dismissed: <String>{'exams:A2.1'},
        step: 'A2.2',
        introduced: 500,
        stepWords: 540,
      );
      expect(kind(facts), ContextualKind.examsUnlocked);
    });

    test('dismissed_cards that cannot be read dismisses nothing', () {
      expect(dismissedIds(null), isEmpty);
      expect(dismissedIds('["voice","exams:A2.1"]'), <String>{
        'voice',
        'exams:A2.1',
      });
      for (final bad in <String>['', 'voice', '{"voice":1}', '[1, 2]', '[']) {
        expect(dismissedIds(bad), isEmpty, reason: bad);
      }
    });

    test('what must be answered cannot be dismissed away', () {
      expect(contextualFor(everything)!.dismissible, isFalse);
      expect(
        contextualFor(const ContextualFacts(stepComplete: true))!.dismissible,
        isFalse,
      );
      expect(
        contextualFor(
          const ContextualFacts(
            dismissed: <String>{'pause', 'voice', 'exams:A2.1'},
            stepComplete: true,
            nextStep: 'A2.2',
          ),
        )?.kind,
        ContextualKind.stepComplete,
      );
    });
  });

  test('the greeting follows the hour', () {
    expect(dayPart(0), DayPart.morning);
    expect(dayPart(10), DayPart.morning);
    expect(dayPart(11), DayPart.day);
    expect(dayPart(17), DayPart.day);
    expect(dayPart(18), DayPart.evening);
    expect(dayPart(23), DayPart.evening);
  });

  test('the date is German', () {
    expect(germanDate('2026-09-21'), 'Montag, 21. September');
    expect(germanDate('2026-03-29'), 'Sonntag, 29. März');
  });
}
