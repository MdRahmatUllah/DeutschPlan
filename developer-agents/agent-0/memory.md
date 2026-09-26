# agent-0's memory

What agent-0 (the lead) knows that the code and the docs don't tell you. Two parts:

1. **Board memory**, a snapshot of `agents/agent-0.md` on the `team` branch (last seen 2026-09-26 19:46). The live copy is always newer: read it first, at `<root>/dp-team/agent-0/agents/agent-0.md`.
2. **Shared memories** this role leans on. They are in [`../shared-memory/`](../shared-memory/), which every agent loads once it is restored (see [`../README.md`](../README.md)).

## Board memory (snapshot)

**Now:** #595 docs: the project handbook, the developer-agents folder, and branding — claimed 2026-09-26 19:46.

**Next:** v1.0.1 tagged. Watch for agent-3's 1.0.1 SQA report and route findings to 1.0.2 (agent-1/agent-2). Remind the owner: upload key, phone check, emulator-5558 OK.

**Notes for the next session:**

- Worktree: F:/appDevs/dp-wt/agent-0.
- Lane A: #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #133 → #134 → #135 → #136 → #169 → #170 → #171 → #175.
- #124's item widgets must be reusable by the exam runner #130 without verdicts. Reuse `PracticeHeader`/`PracticeStrip` (grammar_practice_screen.dart) and `StudyAnswerField` (study_cloze.dart).
- `QuizArgs` lives in `routes.dart` (no `timer` yet); `stepQuiz` (L2) and `categoryQuiz` (L6) already build it.
- Lead duties: review requests before new work; `team.py assign` when a lane is dry; close epics and milestones (PLAN.md); relay the owner's decisions (`reopen` + `remember decisions`).
- 2026-09-24 21:57: emulator-5558 (developers): onboarded learner on A1.1, exam_unlock_percent=0 (set via a debug build's run-as, then the release build installed over it), Mock 1 in progress. The exam screens (#131-#136) can be device-checked there.

## Shared memories for this role

- [keep-working](../shared-memory/keep-working.md): never idle-wait; parallel issues; keep agents assigned.
- [merge-open-prs-first](../shared-memory/merge-open-prs-first.md): open PRs before new work; ask an idle agent to review at once.
- [read-full-review](../shared-memory/read-full-review.md): read the whole latest review before merging.
- [no-merging-others-prs](../shared-memory/no-merging-others-prs.md): merging another agent's PR can be refused; then the author merges.
- [merge-then-delete](../shared-memory/merge-then-delete.md): delete a branch only once the PR is MERGED.
- [no-chaining-past-failure](../shared-memory/no-chaining-past-failure.md): tests, rebases, locks and builds are their own calls.
- [basic-gate-per-pr](../shared-memory/basic-gate-per-pr.md): basic check per PR; the full suite at milestone completion.
- [full-suite-j2](../shared-memory/full-suite-j2.md): how the full suite runs without being reaped for memory.
- [decision-resets-issue](../shared-memory/decision-resets-issue.md): raise owner questions on a new issue, not one in review.
- [v1-scope](../shared-memory/v1-scope.md): the owner's v1 scope decisions.
- [v1-release](../shared-memory/v1-release.md): v1.0.0 and v1.0.1: what was tagged and what is still the owner's.
- [m2-decisions](../shared-memory/m2-decisions.md): M2/M3 decisions and carry-overs from before the team.
- [ci-minutes](../shared-memory/ci-minutes.md): CI is off.
- [pr-author-line](../shared-memory/pr-author-line.md): **Agent-N** on line 1 of every PR body.

The project's own memory (the owner's rules, the decisions already made, the technical lessons) is `MEMORY.md` on the board. Read it every session.
