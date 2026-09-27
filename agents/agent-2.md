# agent-2

session: active
last-seen: 2026-09-27 23:13
last-read: 1808

## Now

#752 in review as PR #967: answer review threads; re-run the gate if main moved, then merge.

## Next

Queue empty. 1.0.1 is ready: gate green on 4dfd9d52 (#17), release PR #594 approved; it waits for the owner's go and the v1.0.1 tag (agent-0). Take whatever agent-0 sends next.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Worktree: F:/appDevs/dp-wt/agent-2 (create it: ONBOARDING.md §2).
- Lane C: #144 → #83 (after #81) → #84 → #127 → #129 (hand to agent-0 for #130) → #128 → #146 → #157 → #158 → #159 → #160 → #147 → #145 → #148 → #149 → #150 → #172 → #161 → #162 → #165 → #168.
- #144: data from `stepProgressProvider`, `PlanEngine.streak`, daily_stats, `ExamRepository.watchStepPassed`; replace the `MeRoute` placeholder and the router tests that assert 'M1'.
- #83: `ExamRepository` (begin/finish/ExamScore) already exists; the generator's output maps to `ExamQuestion(ord, section, prompt, itemRef, optionsJson, expected)`; reuse `grammar_item_generator.dart` and quiz_builder (#81). `skill_prompts` in content.db looks broken — a spec gap to flag.
- #127 replaces the Exams-tab stub in `step_detail_screen.dart` (`ponytail: (#127, #128)`).
- #146 unblocks #147, #148, #150 and #155 (agent-1 waits on it). New settings keys go in `setting_keys.dart` AND `docs/02-data/user-database.md` (a test compares them). main.dart's glass comment says #143 — wiring the glass theme is #146's job.
- Native files (AndroidManifest.xml, Info.plist) are also touched by agent-0's #134: rebase often.
- 2026-09-25 20:56: Bangla digits rule (#425): int ARB placeholders need format decimalPattern; numbers the code writes go through l10n.digits; l10n_test guards both. plant.py counts any output without 'All tests passed!' as CAUGHT: wrap pytest to print Flutter's verdict. A plant that makes the course tests slow can hang plant.py past its timeout (shell=True leaves flutter_tester running): run such plants against one test with --plain-name. Worktree agent-2-b has stale codegen: run build_runner + pub get before a check there.
- 2026-09-26 07:25: Typography chain, stacked: #498 (#419, main worktree feat/419-hyphen) -> #505 (#502, base feat/419-hyphen) -> #507 (#504, base feat/502-mixed-hyphen), last two in agent-2-b. Merge in order: squash #498, then in agent-2-b 'git rebase --onto origin/main feat/419-hyphen feat/502-mixed-hyphen', force-push, retarget #505 to main (gh pr edit 505 --base main), merge; same for #507 onto main. Plants: scratchpad plants419/502/504.json. Asked agent-0 about #154 (H-692) and for a lane X assignment (H-703).
- 2026-09-26 09:42: 2026-09-26: typography chain merged (#498/#505/#507: _Hyphenated on runs, banglaBreaks, DpText(breakTooWide:), UAX #14 LB13 in the planner). #514 moved enableHymtDownload to model_repository.dart. #526: DpUmlautBar.scrollPadding, StudyAnswerField(umlautRowBelow:). Full suite green at 689929de (4081 + 329). Merged agent-0's #495/#493 while it was idle.
- 2026-09-26 19:26: This session (2026-09-26): #551, #557, #560, #564, #568, #573, #577, #580, #584, #586 and #590 are merged. The golden audit now runs 150/200 % in en and bn, with a keyboard pass at 200 % (expectKeyboardFits: each field in SQA's room, status bar 24, keyboard top 396). DpTextRole.oneStepSmaller exists for 'what is asked, one role smaller while typing past 130 %'. Lessons: a board issue's Dependencies text blocks claims (keep it free of issue numbers you don't mean). Tests: a reveal depends on the caret's position (enterText vs a prefill) and on the order of keyboard and focus. Resizing the window with a dialog open isn't faithful. Stash, don't checkout, your own edits.
- 2026-09-26 19:35 (end of session): v1.0.1 tagged (0d23968e). Nothing open for agent-2; every remaining issue is Later (iOS needs a Mac; #533 and #154 are the owner's). SQA's 1.0.1 device pass goes into 1.0.2.
- 2026-09-27 09:42: Stopped (usage limit). In review: #644 as PR #790 and #605 as PR #801. #725 is claimed, and branch feat/725-l13-error-exit in dp-wt/agent-2-b has no changes yet. Plan: L13's error state (exam_results_screen.dart:130-140) becomes an SgErrorPanel with Retry (invalidate examResultProvider) and a way out to LearnRoute, and back is allowed when step is null. Then the P2s in my list; #649 and #652 wait for #790 (both touch main.dart).
- 2026-09-27 15:50: In review: #875 (#668), #881 (#879). #606 waits for the owner's decision. A reviewer subagent was reviewing #874/#876/#852 when the usage limit hit; check those PRs' state and comments. New issues filed: #877, #883-#886.
- 2026-09-27 19:06: In review: #920 (#912, two rounds incl. agent-0's L4/T4 sites), #931 (#891). A reviewer subagent was reviewing #926/#928/#929 at the usage limit: check their PR comments. Closed #909/#910 as dupes of #906; #883 closed via #887. New memory: read issue comments before closing.
- 2026-09-27 21:59: Open: #946 (test-only, main red since #934 met #936: agent-0 to review, then merge), #939 (#821 + #754 Today batch). Local, not pushed (2-PR limit): feat/853-a11y-targets in F:/appDevs/dp-wt/agent-2 = #815 (L2 Words NestedScrollView) + #853 (chip rows 8/8, L6 spacing 14, L7/R1 runSpacing 16, T6 ring label, M2 plural); all tests + 1258 goldens pass; push + PR (Closes #815, Closes #853) once a slot frees; rebase and re-run test/data too. Filed #951 (owner decision, M1 badges) and #952 (remaining Wraps). Next batch: #751 #752 #854.

