# R2 · Add / edit my word

**Purpose.** Save words met in real life (the spreadsheet's "Add Words").

**Prototype.** `AddWord`.

**Reached from.** R1 idle and no-results states, W1 *Edit* (custom words). **Leads to.** W1 (*Open* on a course match), back to R1 with the new word highlighted.

**Layout.** Header "My word" with copy "Words you meet in real life. Saved on this phone, quizzed like any other." Fields: Article (segmented der / die / das / none, gender-coloured), German (umlaut row), live check under it — "Already in the course · A1.2 · das Pfand" with *Open* and *Log it* ("counts one more real-life sighting") — Meaning, Where I saw it, Example sentence (optional). Buttons *Save*, *Save and add to revision*; Delete in edit mode.

**Functional requirements**
- FR-R2-01 Live check runs the exact-match search on every change (debounced).
- FR-R2-02 *Log it* increments `word_state.times_logged` (creating the row as `todo` if needed) and does not create a custom word.
- FR-R2-03 *Save* inserts `custom_words`; *Save and add to revision* also creates a `word_state`-like entry via the custom-word scheduling path (custom words are scheduled with the same FSRS, keyed `custom:<id>`).
- FR-R2-04 Custom words appear in Search idle "My words", in quizzes with source `allLearned` (opt-in setting), never in exams.

**Tests.** match detection; save paths.
