# agent-4's memory

What agent-4 (the website) knows that the code and the docs don't tell you. Two parts:

1. **Board memory**, a snapshot of `agents/agent-4.md` on the `team` branch (last seen 2026-09-30 20:28). The live copy is always newer: read it first, at `<root>/dp-team/agent-4/agents/agent-4.md`.
2. **Shared memories** this role leans on. They are in [`../shared-memory/`](../shared-memory/), which every agent loads once it is restored (see [`../README.md`](../README.md)).

## Board memory (snapshot)

**Now:** #1169 (this folder).

**Next:** Website #45, the Google Play link, waits for v1.1.0's Play release (app #1123). When the owner says `de.sogda.app` is listed: set `playStoreUrl` in `site.config.ts`, PR into `dev`, then dev into `main`. Website #52 is the owner's hand checks: a real phone, a screen reader, and Safari. The team's review of the site and its competitors runs on website #54, and agent-4 drafts its master plan. Anything agent-0 assigns comes first.

**Notes for the next session:**

- 2026-09-29: onboarded as agent-4, a fifth identity (`team.py` accepts agent-0 to agent-9). Worktree `<root>/dp-wt/agent-4`; re-run the gen sequence after switching branches. Reviews in this repo are PR conversation comments starting `**Agent-4** review of #P (#N) at <sha>`, then `team.py msg <author> --kind review`.
- 2026-09-30: website clone `<root>/sogda-website`; PR images on the `pr-shots` branch (worktree `<root>/sogda-website-shots`). Lessons: run gate commands without pipes, so exit codes count. Lighthouse here follows the OS dark mode, and a fresh profile pays a one-off font cold start. An emulator-5558 started from a session dies with it, as it did during Chrome's first run.
- 2026-09-30: website #45 waits for the app's Play release (the owner's call).

## Shared memories for this role

- [sogda-website](../shared-memory/sogda-website.md): the site, its repo, the owner's rules for it, and where it stands.
- [pr-author-line](../shared-memory/pr-author-line.md): every PR body starts with `**Agent-4**`.
- [device-lock-check](../shared-memory/device-lock-check.md): run `team.py device` alone and read it; only emulator-5558.
- [merge-then-delete](../shared-memory/merge-then-delete.md): delete a branch only after its PR is merged.
- [no-chaining-past-failure](../shared-memory/no-chaining-past-failure.md): a build, a lock or a test is its own command.

The project's own memory (the owner's rules, the decisions already made, the technical lessons) is `MEMORY.md` on the board. Read it every session.
