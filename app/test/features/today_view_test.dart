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

  group('FR-T1-03 the in-progress labels', () {
    test('nothing done starts the day', () {
      expect(
        todayAction(artboardToday(reviseDone: 0, newDone: 0)),
        TodayAction.start,
      );
    });

    test('something done continues it', () {
      expect(todayAction(artboardToday()), TodayAction.resume);
    });

    test('sentences still to do keep the day going', () {
      // Sentences are part of the day, so Revise and New alone do not end it.
      // Nothing left at all is the widget test's "done, and disabled".
      expect(
        todayAction(artboardToday(reviseDone: 10, newDone: 7)),
        TodayAction.resume,
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
