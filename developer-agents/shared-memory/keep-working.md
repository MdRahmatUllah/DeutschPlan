---
name: keep-working
description: "Owner rule — never stop or idle-wait; keep taking new issues, run them in parallel, and keep the other agents assigned until development is complete"
metadata:
  type: feedback
---

Don't stop and wait while subagents, reviews or other agents run. Take the next issue in parallel (a second worktree plus a subagent), assign and notify the other agents, and keep going until development (M7) is complete.

**Why:** the owner, on 2026-09-25, after I sat waiting on a subagent and two reviews: "do not stop until the development is complete. take new issues and notify other agents and work. do not stop working".

**How to apply:** while something runs in the background, start the next ready issue: M7 P1s first, then SQA follow-ups. Keep each agent's queue two deep, via `team.py assign` and `msg`. Still respect memory: at most two heavy test runs at once, and check free RAM first. Related: [[merge-open-prs-first]], [[basic-gate-per-pr]].
