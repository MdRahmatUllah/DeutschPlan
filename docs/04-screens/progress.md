# M2 · Progress detail

**Prototype.** `Progress`.

**Reached from.** M1 cards, T1 streak pill. **Leads to.** L2 (step rows).

**Layout.** Segmented Week · Month · All. "Cards per day · this week · 85" bar chart (Revisions Lagoon, New Sun) by weekday. "Retention · 88% this week · target 90%" line chart (share of revisions rated Hard/Good/Easy) with the target line — shown only after 30 days of data, otherwise a note. "By step" rows with bars ("184 / 540"). Totals: "6 h 48 study time", "1,560 words introduced", "4,912 reviews", "12 / 19 streak / best".

**Functional requirements**
- FR-M2-01 Charts via `fl_chart` from `daily_stats` and `review_log`; retention = (ratings ≥ 2) ÷ all revision ratings per day, source `daily`.
- FR-M2-02 Best streak computed from `daily_stats` respecting rest days.
- FR-M2-03 Study time from `daily_stats.seconds`, accumulated per session.

**Tests.** retention maths; streak/best.
