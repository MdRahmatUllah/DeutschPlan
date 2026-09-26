---
name: pr-author-line
description: "Owner rule — every PR description starts with the agent's name (\"Agent-N\") on its first line"
metadata:
  type: feedback
---

Put the agent name on the first line of every PR description, e.g. `**Agent-2**`, above `Closes #N`.

**Why:** the owner (2026-09-25) reads the PR list to see which agent is doing what; the GitHub account is shared by all agents, so the author field can't tell them apart.

**How to apply:** when writing `gh pr create --body`, make line 1 `**Agent-N**` (your identity from `team.py join`), then the usual body ending with the Claude Code line. Related: [[basic-gate-per-pr]], [[merge-open-prs-first]].
