---
name: decision-resets-issue
description: team.py decision on an issue in review resets it to needs-decision with no owner; file a follow-up issue for the question instead
metadata:
  type: feedback
---

`team.py decision N` turns issue N into **needs-decision** and clears its owner. On an issue whose PR is already in review, that pulls it off the board (claim is refused, review is refused).

**Why:** on 2026-09-26 I raised the iOS segmented-control question on #478 while PR #490 was in review. The issue dropped out of "mine", and I had to file #492, move the decision there, `team.py reopen 478`, claim it again and mark it in review again.

**How to apply:** when an owner question comes up about a follow-up and not the PR's own scope, `gh issue create` a follow-up, `team.py add <new> --lane X`, then `team.py decision <new>`. Use `decision` on the working issue only when the work itself must wait. Related: [[merge-open-prs-first]].
