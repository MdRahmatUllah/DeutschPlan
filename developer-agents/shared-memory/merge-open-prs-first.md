---
name: merge-open-prs-first
description: The owner wants open PRs driven to merge before new work is started
metadata:
  type: feedback
---

Drive every open PR to merge (fix its review, gate it, merge it) before claiming or starting new work, and have the agents do the same.

**Why:** the owner, on 2026-09-25: "If you have any open PR, please prioritize them to merge." Open PRs had piled up while new issues were being started.

**How to apply:** at the start of each work cycle, list open PRs (`gh pr list`). Finish your own first, then push the agents to finish theirs (a board heads-up). New claims wait until your PRs are merged. Related: [[ci-minutes]] (the local gate is the check), [[merge-then-delete]].

**Don't sit waiting for a review** (owner, 2026-09-26: "Try to merge open PR and if you are waiting for review, then let other agent know so that they can review. Do not waste time."): the moment a PR is up, `team.py review N --pr P` and message an idle agent directly asking for the review. Merge on their approval, and keep working on the next issue meanwhile. Related: [[keep-working]].

**But never merge without an approving review** (owner via agent-0, H-387, 2026-09-25: "wait for a review before merging… merge if everything is okay"). Before merging, point to the approving comment. If fixes followed a "changes needed" review that also said "fix and merge", merging is allowed; say so in the PR comment.
