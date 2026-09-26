---
name: ci-minutes
description: "GitHub CI is OFF (workflows disabled 2026-09-24, #302/PR #303); the local gate is the only check — never wait on, watch or re-enable CI"
metadata:
  type: feedback
---

On 2026-09-24 the user said CI "wast our time" and asked to turn it off completely and tell the other agents. Done: `gh workflow disable CI` and `gh workflow disable "PR title"` (the workflow files stay; `gh workflow enable` would undo it — don't, unless the user asks). CLAUDE.md, ONBOARDING.md (step 14 "No CI", step 15 re-gate before merge), the dev guide, team.py's Now line and the board's MEMORY.md were updated in #302 / PR #303, and all agents got heads-up H-57.

**Why:** waiting on runs cost more time than it saved; the local gate (analyze, format, pytest, full `flutter test` with goldens) covers what CI ran.
**How to apply:** run the full gate before pushing and again before `gh pr merge` if origin/main moved; never `gh run watch` or wait for a run; check PR titles by hand; rebuild and verify the content pipeline locally when it changes. When reviewing, tell agents "merge on a green local gate", not "on green CI". Related: [[m2-decisions]].
