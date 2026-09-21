# T6 · Day complete

**Purpose.** A short, genuine reward for finishing the day.

**Prototype.** `DayComplete`.

**Reached from.** The last open item of the day (T2, T5 or L15). **Leads to.** T1 (tap anywhere or after 4 s).

**Layout.** Lime background (glass: Lime-tinted panel over aurora): ring completes and an ink check draws itself; 20 paper-cut confetti pieces (Lagoon, Sun, Raspberry, Cobalt) fall once for 1.2 s; "Tag geschafft!"; "17 words · 12 min"; streak "13 day streak" bumps; "Tomorrow: 12 revisions · 7 new"; *Back to Today*.

**Functional requirements**
- FR-T6-01 Shown at most once per day (`daily_stats.completed_shown = 1`).
- FR-T6-02 Tomorrow's numbers come from a dry-run `openDay(tomorrow)` that does not persist.
- FR-T6-03 No share prompts, ads or upsells. Reduced motion: static illustration, no confetti.

**Tests.** FR-T6-01 once per day; FR-T6-02 dry run leaves no rows.
