import 'package:deutschplan/domain/reminder_times.dart';
import 'package:flutter_test/flutter_test.dart';

/// #157: when the daily reminder fires.
void main() {
  // Monday 21 September 2026.
  List<DateTime> at(DateTime now, {int mask = 127}) =>
      reminderTimes(now: now, hour: 19, minute: 30, studyDaysMask: mask);

  test("a week of 19:30s, today's while it is still ahead", () {
    final morning = at(DateTime(2026, 9, 21, 8));
    expect(morning.first, DateTime(2026, 9, 21, 19, 30));
    expect(morning, hasLength(7));

    final evening = at(DateTime(2026, 9, 21, 20));
    expect(evening.first, DateTime(2026, 9, 22, 19, 30));
    expect(evening.last, DateTime(2026, 9, 28, 19, 30));
    expect(evening, hasLength(7));
  });

  test('study days only: Monday the lowest bit', () {
    // Mon, Wed, Fri.
    final days = at(DateTime(2026, 9, 21, 8), mask: 1 | 4 | 16);
    expect(days.map((d) => d.weekday), <int>[
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]);
    expect(at(DateTime(2026, 9, 21, 8), mask: 0), isEmpty);
  });

  test('each is 19:30 on its own date, across a daylight-saving change', () {
    // Europe goes back an hour on 25 October 2026.
    final week = at(DateTime(2026, 10, 22, 8));
    for (final day in week) {
      expect((day.hour, day.minute), (19, 30), reason: '$day');
    }
  });
}
