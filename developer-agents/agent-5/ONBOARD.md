# Onboarding agent-5 (Marketing & Media)

`/agent-5` prints this file from `origin/main` and follows it. It's safe on
any day: each setup step checks first. `<root>` is the folder that holds the
main checkout (on the first machine, `F:/appDevs`).

**Three rules for every step:**
- **Never use the main checkout's files.** `<root>/deutschplan` stays on an old commit for the owner. Read the current docs from `origin/main` (step 3) and work in your own worktrees, by absolute path.
- **`team.py` runs from your worktree:** `cd <root>/dp-wt/agent-5 && python tools/team.py …`. That's the current version (with `device --refresh`). From the main checkout it refuses with "this worktree has no agent".
- **In Git Bash,** put `MSYS_NO_PATHCONV=1` before a `git show <rev>:<path>`, or Git Bash mangles the argument.

## 1. Set up (skip each step that's already done)
1. Run `git -C <root>/deutschplan fetch -q origin`.
2. **The app worktree:** if `<root>/dp-wt/agent-5` doesn't exist, run `git -C <root>/deutschplan worktree add --detach <root>/dp-wt/agent-5 origin/main`. If it exists, has no changes (`git status --short` is empty) and isn't on a branch of yours with work in progress, move it to the current main with `git -C <root>/dp-wt/agent-5 switch -q --detach origin/main`.
3. **The media worktree:** if `<root>/dp-media` doesn't exist, run `git -C <root>/deutschplan worktree add <root>/dp-media media` (it creates a local `media` branch tracking `origin/media`; see that branch's README). Otherwise run `git -C <root>/dp-media pull -q`.
4. **Your own website clone (read only):** if `<root>/sogda-website-wt/agent-5` doesn't exist, run `gh repo clone MdRahmatUllah/sogda-website <root>/sogda-website-wt/agent-5`. Never use `<root>/sogda-website`: that's agent-4's working clone. Then run `git -C <root>/sogda-website-wt/agent-5 fetch -q origin`, and read the live site's state from `origin/main` (`git show origin/main:<path>`). `dev` is unreleased work.
5. **The memory:** find this session's memory folder (your system prompt names it). If it has no `MEMORY.md`, copy `<root>/dp-wt/agent-5/developer-agents/shared-memory/*.md` into it.
6. **Check the tools,** each command on its own, and report what's missing:
   - `gh auth status` (it must be `rahmat-ullah`);
   - `python --version`;
   - `node --version`;
   - `ffmpeg -version`;
   - `magick -version`;
   - `python -c "import PIL"`.

   **Ask the owner before installing any system software.**

## 2. Join the board
Run `cd <root>/dp-wt/agent-5 && python tools/team.py join agent-5`. The first time, it creates your board file and clones the board to `<root>/dp-team/agent-5`. If it says agent-5 looks active, another session is running as agent-5: stop and tell the owner. Don't use `--force` unless the owner says so.

## 3. Read, from `origin/main`, in this order
Read each file in `<root>/dp-wt/agent-5/` (current after step 1.2), or with `git -C <root>/deutschplan show origin/main:<path>`:
1. `developer-agents/README.md`: the team, the rules, the board.
2. `developer-agents/agent-5/README.md`: **your role and the owner's rules for you. They're binding:** you never publish, post or send anything yourself, and every fact comes from `site-facts.json`.
3. `developer-agents/agent-5/memory.md`, and `docs/marketing/README.md`.
4. `CLAUDE.md`: the session ritual and the non-negotiables. **Read origin/main's,** not the copy this session loaded from the old main checkout.
5. On the board (`<root>/dp-team/agent-5`): `agents/agent-5.md` (your Now, Next and Memory), `MEMORY.md`, and the lane M section of `PLAN.md`.

## 4. Start the session (`CLAUDE.md`, "Start every session")
1. `team.py status`: act on your handoffs, then `team.py ack`.
2. **Reviews first:** any open PR that asks for you.
3. **Then your work:** continue your `Now`, or `team.py claim <N>` the first ready issue in **lane M** (milestone MK1 before MK2; anything agent-0 assigned to you comes first).
4. **While working:** `team.py log -m "…"` at each real step. At the end of the session: `team.py next -m "…"`, `team.py note -m "…"`, and `team.py leave -m "…"`.

## 5. Tell the owner, in three lines
Say that agent-5 has joined, what you'll do first, and anything you need from the owner (a missing tool, an account, or a decision).
