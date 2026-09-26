# M7 · Reset

**Prototype.** `ResetDialog`.

**Reached from.** M3 → Reset. **Leads to.** M3; S2 after a full reset.

**Flow.** Sheet with two options: *Reset one step* (step picker → confirm) and *Reset everything*. Full reset dialog: "Reset everything? Deletes all progress, plans, quiz and exam history and my words on this phone. Export first if you might want it back. Type RESET to confirm." with a text field; *Cancel* / *Reset* (Coral, enabled only when the text equals RESET).

**Functional requirements**
- FR-M7-01 Reset one step: delete `word_state`, `plan_items`, `review_log` for that step's uids, its `grammar_state` rows, its exam and quiz attempts; the step becomes To-do; if it was active, or it is the only step there is (a finished one with auto-advance off), enrollment restarts today, planned anew. The undo stack is emptied. The course's first day (T1's "Day N of your course", M1's "Learning since") doesn't move: it is the earliest of the enrollments and the days studied, and a step reset leaves the days studied alone (#420). Only *Reset everything* starts the course over.
- FR-M7-02 Reset everything: empty every user table in one transaction (keep `theme_mode` and `ui_language`), delete the recordings (best effort, after the data), keep the models; then route to onboarding.
- FR-M7-03 Offer *Export first* inline before the destructive action.

**Tests.** per-step scope; full reset keeps theme/language and models.

## Details #149 settles

- **The sheet** (`features/me/reset_flow.dart`; the artboards draw only the dialog). It lists *Export first* ("Keep a file you can import later", in link colour), *Reset one step* and *Reset everything* (in Coral). *Export first* comes first and opens M6 (Export / import) over M3, before either reset (FR-M7-03).
- **One step** (FR-M7-01):
  - A second sheet, *Which step?*, lists the steps with something to reset, in course order: begun, or with a word, topic, quiz or mock of theirs touched. The current step is marked *Current*; with none, a toast says so.
  - A Coral confirm follows: "Reset A1.1? Its words go back to To do, with their reviews, plans, grammar, quizzes and mock exams." For the current step it adds "A1.1 starts again today."
  - It deletes, in one transaction:
    - for the step's word uids: `word_state`, `plan_items`, `review_log` and `sentence_log` (the per-word practice, which the FR leaves unnamed);
    - for its topic uids: `grammar_state` and `grammar_practice_log`;
    - its `exam_attempts` (their answers cascade) and its `stepLearned` quiz attempts;
    - the deleted mocks' Speaking recordings (`recordings/<id>.m4a`).
  - The current step's enrollment restarts today (`started_on`), and `last_planned_date` moves to yesterday, so today is planned again from the step started over. Another step's enrollment row is deleted: it is no longer started. Custom words belong to no step and stay.
  - M3 stays, with a toast "A1.1 is reset".
- **Everything** (FR-M7-02):
  - The dialog is `Adaptive.showTypedConfirm`: the platform's alert with a field. *Reset* stays off until the field holds RESET exactly (not "reset", not "RESET "). The word is RESET in every language. While it waits, *Reset* is Coral but faded; the artboard draws it full, but a control that does nothing yet shouldn't look ready.
  - The field opens focused, so the keyboard is up. Above it, the title, the message and the field scroll, and the actions stay under them. At 200 % or in Bangla they are taller than the room the keyboard leaves, and the actions used to cover the message and the field (#432). When the keyboard opens, the field comes into view with nothing typed yet, on both chromes: the dialog takes the keyboard's room at once rather than over the platform's 100 ms animation (Material's dialog and Cupertino's alert both animate it), which the field's reveal ran ahead of. On a budget phone at 150 % and 200 %, and on SQA's phone, the field had stayed hidden behind the actions or the keyboard until the learner typed (#586). The Cupertino actions draw Bangla in the app's Bengali font.
  - Resetting deletes every table an export carries, plus `translation_cache` and `undo_stack`. Of `settings`, only `theme_mode` and `ui_language` stay.
  - All recordings are deleted. The models and the course content are not touched.
  - The app then goes to S2's first page, since the router never sends anyone to onboarding by itself. The setup draft, the study session, the plan engine and Today's plan are invalidated.
- A write that fails leaves the data as it was (one transaction) and says "Couldn't reset. Nothing was changed."
