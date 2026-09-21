# T4 · Backlog

**Purpose.** Hold missed or skipped new words without pressure.

**Prototype.** `Backlog`, `BacklogEmpty`.

**Reached from.** T1 Backlog card, T3, M1 schedule card. **Leads to.** T2 (all or one day), W1 (row).

**Layout.** Header "Backlog · 14 words" with copy "From Tue and Wed — take them when you have time. Nothing here is overdue." Top card: *Study all · 14* + switch "Pause new words until this is clear — Revisions continue as normal". Groups by original date, newest first: "Wed 16 Sep · 7 words" + *Study this day* + word rows (article-coloured headword, meaning, status chip).

Empty: illustration, "Nothing waiting. Nice.", "Skipped or missed new words land here, without a deadline.", *Back to Today*.

**Functional requirements**
- FR-T4-01 Rows are `plan_items` with kind new, uncompleted, plan_date < today, grouped by plan_date desc (BR-PLAN-05).
- FR-T4-02 *Study all* / *Study this day* open T2 with exactly those items as a single "Backlog" block.
- FR-T4-03 The pause switch writes `pause_new_when_backlog` (BR-PLAN-07) and takes effect from the next plan generation.
- FR-T4-04 Row actions (iOS trailing swipe / Android long-press): *Mark known*, *Suspend*, *Remove from course* (= suspend + complete the plan item).
- FR-T4-05 Never show overdue styling or red.

**Tests.** FR-T4-01 grouping; FR-T4-03 pause stops generation; empty state golden.
