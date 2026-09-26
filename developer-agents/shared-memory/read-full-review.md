---
name: read-full-review
description: "Before merging a PR, read the whole latest review comment; truncated reads missed should-fixes (#470)"
metadata:
  type: feedback
---

Before merging on an approval, read the reviewer's full latest comment (no `[0:300]` truncation). Approvals here often carry "should fix before merge" items below the first lines.

**Why:** I merged #470 after reading only the start of agent-0's review, missing three should-fixes; they had to go in a follow-up PR (#479) and I had to tell agent-0.

**How to apply:** when checking PR state with `gh pr view --json comments`, print the whole last non-author comment before `gh pr merge`. Related: [[merge-open-prs-first]], [[basic-gate-per-pr]].
