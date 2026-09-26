---
name: m2-decisions
description: Product decisions the user made for DeutschPlan M2 (report-a-problem goes to GitHub issues)
metadata:
  type: project
---

- Study overflow "Report a problem" (#100) opens the repo's GitHub new-issue page (MdRahmatUllah/DeutschPlan) with details prefilled — chosen 2026-09-23. The docs never gave a destination.
- Still undecided by the user: #245 (Supertonic voice size/manifest), #239 (FSRS doc mismatch), branch protection on main (needs admin).

**Why:** the app has no server or account, so a report needs an external destination.
**How to apply:** use the GitHub link; don't invent an email address. See [[ci-minutes]].

**M2 carry-overs (2026-09-23):**
- #105 → #107: the last card's rating Undo is lost because the session auto-closes on finish (and the pop hides the bar). #107's summary sheet must replace the auto-close and a test must undo the last card from under the summary. PR #261 review thread says so.
- #104 was done after #105 on purpose (cloze needs the rating bar).
- Merge, then rebase stacked branches as SEPARATE steps; check `gh pr view N --json state` = MERGED first. Also check that a push really reached the PR (`gh api .../pulls/N --jq .head.sha`). Once GitHub did not sync a PR head until it was closed and reopened.

**M2 done (2026-09-24):** #95–#111 merged (T6 = PR 268); epic #8 closed. The emulator's storage is tight, so debug APKs don't fit; use release x64.

**M3 (the user's standing goal, 2026-09-24): do all 12 without asking.** Order: #112 L1 → #113 L2 shell → #114 words → #115 grammar tab → #116 quiz tiles → #117 L3 library → #118 L4 topic → #82 generator → #119 L15 → #120 L5 → #121 L6, then close epic #9.
- L1 added `stepProgressProvider` (a grouped drift query in word_queries.drift; `unlocked` is computed in the repository from exam_unlock_percent), `CourseLevel` (German band names A1–B1 plus the band palette, for reuse by L2/L3), `openBlocks`/`originOf` in today_screen.dart, a compact DpButton, a DpPill icon, DpSurface.glassOutline, DpSegmentedBar.colours, and the palette token onAccentMark.
- Artboards: PNGs are in docs/design/<set>/; the glass set has no PNGs, so render them with scratchpad art.py (headless Edge).
- Progress (2026-09-24): #112 (PR 269), #113 (270), #114 (271) and #115 (272) merged; #116 is PR 273. Stacked-branch recipe: stash, `git rebase --onto origin/main <old-base> <branch>`, stash pop.
- Emulator: when uiautomator dumps come back empty, the system process has usually stalled (an ANR dialog); `adb reboot` fixes it. Device scripts must `rm -f /sdcard/ui.xml` before each dump, or a stale dump fools them.
- todayStub pins todayProvider to 2026-09-21 and stubs stepWords/stepCategories/stepTopics/lastStepQuiz/stepProgress; a screen test that needs different data passes its own override list instead.
- Progress (2026-09-24, later): #116–#120 merged (PRs 273–278; #82 = PR 275, #119 = 277, #120 = 278). #121 L6 is PR 279 (CI green). After it merges, close epic #9. That completes M3; M2 was already done.
- Deliberate M3 choices: L6 *Quiz* pushes the quiz route with source `category` (there is no standalone L7), gated at 10 learned words like L2's tiles. On iOS, AdaptiveScaffold's bar is a NavigationToolbar, so a long title moves clear of the back label. WordRow caps the headword at 1 line (content.db has phrases up to 61 characters). Today counts grammar practised in L15 through `todayGrammarDue` (watches grammar_state), and the plan's list stays the day's total.
