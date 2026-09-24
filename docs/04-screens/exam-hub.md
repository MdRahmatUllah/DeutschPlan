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
- Details L11 settles (#129):
  - The line is "40 questions · ≈ 20 min · pass mark n%", then "your best: n% (k attempts)" once the mock has a finished attempt, rounded down as L10's card is.
  - The sections are the learner's paper, in order with their counts: with listening off, Vocabulary 11 and Reverse 9, and no Listening (FR-L10-04). Writing and Speaking are marked *self-assessed*. The mark wraps under the name where the two don't fit, and neither is cut.
  - The *Timer on* switch starts from `exam_timer_default`. *Begin exam* keeps its value as `exam_timer`, which L12 reads fresh or resumed (`exam-runner.md`).
  - *Begin exam* (`ExamRepository.start`): the seed's stored paper, so a retake is the same mock whatever has changed since. The first sitting draws one against the other seeds' stored papers (`buildExam(sat:)`). A stored paper whose listening no longer matches the setting is drawn again in the same way. The paper is in the learner's meaning language (Bangla only when that is the setting). The attempt and its rows are one transaction; L12 opens on its id. A second tap while it runs begins nothing, and a failure says so and stays.
- Details L10 settles (#127):
  - A card's pill is its best finished score, rounded down so a fail never reads as the mark: *Passed n%* in Lime once any attempt passed, *n% — not yet* in Coral otherwise. With no attempt, *Not attempted*, unless one is under way, when *Resume* says it all. An attempt left unfinished counts in the line ("1 attempt") with no pill (FR-L12-04).
  - The line is "40 questions · ≈ 20 min", then the attempts once there are any, then Mock 3's "seed 3 · no repeats within the step". The note appears only where it is true. A mock whose paper shares grammar topics with another's (`Exam.reused`: steps with fewer than twelve topics, A1.1 to B1.2) reads "shares a few grammar topics with your other mocks" instead. A paper not sat yet is asked of the generator; a stored one is compared with the other stored papers. The 40 is BR-EXAM-03's questions with or without listening; the 20 minutes is the artboard's, fixed until the runner's timer (#130) says otherwise.
  - *Resume* opens the unfinished attempt in L12; *Start* opens L11 for that mock.
  - "What's in these exams" lists the sections as the learner's paper has them: with listening off, "Vocabulary 11 · Reverse 9 …" and no Listening (FR-L10-04). The pass mark is `exam_pass_percent`, and both settings are followed as they change.
  - The hub shows once the step's exams are unlocked (BR-EXAM-01) or it has been passed.
- Details the locked L10 settles (#128):
  - The target is `exam_unlock_percent` of the step's words, suspended ones left out as BR-EXAM-01 leaves them out, rounded up: 90 % of 540 is 486. The card reads "Unlocks when 90% of A2.1 is introduced", with a bar and "244 of 486 words introduced · about 35 days at 7 a day".
  - The days are FR-L2-01's reckoning (`courseDays`): the words left ÷ `daily_new` × 7 ÷ the study days, rounded up. A pace with no study days gives no days.
  - *Study now* opens today's session, as L1's *Study* does, or Today once the day is done.
  - The panel is the unlocked one's, and its footnote adds "Change the unlock threshold in Settings." The artboard's differently worded footnote isn't used: its "no repeated items" is not true of every step.
  - Solid Sun with an ink border on paper and dark; a Sun wash with a Lagoon *Study now* under glass.

**Business rules.** BR-EXAM-01…06.

**Tests.** unlock threshold; resume detection; generator no-repeat across seeds (data test on every step).
