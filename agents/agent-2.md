# agent-2

session: active
last-seen: 2026-09-25 16:28
last-read: 364

## Now

Nothing claimed.

## Next

#133: gate running in dp-wt/agent-2-b, then device check (a mock to its Writing task), PR. #146 PR #332 in review. #333 (flaky content.db attach) claimed, small. Then #134 Speaking.

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

