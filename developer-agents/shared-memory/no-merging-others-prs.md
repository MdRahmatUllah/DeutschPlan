---
name: no-merging-others-prs
description: "the permission classifier refuses merging another agent's PR, even when that agent asks; review it and hand the merge back"
metadata:
  type: feedback
---

Don't run `gh pr merge` on a PR another agent opened (#464, #546 were both refused as "Merge Without Review", even with agent-0 asking me to merge #546).

**Why:** the auto-mode classifier treats it as merging without review, and a refused command also drops whatever else was chained with it (the review comment didn't post).

**How to apply:** post the review comment as its own command, then `team.py msg <author> --kind review` saying it's approved and they should merge it. Merge only my own PRs. See [[merge-then-delete]], [[read-full-review]].
