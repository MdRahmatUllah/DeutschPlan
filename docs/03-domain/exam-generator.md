# Mock exam generator

`domain/exam_generator.dart` — one algorithm, seeded (BR-EXAM-02).

```
ExamGenerator(step, seed).build() → Exam(sections)
```

1. Pool = all words of the step (any status, suspended excluded) and all grammar topics of the step.
2. RNG = `Random(hash(step, seed))`. A step-level exclusion set is built from the *other* seeds' item ids so the three mocks never share an item; when the pool is smaller than 3 × demand, the least-recently-used items are reused and the hub says so.
3. Sections (BR-EXAM-03): Vocabulary 10 (DE→meaning, typed) · Reverse 8 (meaning→DE, typed, article optional) · Articles 6 (nouns only) · Word forms 4 (from `forms`) · Gap fill 6 (example sentence with the headword blanked; cloze check) · Grammar 4 (items from `GrammarItemGenerator` for the step's topics) · Listening 2 (TTS plays the word/sentence; type it; skipped if listening disabled — points redistributed) · Writing 1 · Speaking 1.
4. Points: 1 per item; Writing 4 (app checks 2: ≥ 6 target words used, ≥ minimum length; rubric 2 × 0.5 each) ; Speaking 4 (rubric 4 × 1). Max 48. Score % = points / max.
5. Writing prompt: template per level × topic category with 10 target words from the step; minimum words A1 30 · A2 60 · B1 100 · B2 150 · C1 200 · C2 250. Connector check uses the step's grammar connector list.
6. Speaking prompt: template per level (60 s A1–A2, 90 s B1–B2, 120 s C1–C2); one retake.

Persistence: on *Begin exam* an `exam_attempts` row is created with all `exam_answers` pre-inserted (prompt, options, expected); answering updates rows in place, so a crash resumes exactly. Timer: `duration_sec` accumulates only while running; pauses are recorded.

Grading on submit: `answer_check` per item; Listening compares the typed text with `checkGerman`; Writing app-checks computed from the text; rubric ticks stored in `self_rubric_json`. `passed = score% >= exam_pass_percent`. Passing marks the step (query, not a flag: any finished passed attempt for the step).
