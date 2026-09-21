# T3 · Session summary

**Purpose.** Close the loop and point to the next useful action.

**Prototype.** `Summary` (sheet over the faded session).

**Reached from.** End of T2. **Leads to.** T5 (*Practice 3 sentences*), T4 (*Review backlog · 14*), T1 (*Done for now*). Skipped entirely — T6 shown instead — when the day is complete and no sentences are open.

**Layout.** Bottom sheet, medium detent: "Gut gemacht!" · "20 cards · 12 min" · rating pills "2 Again · 3 Hard · 10 Good · 5 Easy" · "Words to watch" (≤ 5 Again-rated words with play) · buttons.

**Functional requirements**
- FR-T3-01 Counts come from the session's own results, not the day totals.
- FR-T3-02 Primary action MUST be the next open block in the day's order; secondary the backlog if any; *Done for now* always present.
- FR-T3-03 Dismissing the sheet (drag down) behaves as *Done for now*.

**Tests.** Widget: button set for the four combinations of (sentences open, backlog > 0).
