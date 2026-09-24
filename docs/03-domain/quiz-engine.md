# Quiz engine

`domain/quiz_builder.dart` builds a `Quiz` from `QuizArgs(direction, length, source, timer, seed)`.

- Sources: `stepLearned(code)` (default), `allLearned`, `category(id)`, `compareSet(uids)`.
- Directions: `deEn`, `deBn`, `enDe`, `articles`, `listening`, `forms`, `mixed` (round-robin of the above that apply).
- Eligible words: status learning/done, not suspended; `articles` needs an article; `forms` needs a non-empty `forms` cell parsed into `(label, form)` pairs (`fasst zusammen · hat zusammengefasst` → 3rd person, Perfekt; `-en` / `Häuser` → plural).
- Selection: seeded shuffle, prefer words with the lowest retrievability so quizzes double as revision.
- Multiple-choice distractors: same POS, same step where possible, never a synonym of the answer.
- Flow: immediate feedback per item (`answer_check`), wrong items re-asked once at the end (BR-QUIZ-01), each answer also rated into FSRS (BR-FSRS-03, source `quiz`).
- Result: score, time, mistakes; actions *Retry mistakes* (new Quiz from the mistake uids), *Add mistakes to revision* (already rated Again — this button re-schedules them for tomorrow explicitly).

## Details the builder settles (#81)

- **Learned** means `word_state.status` learning or done, which also leaves suspended words out (BR-STATUS-03). `compareSet`'s `sourceRef` is the uids, comma-separated. `category`'s is the category id; `stepLearned`'s is the step code.
- **Selection.** The words are ranked by retrievability on the day (a never-reviewed word counts as 0). The quiz is drawn, in a seeded shuffle, from the weakest twice-`length`: the words most likely forgotten dominate, but a retry isn't the same quiz. The same seed over the same progress builds the same quiz. A quiz is shorter than `length` when fewer words qualify.
- **What each item asks.** `prompt` is shown and `expected` is checked by `answer_check`:

  | Direction | Prompt | Expected | Check |
  |---|---|---|---|
  | deEn | the headword with its article | the meaning list | `checkMeaning` |
  | deBn | the headword | the Bangla meaning (needs one) | `checkMeaning` |
  | enDe | the meaning | the headword | `checkGerman` |
  | articles | the noun without its article | `der`/`die`/`das` (needs one) | `checkArticle` |
  | listening | the headword, played | the headword, typed | `checkGerman` |
  | forms | the word | one form, with its label | `checkForm` |

- **Forms labels.** `plural` for a noun (the cell is the plural, or an ending such as `-en`). For a verb or phrase, `thirdPerson` · `perfekt` (`geht · ist gegangen`). For an adjective or adverb, `comparative` · `superlative` (`besser · am besten`). A cell with three parts is a synonym set, not forms, and isn't asked.
- **Mixed** gives item *i* the first direction, starting at position *i* of the rotation (deEn, deBn, enDe, articles, listening, forms), that applies to its word.
- **Re-asks (FR-L8-03, #125).** After the quiz, every item not answered correctly is asked once more, in quiz order. An almost counts as a mistake too, since L9 lists a typo ("die Kausion") among the mistakes. A re-ask is asked once, whatever its answer. It changes neither the score nor FSRS (the first answer already rated the word), and it only sets `quiz_answers.re_asked`. The counter shows the re-asks' own "2 / 4" under a *Once more* chip. `domain/quiz_queue.dart` holds the order.
- **Multiple choice.** Every meaning item (deEn, deBn, enDe) carries four tiles: the answer and three distractors, in a seeded order. The runner and the exam generator decide when to show tiles instead of a text field. The quiz runner (#124) shows them for DE → বাংলা only (`QuizItem.tiles`): typing Bangla needs a Bangla keyboard, which a learner of German can't be assumed to have. DE → EN and EN → DE are typed, as `quiz.md` lays them out. Distractors come from the word's step (every word, whatever its status) and the learned words. They are ranked same part of speech and step first, then other steps, then other parts of speech. They never share a meaning with the answer, never appear in its `synonyms_register` cell (or it in theirs), and never repeat a tile.
