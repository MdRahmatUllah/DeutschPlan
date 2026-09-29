# T4 · Backlog

**Purpose.** Hold missed or skipped new words without pressure.

**Prototype.** `Backlog`, `BacklogEmpty`.

**Reached from.** T1 Backlog card, T3, M1 schedule card. **Leads to.** T2 (all or one day), W1 (row).

**Layout.** Header "Backlog · 14 words" with copy "From Tue and Wed — take them when you have time. Nothing here is overdue." (weekdays while the oldest day is within the last six, dates past that, as T1's card, #821) Top card: *Study all · 14* + switch "Pause new words until this is clear — Revisions continue as normal". Groups by original date, newest first: "Wed 16 Sep · 7 words" + *Study this day* (its row at least 48 dp, 44 pt on iOS, for the button's target, #689 TD-14) + word rows (article-coloured headword, meaning, status chip).

Empty: illustration, "Nothing waiting. Nice.", "Skipped or missed new words land here, without a deadline.", *Back to Today*.

**Functional requirements**
- FR-T4-01 Rows are `plan_items` with kind new, uncompleted, plan_date < today, grouped by plan_date desc (BR-PLAN-05).
- FR-T4-02 *Study all* / *Study this day* open T2 with exactly those items as a single "Backlog" block.
- FR-T4-03 The pause switch writes `pause_new_when_backlog` (BR-PLAN-07) and takes effect from the next plan generation.
- FR-T4-04 Row actions (iOS trailing swipe / Android long-press; on either, a focused row's context-menu key or Shift+F10, and a screen reader's custom actions, #1039): *Mark known*, *Suspend*, *Remove from course* (= suspend + complete the plan item). A suspended word stays listed with its status, so it can be resumed. It is left out of *Study all* and *Study this day*, and out of Today's backlog count and the backlog pause (BR-PLAN-07). The list follows its words' state, so a word suspended or resumed from W1 over T4 shows it at once, and W1's *Suspend* keeps the row, as this one does (#368). A second tap on a word's action while the first is written (the iOS strip, a screen reader's actions) does nothing (#689 TD-7). The iOS strip fills them Lagoon, Sun and Oat (never red, FR-T4-05), each label in its fill's own ink, 4.5:1 in light and dark (#735). Each action's *Undo* takes back only that action: *Mark known*'s undoes the rating it made and nothing else, so a rating made since, on a screen with no *Undo*, stays, of another word (#728) or of this one (#888); *Suspend* or *Remove* on a word already suspended leaves it suspended on *Undo* (#728).
- FR-T4-05 Never show overdue styling or red.

**Tests.** FR-T4-01 grouping; FR-T4-03 pause stops generation; empty state golden.
