# Business rules (canonical)

Every rule has an ID. Engines in `03-domain/` implement them; screens in `04-screens/` reference them; tests assert them.

## Course structure

- **BR-COURSE-01** The course has 6 CEFR levels and 12 steps: `A1.1, A1.2, A2.1, A2.2, B1.1, B1.2, B2.1, B2.2, C1.1, C1.2, C2.1, C2.2`, in that fixed order.
- **BR-COURSE-02** A word belongs to exactly one step. Its level comes from the workbook's `Level` column; its step is assigned by the content pipeline at the week boundary nearest the middle of the level (see `02-data/content-pipeline.md`).
- **BR-COURSE-03** Grammar topics are split between X.1 and X.2 by count, keeping teaching order.
- **BR-COURSE-04** A learner can browse any step at any time. Studying (new words) happens only in the *active* step. Exactly one step is active at a time.
- **BR-COURSE-05** Auto-advance (default on): when every word of the active step has been planned, the next step becomes active automatically on the next study day. With auto-advance off, Today shows "Step complete" and offers *Start next step*.

## Word status

- **BR-STATUS-01** Statuses: `todo` (never introduced), `learning` (introduced, still being reviewed), `done` (FSRS stability ≥ `done_stability_days`, default 7), `suspended` (paused by the learner).
- **BR-STATUS-02** `done` is derived, never set by hand. A lapse (rating Again) can move a word from `done` back to `learning`.
- **BR-STATUS-03** `suspended` words are excluded from plans, revision, quizzes, exams and practice sentences until resumed. Suspension keeps FSRS state. Suspending a word drops its open plan rows. A rating never changes a suspended word's status (#351): the schedule still moves, and *Resume* derives the status from it.
- **BR-STATUS-04** "I know it" on a new word = first review rated Easy.

## Daily plan

- **BR-PLAN-01** A study day is any weekday enabled in `study_days_mask` (default all seven). Non-study days are *rest days*: no new words, no backlog growth, streak preserved; revisions are optional.
- **BR-PLAN-02** On a study day the plan is: Revise (`revise_count`, default 10) → New today (`daily_new`, default 7, from the active step in teaching order) → Grammar due (topics whose FSRS due ≤ today) → Practice sentences (`sentence_count`, default 3).
- **BR-PLAN-03** Revise picks FSRS-due words first (earliest due), then fills with the lowest-retrievability learned words, excluding today's new words. It never exceeds `revise_count`; excess due cards wait.
- **BR-PLAN-04** Plans are generated when a day is first opened and persisted. Reopening the same day shows the same plan.
- **BR-PLAN-05** Missed days are generated retroactively (up to `backlog_catchup_days`, default 30). Any new word planned for a past date and not completed is the **Backlog**.
- **BR-PLAN-06** *Skip* leaves a new word uncompleted; it appears in the backlog from the next day. Backlog has no deadline and is never shown as overdue.
- **BR-PLAN-07** Backlog pause: when on, no new words are planned until the backlog is empty; revisions continue. Today offers this when backlog > 3 × `daily_new`.
- **BR-PLAN-08** Changes to `daily_new`, `revise_count`, `study_days_mask` take effect from the next day; today's plan is fixed.
- **BR-PLAN-09** Time estimate = 25 s per revision + 45 s per new word + 60 s per grammar topic + 40 s per sentence, replaced by the learner's own median timings once ≥ 7 sessions exist.
- **BR-PLAN-10** Day complete = every plan item of today is completed or skipped, and no grammar/sentence item is open. Rest days count as complete for streak purposes.

## Scheduling (FSRS)

- **BR-FSRS-01** Scheduler is FSRS-4.5 with the published default weights; `desired_retention` default 0.90 (settable 0.80–0.97).
- **BR-FSRS-02** Ratings: 1 Again · 2 Hard · 3 Good · 4 Easy. Every rating is logged in `review_log` with source (`daily`, `quiz`, `exam`, `search`, `known`, `sentence`).
- **BR-FSRS-03** Quiz/exam results feed FSRS: correct → Good, almost → Hard, wrong → Again. "Add missed to revision" = rate Again.
- **BR-FSRS-04** Practice sentence "Not yet" rates the headword Hard.
- **BR-FSRS-05** Grammar topics use the same scheduler in `grammar_state`; a practice set is rated as a whole (all correct → Good, one wrong → Hard, more → Again).
- **BR-FSRS-06** A word switches to the **cloze card** format after two consecutive Good/Easy ratings. The learner can switch it back from Word detail.

## Answers

- **BR-ANS-01** DE→EN: any synonym in the `/`- or `,`-separated list counts; case and a leading "to " are ignored; one-character typos on words ≥ 6 letters are *almost*.
- **BR-ANS-02** EN→DE: the word with or without its article; umlauts as ä/ae/a, ü/ue/u, ö/oe/o, ß/ss; a wrong article on a correct noun is *wrong article* (counts as wrong for scoring, but the feedback names the article).
- **BR-ANS-03** Articles quiz: exact match of der/die/das.
- **BR-ANS-04** *Almost* scores 0.5 in quizzes and exams.

## Search

- **BR-SEARCH-01** Result order: Exact match → Starts with → Similar words → In sentences. Within a tier, higher frequency first.
- **BR-SEARCH-02** Exact match ignores article, case and umlaut spelling; matches English synonyms exactly and Bangla exactly.
- **BR-SEARCH-03** Similar = trigram candidates within edit distance ≤ 2 (≤ 3 for queries > 5 chars).
- **BR-SEARCH-04** Web search opens Duden, DWDS, Wiktionary, Linguee or Google in an in-app browser. Nothing is sent by the app itself.

## Quizzes and exams

- **BR-QUIZ-01** Quiz sources: this step's learned words (default), all learned, a category. Lengths 10/20/30. Wrong answers are re-asked once at the end.
- **BR-EXAM-01** Mock exams unlock when ≥ `exam_unlock_percent` (default 90) of the step's words are introduced.
- **BR-EXAM-02** Three mocks per step, generated by one algorithm with seeds 1–3; items never repeat across a step's three mocks. *Try another mock* uses the next unused seed.
- **BR-EXAM-03** Sections and counts: Vocabulary 10 · Reverse 8 · Articles 6 · Word forms 4 · Gap fill 6 · Grammar 4 · Listening 2 · Writing 1 · Speaking 1. Points: 1 per item, Writing 4, Speaking 4 → 48 points.
- **BR-EXAM-04** Pass mark `exam_pass_percent` (default 60). Passing any mock marks the step *Passed*.
- **BR-EXAM-05** No feedback during the exam. Leaving saves an unfinished attempt; the timer stops.
- **BR-EXAM-06** Writing and Speaking are self-assessed with app-side checks (words used, length, connectors) plus a four-item rubric; recordings stay on device.

## Content updates

- **BR-CONTENT-01** Word identity is the uid hash of `level | german | pos | english`. Progress is keyed by uid and survives content updates.
- **BR-CONTENT-02** New words join their step's To-do queue in teaching order; removed words are hidden but their history stays; changed meanings show an *updated* chip for 7 days.
- **BR-CONTENT-03** Today shows a one-time update card with counts.

## Privacy

- **BR-PRIV-01** No network call is made without a user action (web link, model download, export share).
- **BR-PRIV-02** All learner data lives in `user.db` and app-private files. Export is a JSON file the learner shares themselves.
