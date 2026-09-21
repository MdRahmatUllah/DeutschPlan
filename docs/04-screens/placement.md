# S3 · Placement check and result

**Purpose.** Suggest a starting step for learners who already know some German.

**Prototype.** `Placement`, `PlacementResult`.

**Reached from.** S2 page 3. **Leads to.** S2 page 4 with the suggested step selected, or back to page 3.

**Layout.** Top bar: close, "Question 4 of 20", level tag ("A1 · word meaning"). One multiple-choice question (word meaning, article, or sentence gap) with four options; footer note "Two right answers in a row move you up a level; two wrong move you down. Nothing is saved until you choose a step." *Next* button.

Result: "Your result — 18 of 20 correct", suggested step in a large chip, one-sentence rationale, per-area breakdown (A1 words 9/10 · Articles 5/5 · A2 words 4/5), note that skipped steps stay browsable, buttons *Use A2.1* / *Choose myself*.

**Functional requirements**
- FR-S3-01 Adaptive: start at A1.1; two consecutive correct → next step; two consecutive wrong → previous step; 20 items max; stop early after 8 items if the level is stable for 3 items.
- FR-S3-02 Items are sampled from content with a fixed seed per session; distractors from the same POS.
- FR-S3-03 Nothing is written to `word_state`; the result only pre-selects the step (BR-COURSE-04).
- FR-S3-04 Abandoning (close) returns to page 3 with no changes.

**Tests.** Unit: level walk with scripted answers; widget: close discards.
