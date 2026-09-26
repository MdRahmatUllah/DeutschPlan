---
name: no-chaining-past-failure
description: "A rebase (or lock, or build) gets its own command; never `;`-chain the gate after it"
metadata:
  type: feedback
---

Run `git rebase`, `team.py device` and anything else that can refuse or conflict as their own command, and read the result before the next step. Chain the gate's steps with `&&`, never `;`, and never pipe a rebase through `| tail`, which hides its exit code.

**Why:** on 2026-09-25 a `git rebase … | tail -1; …gate…` hit an ARB conflict. The gate then ran for 10 minutes on a conflicted tree, twice in one session. See [[device-lock-check]] for the same mistake with the device lock.

Also, a newline after a heredoc (`git commit -F - <<EOF … EOF`) ends an `&&` chain. On 2026-09-25 a failed `merge-base --is-ancestor` check skipped the commit, but the push, the PR comment and `gh pr merge` on the lines after the heredoc still ran. PR #365 merged without its review fixes.

Again on 2026-09-26: `pytest …; git commit … && git push && gh pr merge 464` merged `tools/perf.py` with a syntax error, and main was red until hotfix #491. Separately, a Python edit script that asserted on `'\n'` text failed on a CRLF file (worktrees check out CRLF with `core.autocrlf=true`), and the `git add && git commit && push && gh pr create` on the next line still ran, so a PR opened without half its change.

**How to apply:** a test or a script that edits files is its own command; merge only in a later call after reading it passed. For exact-text edits, use the Edit tool or read with `newline=''` and match `\r?\n`. Never let a Python heredoc's failure fall through to a commit on the next line. After a rebase, check `git status` for "rebase in progress" before regenerating or gating. Commit in one call, and push/comment/merge in the next, only after reading that the commit landed (`git log -1`). ARB files conflict whenever two branches append keys at the end. The fix is `git checkout --ours` for main's copy, then re-add your keys with a JSON script.
