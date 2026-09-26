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

**Data.** `examRunServiceProvider` (`ExamRunService` over `ExamRepository`). The runner's state (the question on screen, the clock, the plays) is widget state: every answer and flag is written as it is given and the clock every 10 s, so the database is the attempt and a keepAlive notifier would only hold a second copy of it (#130).

**Developer notes.** A one-second timer in the screen; `duration_sec` is written every 10 s, so a crash loses ≤ 10 s, and the time left is derived from it. Disable predictive back in this route.

**Tests.** FR-L12-01 resume; FR-L12-03 timer/pause maths; widget: navigator jump and confirm.

## Details the runner settles (#130)

- **Numbering.** "Question 21 of 40" numbers the questions. Writing and Speaking are tasks, not numbered, so a full paper reads "of 40" with 42 items. The band names the section and the item's place in it ("Articles · 3 of 6").
- **The clock.** Seconds run into `duration_sec` and seconds paused into `paused_sec`, both written every 10 s (and on leaving), so a crash loses at most 10 s. Time left is 20 min (`examMinutes`) minus `duration_sec`. At 0:00 the exam submits without asking. A submit that fails keeps the learner on the paper with a toast, the clock running again; the answers are already written.
- **Pause is the leave dialog** (#132). The band's pause button opens it, as the ExamRunner artboard links it to ExamLeave, and so does back. While it's open the clock stops and the seconds count as paused ("The timer stops"). *Keep going* runs the clock again. *Leave* writes what was typed and the time, sets `status = abandoned` (FR-L12-04), and goes back to the hub. An abandoned attempt opened again (a deep link to `/exam/<id>`) goes back to the hub too: it is closed.
- **Timer off** (L11's switch, `SettingKeys.examTimer`, read when the runner opens, fresh or resumed): no clock and no auto-submit. `duration_sec` still counts, for L13's time.
- **When answers are written.** A tap (article, choice, word) is written at once. A typed answer is written when the learner moves on (*Previous*, *Next*, submit, leaving), so a crash loses at most the answer being typed.
- **What a grammar item records**, as #84 grades it: pick the form, the form; rule recall, the rule's index; spot the error, the word's index; order the sentence, the words in order joined by a space.
- **Listening** (FR-L12-06): one play and two replays, then the speaker is off. Gap: the plays are counted in memory, so a resumed attempt gives each word three plays again; persisting them waits for a column.
- **Submit** is the last question's button and the navigator's *Submit exam*. With questions unanswered, either one asks first (FR-L12-05). The confirm counts unanswered questions as the navigator does, numbered ones only ("20 questions are unanswered…"), and names empty Writing and Speaking tasks apart ("The writing and speaking tasks are empty."). It also asks when only the tasks are empty (#350). A recording still running is stopped and saved first, so the confirm counts it and the grading has it (#372). One submit runs at a time. A second tap, Speaking's Stop or the 0:00 tick while it stops the recorder or asks is turned away. At 0:00 with the confirm open, the clock holds at 0:00 and the paper submits once the learner answers. A recorder that fails to stop loses that take, not the exam: the paper is graded without it. A recording counts as answered with no rubric ticks, and the confirm doesn't ask about them: Speaking scores by its ticks, and L13 lets the learner set them afterwards (#135).
- **Speaking left mid-recording** (*Previous*, the navigator, leaving the exam) keeps what was said, under its own task, not the question moved to (#372).
- **The navigator** (#131) lists the numbered questions only; Writing and Speaking follow question 40 (Writing's button reads *Submit text*). A flagged question counts as flagged, answered or not, and "unanswered" counts every question with no answer, flagged ones included. The time in its title is the clock when it opened.
- **Writing with the keyboard up** (#529): the task and the text share a few lines on a phone, so the live count line ("N words · min 100" and the connectors found) takes the *Previous / Submit text* row's place above the keyboard, where it stays in view and gives the text that room. The buttons come back when the keyboard goes: a tap anywhere outside the text (the task, the band, the chips) closes it, as a multiline field has no *Done* key and iOS no back gesture that would; the umlaut keys, gaps included, count as the field. The other typed questions keep their buttons.
