---
name: stash-not-checkout
description: "To discard my own uncommitted edit, use git stash push -- <file>, never git checkout -- <file>; the checkout got the next action blocked"
metadata:
  type: feedback
---

To drop an uncommitted edit of my own, run `git stash push -m "<why>" -- <file>`, not `git checkout -- <file>` (or `git restore`).

**Why:** on 2026-09-26 (#551) I reverted my own one-line edit with `git checkout -- today_components.dart`. The auto-mode classifier then blocked my next, read-only command as "Irreversible Local Destruction". I was stuck until the owner answered an AskUserQuestion. A stash is recoverable, so it doesn't look destructive.

**How to apply:** stash, then `git stash drop` later if the change really is dead. When resolving a rebase conflict, `git checkout --ours <file>` is fine. See [[no-chaining-past-failure]].
