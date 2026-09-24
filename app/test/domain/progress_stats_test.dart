import 'package:deutschplan/domain/plan_stats.dart';
import 'package:deutschplan/domain/progress_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// M2's maths — #145.
void main() {
  // Thursday 24 September 2026.
  const today = '2026-09-24';

  group('the days', () {
    test('Week is this week, Monday to Sunday', () {
      expect(rangeDays(ProgressRange.week, today), <String>[
        '2026-09-21',
        '2026-09-22',
        '2026-09-23',
        '2026-09-24',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
      ]);
    });

    test('Month is the last 30 days to today', () {
      final days = rangeDays(ProgressRange.month, today);
      expect(
        (days.length, days.first, days.last),
        (30, '2026-08-26', '2026-09-24'),
      );
    });
  });

  group('the bars', () {
    const days = <DayCounts>[
      // A row with nothing in it (a rating undone): not where All begins.
      (day: '2026-05-10', reviews: 0, newWords: 0),
      (day: '2026-07-30', reviews: 4, newWords: 7),
      (day: '2026-09-21', reviews: 11, newWords: 6),
      (day: '2026-09-24', reviews: 20, newWords: 6),
    ];

    test('a day each, the empty days zero', () {
      final week = progressBars(ProgressRange.week, today, days);
      expect(week, hasLength(7));
      expect((week[0].reviews, week[0].newWords), (11, 6));
      expect((week[1].reviews, week[1].newWords), (0, 0));
    });

    test('All: a month each, from the first month with anything done', () {
      final all = progressBars(ProgressRange.all, today, days);
      expect(all.map((b) => b.start), <String>[
        '2026-07-01',
        '2026-08-01',
        '2026-09-01',
      ]);
      expect((all[0].reviews, all[0].newWords), (4, 7));
      expect((all[1].reviews, all[1].newWords), (0, 0));
      expect((all[2].reviews, all[2].newWords), (31, 12));
    });

    test('All with nothing done has no bars', () {
      expect(
        progressBars(ProgressRange.all, today, const <DayCounts>[]),
        isEmpty,
      );
    });
  });

  test('FR-M2-01 retention: Hard, Good and Easy remembered, Again not', () {
    expect(retention(<int>[1, 2, 3, 4]), 0.75);
    expect(retention(<int>[1]), 0);
    expect(retention(const <int>[]), isNull);
  });

  test('retention shows after 30 days of data', () {
    expect(retentionReady(null, today), isFalse);
    expect(retentionReady('2026-08-26', today), isFalse);
    expect(retentionReady('2026-08-25', today), isTrue);
  });

  group('FR-M2-02 the best streak', () {
    bool weekdays(String day) =>
        DateTime.parse(day).weekday < DateTime.saturday;

    test('the longest run there has been', () {
      expect(
        longestStreak(
          activeDays: <String>{
            '2026-09-01',
            '2026-09-02',
            '2026-09-03',
            '2026-09-07',
            '2026-09-08',
          },
          isStudyDay: (_) => true,
          today: today,
        ),
        3,
      );
    });

    test('a rest day carries the run without lengthening it', () {
      // Thu 3, Fri 4, (Sat, Sun rest), Mon 7: one run of three.
      expect(
        longestStreak(
          activeDays: <String>{'2026-09-03', '2026-09-04', '2026-09-07'},
          isStudyDay: weekdays,
          today: today,
        ),
        3,
      );
    });

    test('nothing done is none', () {
      expect(
        longestStreak(
          activeDays: const <String>{},
          isStudyDay: (_) => true,
          today: today,
        ),
        0,
      );
    });
  });
}
