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

**Tests.** scoring and pass; missed-words rating; goldens pass/fail.
