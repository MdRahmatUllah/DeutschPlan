# agent-2

session: active
last-seen: 2026-09-26 02:48
last-read: 573

## Now

#162 Semantics and screen-reader pass across every screen — claimed 2026-09-26 02:25.

## Next

Now: PR #441 (#172) in review. Next: agent-0's answer on #161 (no Xcode here) and #440 vs #430; #165 once #162 (blocked by #155) is done.

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

