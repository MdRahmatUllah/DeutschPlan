# Quiz engine

`domain/quiz_builder.dart` builds a `Quiz` from `QuizArgs(direction, length, source, timer, seed)`.

- Sources: `stepLearned(code)` (default), `allLearned`, `category(id)`, `compareSet(uids)`.
- Directions: `deEn`, `deBn`, `enDe`, `articles`, `listening`, `forms`, `mixed` (round-robin of the above that apply).
- Eligible words: status learning/done, not suspended; `articles` needs an article; `forms` needs a non-empty `forms` cell parsed into `(label, form)` pairs (`fasst zusammen · hat zusammengefasst` → 3rd person, Perfekt; `-en` / `Häuser` → plural).
- Selection: seeded shuffle, prefer words with the lowest retrievability so quizzes double as revision.
- Multiple-choice distractors: same POS, same step where possible, never a synonym of the answer.
- Flow: immediate feedback per item (`answer_check`), wrong items re-asked once at the end (BR-QUIZ-01), each answer also rated into FSRS (BR-FSRS-03, source `quiz`).
- Result: score, time, mistakes; actions *Retry mistakes* (new Quiz from the mistake uids), *Add mistakes to revision* (already rated Again — this button re-schedules them for tomorrow explicitly).
