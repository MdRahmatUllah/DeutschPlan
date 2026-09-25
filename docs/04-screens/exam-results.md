# L13 · Exam results · L14 · Exam review

**Prototype.** `ExamResults`, `ExamReview`.

**Reached from.** L12 submit. **Leads to.** L14 (*Review answers*), L10 (*Try another mock*), L2 (*Back to step*), W1 (*Open word*), L4 (*See rule*).

## L13 layout
Block: "Bestanden!" (Lime, badge scale-in with one glow pulse) or "Noch nicht" (Coral); "77%" display; "37 of 48 points"; pass-mark tick at 60 % on a bar; sub-line "A1.2 · Mock 2 · 18:41 · +15 points vs attempt 1 (62%)". "By section" list: Vocabulary 8 / 10 … Writing 3 / 4 *self-assessed*, Speaking 3 / 4 *self-assessed*. Buttons *Review answers*, *Add missed words to revision · 9*, *Try another mock*, *Back to step*.

## L14 layout
Filter chips All · 40, Wrong only · 9, Flagged · 3. Cards per question: "Q3 · Vocabulary · Wrong", the item, "Your answer: house", "Correct: flat, apartment", explanation (example sentence with translation, or the grammar rule "Nouns ending in -ung are feminine.") and *Open word* / *See rule*.

**Functional requirements**
- FR-L13-01 Score = points ÷ max (BR-EXAM-03); `passed` per BR-EXAM-04; comparison with the previous finished attempt of the same step.
- FR-L13-02 *Add missed words to revision* rates every wrong word item Again (source `exam`) and sets due = tomorrow.
- FR-L13-03 Rubric ticks for Writing can be edited here if not done in the runner; editing recomputes the score.
- FR-L14-01 Explanations: word items → first example; grammar items → topic rule with link; articles → rule-of-thumb from the grammar content when available.

## Details L13 settles (#135)

- **Where it is.** L12 shows L13 in the paper's place after the submit, in the same route (`/exam/:attemptId`), and L14 in L13's. A finished attempt opened again (a deep link, a restore) opens on L13. Close (a back arrow on Android, a cross on iOS), system back and the iOS swipe, and *Try another mock* all go to the step's exam hub (L10, L2's Exams tab), never to L11 under the route; *Back to step* goes to L2. The hub offers the next unused mock first, which is how *Try another mock* meets BR-EXAM-02's "the next unused seed".
- **The score.** The percentage is rounded down, so 59.9 % never reads as the 60 % that passes. Points show a half when Writing's rubric adds one ("36.5"). "Bestanden!" on Lime (`easy`) or "Noch nicht" on Coral (`again`) follows the attempt's `passed`. The pass-mark tick sits at `exam_pass_percent`. No artboard draws the fail state; it is the pass layout on Coral, with a cross in the badge.
- **The line.** "A1.2 · Mock 2 · 18:41": the step, the mock and how long the paper ran (`duration_sec`, paused time left out).
- **The comparison.** It is against the step's previous *finished* attempt, of any mock, by `finished_at`. Its number is its place among the step's finished attempts ("vs attempt 1"). An abandoned or unfinished attempt is never compared. A first attempt has no comparison.
- **The sections.** They follow BR-EXAM-03's order, each with its points out of its maximum (1 an item, 4 a task). The bar is Lime whatever the result.
- **The rubric** (FR-L13-03). Writing's and Speaking's rows read "self-assessed ›" and open their rubric in a sheet: Writing's two ticks (task covered · structure, 0.5 each), Speaking's four as the runner left them. Each tick is written and the paper graded again at once, with the submit's finish time and `status` kept, so the score, the badge and `passed` follow. #84 counts the ticks only with a text (Writing) or a recording (Speaking), so without one the ticks are shown dimmed and the sheet says they count nothing. Speaking's sheet also has *Delete recording* (FR-L12S-04), asked first: it removes the file, clears the answer and grades again.
- **Missed words** (FR-L13-02). A word item (every section but Grammar, Writing and Speaking) that scored under its point is missed, once per word, *almost* included. Only words the plan has already introduced go to revision: a paper can draw a word before the plan teaches it (the exams open at 90 % introduced), and that word keeps its new-word card. *Add missed words to revision · 9* rates each Again (source `exam`) and makes it due tomorrow, once per visit; then a toast, or on a failure a toast and the button again. With none missed the button is disabled.
- **Motion.** The badge scales in over the first third of 1.2 s with one pulse of its halo, and stands still with reduce motion.

**Tests.** scoring and pass; missed-words rating; goldens pass/fail.
