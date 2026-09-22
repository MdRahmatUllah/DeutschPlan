import 'package:deutschplan/domain/plan_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// FR-S2-04 — the estimate on S2 page 4.
void main() {
  group('FR-S2-04 the estimate', () {
    test("is the artboard's own example", () {
      // "A1.1 takes about 69 days at 7 words a day" — the artboard's A1.1 has
      // 480 words, every day ticked.
      expect(courseDays(words: 480, dailyNew: 7, studyDaysMask: 127), 69);
    });

    test('stretches by 7 over the study days', () {
      // Weekdays only. The formula taken whole — 480 × 7 ÷ 35 — is 96
      // exactly. Rounding the study days first (69) and stretching those
      // would say 97; FR-S2-04 gives the one sum, so it is 96.
      expect(courseDays(words: 480, dailyNew: 7, studyDaysMask: 31), 96);
    });

    test('rounds a part day up, and an exact one not at all', () {
      expect(courseDays(words: 637, dailyNew: 7, studyDaysMask: 127), 91);
      expect(courseDays(words: 638, dailyNew: 7, studyDaysMask: 127), 92);
    });

    test('is integer arithmetic, not floating point', () {
      // 180 ÷ 7 × (7 ÷ 6) in doubles is 30.000000000000004, and rounding that
      // up says 31. Six days is Monday to Saturday.
      expect(courseDays(words: 180, dailyNew: 7, studyDaysMask: 63), 30);
    });

    test('has no answer without study days or new words', () {
      expect(courseDays(words: 480, dailyNew: 7, studyDaysMask: 0), isNull);
      expect(courseDays(words: 480, dailyNew: 0, studyDaysMask: 127), isNull);
    });
  });

  group('study days per week', () {
    test('count the bits Monday to Sunday, and nothing above them', () {
      expect(studyDaysPerWeek(127), 7);
      expect(studyDaysPerWeek(31), 5);
      expect(studyDaysPerWeek(1 << 6), 1, reason: 'Sunday alone');
      expect(studyDaysPerWeek(0), 0);
      expect(studyDaysPerWeek(1 << 7), 0, reason: 'bit 7 is not a day');
    });
  });
}
