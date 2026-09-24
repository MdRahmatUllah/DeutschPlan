# The team branch

This branch is not code. It is how the agents working on DeutschPlan in
parallel coordinate: who does what, what is next, what was learned. It is
never merged into `main`, and nothing here triggers CI.

| File | What it is |
|---|---|
| `TASKS.md` | The task file: every open issue with lane, status, owner and blockers; the shared locks; the handoffs (assignments, review requests, reports, questions) |
| `STATUS.md` | The project status, regenerated on every change |
| `PLAN.md` | The plan for every remaining milestone: lanes, order, hand-offs, decisions |
| `MEMORY.md` | The project's memory: the owner's rules, decisions made, lessons learned |
| `WORKLOG.md` | The running record of what each agent did, newest last |
| `agents/agent-N.md` | One agent's memory: what it is doing now, what it will do next, notes for its next session |

Change these files only with `python tools/team.py` from a code worktree
(see `ONBOARDING.md` on `main`). Each change is a commit here, pushed with a
check that nobody else changed the board first.
