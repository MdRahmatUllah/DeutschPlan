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
- FR-L12-04 Leaving sets `status = abandoned`; the hub shows it as an attempt without a score.
- FR-L12-05 Submit with unanswered questions requires confirmation.
- FR-L12-06 Listening questions play through TTS; replay allowed twice.

**Data.** `examAttemptProvider(id)`, `ExamRepository`.

**Developer notes.** Keep the timer in the notifier with a `Ticker`; persist `remaining_sec` every 10 s so a crash loses ≤ 10 s. Disable predictive back in this route.

**Tests.** FR-L12-01 resume; FR-L12-03 timer/pause maths; widget: navigator jump and confirm.
