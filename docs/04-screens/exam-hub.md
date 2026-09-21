# L10 · Mock exam hub · L11 · Exam intro

**Purpose.** Verify a finished step with exam-style tests.

**Prototype.** `ExamHub` (unlocked, A1.2), `ExamHubLocked` (A2.1), `ExamIntro`.

**Reached from.** L2 Exams tab, T1 "exams unlocked" card, M1 exam badge, L13 *Try another mock* / *Back*. **Leads to.** L11 → L12.

## L10 layout
- Locked: card "Unlocks when 90% of A2.1 is introduced · 184 of 486 words introduced · about 43 days at 7 a day" + *Study now* (→ T2).
- Unlocked: three cards *Mock 1 / 2 / 3*: status pill (*Passed 78%* Lime · *62% — not yet* Coral · *Not attempted*), "40 questions · ≈ 20 min · 2 attempts" (Mock 3: "seed 3 · no repeats within the step"), *Start*.
- "What's in these exams": "Vocabulary 10 · Reverse 8 · Articles 6 · Word forms 4 · Gap fill 6 · Grammar 4 · Listening 2 · Writing · Speaking" and the note "Generated practice exams from this step's words and grammar — not official Goethe or telc papers. Pass mark 60%." (locked variant adds "Change the unlock threshold in Settings").

## L11 layout
"A1.2 · Mock 2 · 40 questions · ≈ 20 min · pass mark 60% · your best: 62% (1 attempt)"; sections list in order with counts (Writing and Speaking marked *self-assessed*); Rules: no feedback until the end · you can flag questions and come back · the timer can be paused; *Timer on* switch ("≈ 20 min · turns Coral in the last 2 minutes"); *Begin exam*.

**Functional requirements**
- FR-L10-01 Unlock = introduced ÷ total ≥ `exam_unlock_percent` (BR-EXAM-01); "about n days" uses daily_new.
- FR-L10-02 Best score and attempts per seed from `exam_attempts` (finished only); an in-progress attempt shows *Resume* instead of *Start*.
- FR-L10-03 *Begin exam* creates the attempt and all answer rows (`03-domain/exam-generator.md`) in one transaction, then pushes `/exam/:attemptId`.
- FR-L10-04 Listening section is omitted (points redistributed) when `listening_questions = 0`.

**Business rules.** BR-EXAM-01…06.

**Tests.** unlock threshold; resume detection; generator no-repeat across seeds (data test on every step).
