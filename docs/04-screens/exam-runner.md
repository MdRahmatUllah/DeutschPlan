# L12 · Exam runner (1/2 — questions, navigator, leaving)

**Purpose.** Run a timed, feedback-free mock exam that survives interruptions.

**Prototype.** `ExamRunner` (Articles question), `ExamNavigator` (question grid sheet), `ExamLeave` (leave dialog).

**Reached from.** L11. **Leads to.** L13 on submit or time-out; L10 on leave.

**Presentation.** Full-screen modal; iOS swipe-to-dismiss disabled; Android back opens the leave dialog.

**Layout.** Cobalt top band: section "Articles · 3 of 6", timer "14:32" (pause button; Coral in the last 2 min), grid icon → navigator. Sub-line "Question 21 of 40 · no feedback until the end". Body: one question per screen using the quiz item layouts (typed, article buttons, multiple choice, gap fill, listening) plus a flag icon. Footer *Previous* / *Next*.

**Navigator sheet.** "Questions · 14:32 left", legend Answered · 22 (Lagoon) / Flagged · 3 (Sun) / Empty · 15 (outline); 8-column grid of numbers; note "15 unanswered — submitting asks you to confirm"; *Submit exam*.

**Leave dialog.** "Leave the exam? Your answers so far are saved as an unfinished attempt. The timer stops. You can start Mock 2 again from the exam hub." Buttons *Keep going* / *Leave* (Coral).

**Functional requirements**
- FR-L12-01 Each answer is written to `exam_answers` immediately; the runner resumes from the first unanswered question after a restart.
- FR-L12-02 No verdicts are shown during the exam (BR-EXAM-05).
- FR-L12-03 Timer counts only while running; pause stores `paused_sec`; at 0:00 the exam auto-submits.
- Whether the timer runs at all is L11's *Timer on* switch, kept as the `exam_timer` setting: L11 writes it on *Begin exam* (its switch starts from `exam_timer_default`), and L12 reads it whenever it opens, fresh or resumed, so it survives Resume and process death. The time left is the limit minus `duration_sec`. Beginning another mock with the switch the other way and then resuming the first resumes it with the new value, which is fine for practice.
- FR-L12-04 Leaving sets `status = abandoned`; the hub shows it as an attempt without a score.
- FR-L12-05 Submit with unanswered questions requires confirmation.
- FR-L12-06 Listening questions play through TTS; replay allowed twice.

**Data.** `examAttemptProvider(id)`, `ExamRepository`.

**Developer notes.** Keep the timer in the notifier with a `Ticker`; persist `remaining_sec` every 10 s so a crash loses ≤ 10 s. Disable predictive back in this route.

**Tests.** FR-L12-01 resume; FR-L12-03 timer/pause maths; widget: navigator jump and confirm.

## Details the runner settles (#130)

- **Numbering.** "Question 21 of 40" numbers the questions. Writing and Speaking are tasks, not numbered, so a full paper reads "of 40" with 42 items. The band names the section and the item's place in it ("Articles · 3 of 6").
- **The clock.** Seconds run into `duration_sec` and seconds paused into `paused_sec`, both written every 10 s (and on leaving), so a crash loses at most 10 s. Time left is 20 min (`examMinutes`) minus `duration_sec`. *Pause* hides the paper until *Resume*. At 0:00 the exam submits without asking.
- **Timer off** (L11's switch, `SettingKeys.examTimer`, read when the runner opens, fresh or resumed): no clock and no auto-submit. `duration_sec` still counts, for L13's time.
- **When answers are written.** A tap (article, choice, word) is written at once. A typed answer is written when the learner moves on (*Previous*, *Next*, submit, leaving), so a crash loses at most the answer being typed.
- **What a grammar item records**, as #84 grades it: pick the form, the form; rule recall, the rule's index; spot the error, the word's index; order the sentence, the words in order joined by a space.
- **Listening** (FR-L12-06): one play and two replays, then the speaker is off.
- **Submit** is the last question's button. With questions unanswered it asks first (FR-L12-05); the navigator's *Submit exam* is #131's.
- Until #133 and #134, Writing and Speaking say they arrive in a later update, and a skipped task scores nothing (FR-L12S-01). The navigator icon is #131's, and the leave dialog's abandon is #132's.
