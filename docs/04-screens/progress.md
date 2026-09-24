# M2 · Progress detail

**Prototype.** `Progress`.

**Reached from.** M1 cards, T1 streak pill. **Leads to.** L2 (step rows).

**Layout.** Segmented Week · Month · All. "Cards per day · this week · 85" bar chart (Revisions Lagoon, New Sun) by weekday. "Retention · 88% this week · target 90%" line chart (share of revisions rated Hard/Good/Easy) with the target line — shown only after 30 days of data, otherwise a note. "By step" rows with bars ("184 / 540"). Totals: "6 h 48 study time", "1,560 words introduced", "4,912 reviews", "12 / 19 streak / best".

Details M2 settles (#145):
- **Week** is this week, Monday to Sunday; **Month** the last 30 days, a bar a day, named every seventh; **All** a bar a month, from the first month with anything done ("Cards per month"). The corner reads "this week · 85", "last 30 days · …", "all time · …".
- A bar stacks the day's revisions (Lagoon) under its new words (Sun), each outlined in ink; a day with nothing done is a grey sliver. The order and the legend carry it without the colours, and a screen reader hears each bar: "Mo: 11 revisions, 6 new".
- **Retention** (FR-M2-01) counts the daily session's revisions: ratings of a word seen before (`elapsed_days` over 0), by the local day they were given — a new word's first rating is not a revision. The corner is the period's share against `desired_retention`; the dashed line is the target. "Shown only after 30 days of data" means the first day with anything done is 30 days back; until then the card says how many days are left. A period with no revisions says "No revisions this week".
- **By step** lists the steps begun or passed: done in Lime, learning in Sun, "184 / 540" as done of the step's words, and the row opens L2.
- **Totals**: study time is `daily_stats.seconds` summed ("6 h 48", or "40 min" under an hour); words introduced are the words met — a day introduced or a rating, as `WordRepository` tells To-do from the rest; reviews are every rating given. The best streak (FR-M2-02) is the longest run in `daily_stats`, rest days carrying it as the streak does. Rest days are today's study days: the mask a past week had isn't kept.

**Functional requirements**
- FR-M2-01 Charts via `fl_chart` from `daily_stats` and `review_log`; retention = (ratings ≥ 2) ÷ all revision ratings per day, source `daily`.
- FR-M2-02 Best streak computed from `daily_stats` respecting rest days.
- FR-M2-03 Study time from `daily_stats.seconds`, accumulated per session.

**Tests.** retention maths; streak/best.
