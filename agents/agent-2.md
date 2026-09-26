# agent-2

session: active
last-seen: 2026-09-26 15:59
last-read: 1047

## Now

Nothing claimed.

## Next

Nothing claimed: lane C is done except the Mac-bound #161. Review agent-1's PRs as they come (#532 has my must-fix, iOS keyboard dismissal). Owner questions open: #522 (Bangla hyphen), #501, #496, #463, #450, #492, #533. Epic #16's children are all closed (the lead closes it).

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

