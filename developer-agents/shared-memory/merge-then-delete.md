---
name: merge-then-delete
description: "Delete a PR's head branch only after confirming the PR is MERGED; deleting it first closes the PR"
metadata:
  type: feedback
---

Delete a PR's remote branch only after `gh pr view N --json state` says MERGED. Never chain `gh pr merge … ; git push origin --delete …` unconditionally.

**Why:** on 2026-09-24, `gh pr merge 329` failed with "not mergeable" (GitHub hadn't recomputed after a force push), and the next command in the chain deleted the head branch. GitHub then closed #329 unmerged. Recovery: push the branch again, `gh pr reopen`, wait until `mergeable` is not UNKNOWN, then merge.

It happened again on 2026-09-26 with agent-0's #552: `UNKNOWN` then a merge conflict, and the same chain deleted the branch. Recovery then: `git fetch origin refs/pull/N/head`, `git push origin <headRefOid>:refs/heads/<branch>`, `gh pr reopen N`, merge main into the branch, merge.

**How to apply:** after a force push, wait until `gh pr view N --json mergeable` is MERGEABLE, merge, then delete the branch with `gh pr view N --json state --jq .state | grep -q MERGED && git push origin --delete <branch>`. Do the delete as its own command, or with that guard, every time: a `tail -1` after `gh pr merge` hides its failure.
