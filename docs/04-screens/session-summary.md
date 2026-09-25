# T3 · Session summary

**Purpose.** Close the loop and point to the next useful action.

**Prototype.** `Summary` (sheet over the faded session).

**Reached from.** End of T2. **Leads to.** T2 again (the day's next block), L15 (*Practice grammar · 2*), T5 (*Practice 3 sentences*), T4 (*Review backlog · 14*), T1 (*Done for now*). Skipped entirely — T6 shown instead — when the day is complete and no sentences are open.

**Layout.** Bottom sheet, medium detent: "Gut gemacht!" · "20 cards · 12 min" · rating pills "2 Again · 3 Hard · 10 Good · 5 Easy" · "Words to watch" (≤ 5 Again-rated words with play) · buttons.

**Functional requirements**
- FR-T3-01 Counts come from the session's own results, not the day totals.
- FR-T3-02 Primary action MUST be the next open block in the day's order; secondary the backlog if any; *Done for now* always present.
- FR-T3-03 Dismissing the sheet (drag down) behaves as *Done for now*.

**Filled in by #328:**
- **The day's order** (BR-PLAN-02) is what FR-T3-02 walks: the day's open revisions (*Revise · 10*), then its open new words (*Learn new words · 15*), then grammar (the session's own, else the topics due today), then the day's sentences. "Open" is BR-PLAN-10's: neither done nor skipped. It matters after a partial session, one section card on Today (FR-T1-04) or T4's backlog (FR-T4-02), which leaves the day's other blocks waiting.
- **Continuing** starts that block as a new session in this one's place, so closing it returns to whoever opened the first. Its T3 then offers the next block.
- **The day is complete** for T6 only when the grammar due is done too, as Today's "Tag geschafft" counts it (BR-PLAN-10).

**Tests.** Widget: button set for the four combinations of (sentences open, backlog > 0).
