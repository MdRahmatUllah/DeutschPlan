# T1 · Today (home)

**Purpose.** Answer "what do I do now, and how long will it take" in one glance and one tap.

**Prototype.** `Today` (in progress), `TodayDone` (all done), `TodayRest` (rest day).

**Reached from.** Today tab, splash, notification, widget, closing any modal. **Leads to.** T2 (button, ring, Revise/New cards), T4 (Backlog card), T5 (Sentences card), L15 (Grammar due card), L2 (step chip → Learn tab), L4 (grammar-this-week card), L10 (exam card), M2 (streak pill), M3 (gear), M4 (voice card).

**Layout (top → bottom).**
1. Header block (Lagoon): German date "Montag, 21. September", greeting "Guten Morgen, {name}" (time-of-day; name optional), streak pill (Sun, flame + number), gear icon.
2. Ring card: 132 dp ring "12 / 20", "≈ 6 min"; right column: step chip "A2.1", "Day 34 of your course", mini bar "184 of 540 words in A2.1".
3. Plan section cards (72 dp): Revise · 10 — "10 words · due today"; New today · 7 — "7 new · {category}"; Backlog · 14 — "14 waiting from Tue–Wed" (only if > 0); Grammar due · n (only if > 0); Practice sentences · 3 — "3 sentences from words you know". Each shows a mini ring or an ink check when done.
4. Contextual card (max one), the first that applies: step complete (auto-advance off) · content update · backlog pause offer · exams unlocked · voice download · course complete. The course-complete card comes last because it cannot be dismissed: ahead of the others it would hide them for good.
5. "Grammar this week" card: next topic of the active step with a one-line rule preview.
6. Primary button (docked): label by state.

**Primary button labels (FR-T1-03).** `Start today · {n} cards` → `Continue · {n} left` → `Practice sentences · {n}` → `Review backlog · {n}` (only after today is done) → `All done — see you tomorrow` (Lime, disabled). Rest day: `Revise anyway · {n}`.

**States.**
- *First day*: Revise card reads "Revision starts tomorrow".
- *After setup* (FR-S2-03): the one-time coach mark "Start here · today's words are ready" points at the primary button. A tap on it, on the button, or on anything on T1 that opens T2 takes it away for good, and it never shows over a finished day (#396).
- *All done* (`TodayDone`): header "Tag geschafft, {name}", ring 20/20 Lime, one collapsed "Today · done" row ("Revise 10 · New 7 · Sentences 3 · backlog cleared"), a *Tomorrow* card ("12 revisions · 7 new · Grammar due · 1 · ≈ 13 min · {category} continues").
- *Rest day* (`TodayRest`): header "Rest day", ring shows "Frei · no plan", explanation "Sunday is off in your study days. The streak is safe." with a link to Settings; Revise card "6 words · optional today" (the block is filled to `revise_count` with words not yet due, BR-PLAN-03, so "words", not "due"); note "Nothing is scheduled and nothing moves to the backlog. Revising anyway keeps tomorrow lighter: 12 → 6 revisions." The count is what is due by the next study day, and when tomorrow is off too the note names that day: "keeps Tuesday lighter" (#345).
- *Course finished*: revision-only mode with a completion card: revisions are still planned, no new words, the backlog only shrinks; the completion card shows once no other contextual card is waiting.
- *Error*: `ErrorPanel` with Retry.

**Functional requirements**
- FR-T1-01 Opening MUST call `PlanEngine.openDay(today)` (idempotent) and render from the persisted plan.
- FR-T1-02 The ring MUST show completed ÷ (revise + new + grammar + sentences) for today; estimate per BR-PLAN-09.
- FR-T1-03 Button label per the table above; tapping starts a session with all open blocks in order Revise → New → Grammar.
- FR-T1-04 Tapping a section card starts a session with only that block; Backlog card opens T4.
- FR-T1-05 Pull-to-refresh MUST re-plan if the date changed; the plan also refreshes on app resume across midnight.
- FR-T1-06 At most one contextual card; dismiss persists in settings (`dismissed_cards` JSON).
- FR-T1-07 The backlog pause offer appears when backlog > 3 × daily_new (BR-PLAN-07) and a step is active — with the course finished there are no new words to pause; the content-update card while `content_updates.seen = 0` (BR-CONTENT-03).
- FR-T1-08 The step chip and the grammar card MUST switch to the Learn tab then push (navigation rules).

**Business rules.** BR-PLAN-01…10, BR-COURSE-05, BR-CONTENT-03.

**Motion.** Ring tweens from 0 on open (deliberate) and to new values after a session; numbers count up; section rings animate. Glass: header is a Lagoon glassTint panel.

**Data.** `todayPlanProvider(date)`, `streakProvider`, `settingsProvider`, `contentUpdatesProvider`.

**Developer notes.** `TodayScreen` composes `TodayHeader`, `ProgressRingCard`, `PlanSectionCard`, `ContextualCard`, `GrammarPreviewCard`, `PrimaryActionBar`. Date formatting uses `intl` with `de_DE` regardless of UI locale.

**Tests.** FR-T1-02 ring maths; FR-T1-03 label transitions (unit on a `TodayViewState`); FR-T1-05 midnight rollover with a fake clock; goldens for the three states × three themes.
