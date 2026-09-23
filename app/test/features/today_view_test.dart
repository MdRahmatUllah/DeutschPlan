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
