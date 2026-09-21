# M7 · Reset

**Prototype.** `ResetDialog`.

**Reached from.** M3 → Reset. **Leads to.** M3; S2 after a full reset.

**Flow.** Sheet with two options: *Reset one step* (step picker → confirm) and *Reset everything*. Full reset dialog: "Reset everything? Deletes all progress, plans, quiz and exam history and my words on this phone. Export first if you might want it back. Type RESET to confirm." with a text field; *Cancel* / *Reset* (Coral, enabled only when the text equals RESET).

**Functional requirements**
- FR-M7-01 Reset one step: delete `word_state`, `plan_items`, `review_log` for that step's uids, its `grammar_state` rows, its exam and quiz attempts; the step becomes To-do; if it was active, enrollment restarts today.
- FR-M7-02 Reset everything: recreate `user.db` from the schema (keep `theme_mode` and `ui_language`), delete recordings, cancel downloads? — no: models are kept; then route to onboarding.
- FR-M7-03 Offer *Export first* inline before the destructive action.

**Tests.** per-step scope; full reset keeps theme/language and models.
