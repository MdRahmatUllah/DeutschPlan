# T6 · Day complete

**Purpose.** A short, genuine reward for finishing the day.

**Prototype.** `DayComplete`.

**Reached from.** The last open item of the day (T2, T5 or L15). From T2, once the last card's *Undo* bar has gone (FR-T2-02, #689 TD-9). **Leads to.** T1 (tap anywhere or after 4 s; under a screen reader on a tap only, as nothing times out for its user: WCAG 2.2.1, #689 TD-13).

**Layout.** Lime background (glass: Lime-tinted panel over aurora): ring completes and an ink check draws itself; 20 paper-cut confetti pieces (Lagoon, Sun, Raspberry, Cobalt) fall once for 1.2 s; "Tag geschafft!" (German in every UI language, read in a German voice, #689 TD-12); "17 words · 12 min" (the words studied: revised, and new ones rated or known; a new word skipped to the backlog is done for the plan but not studied, #729); streak "13 day streak" bumps; "Tomorrow: 12 revisions · 7 new"; *Back to Today*.

**Functional requirements**
- FR-T6-01 Shown at most once per day (`daily_stats.completed_shown = 1`). It is claimed for the plan day the finished session studied (`?day=`, from T2's session, T5 and L15, each of which reads its day when it opens, never when it finishes, #884). A session that crossed midnight finished yesterday's plan: T6 goes straight to Today, claiming nothing, so today's T6 is still to come (#660). A claim or a view that fails to read goes straight to Today too, rather than to a load-failed panel: the celebration is optional (#677). A claim that succeeded before the view failed has spent today's T6 unseen (#886).
- FR-T6-02 Tomorrow's numbers come from a dry-run `openDay(tomorrow)` that does not persist.
- FR-T6-03 No share prompts, ads or upsells. Reduced motion: static illustration, no confetti.

**Tests.** FR-T6-01 once per day; FR-T6-02 dry run leaves no rows.
