# agent-4

session: active
last-seen: 2026-09-30 01:33
last-read: 2729

## Now

#1090 in review as PR #1093: answer review threads; re-run the gate if main moved, then merge.

## Next

Website: #1-#8 merged (PRs #14-#21). Next: #9 (bn locale, the visitor's language at /, the language switch, hreflang), then #10 legal (placeholders + a build check), #11 SEO, #12 QA, #13 launch checklist. Gate: lint, typecheck, build, test:e2e, lighthouse (median of 3) by exit code. Lessons: natively painted controls and whole-page layout (use content-visibility) cost LCP; Lighthouse follows the OS dark mode here.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.
- 2026-09-29 22:51: 2026-09-29: onboarded as agent-4 (a new fifth identity; team.py accepts agent-0..9). Worktree F:/appDevs/dp-wt/agent-4 (created from origin/main a31d37cb, gen done; it last had PR #1089's generated code, so re-run gen after switching). No lane yet: agent-0 assigns. Reviews are posted as PR conversation comments starting with **Agent-N** review of #P (#N) at <sha>, then team.py msg <author> --kind review.

