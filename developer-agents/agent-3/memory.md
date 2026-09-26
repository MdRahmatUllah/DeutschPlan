# agent-3's memory

What agent-3 (SQA) knows that the code and the docs don't tell you. Two parts:

1. **Board memory**, a snapshot of `agents/agent-3.md` on the `team` branch (last seen 2026-09-26 13:31). The live copy is always newer: read it first, at `<root>/dp-team/agent-3/agents/agent-3.md`.
2. **Shared memories** this role leans on. They are in [`../shared-memory/`](../shared-memory/), which every agent loads once it is restored (see [`../README.md`](../README.md)).

## Board memory (snapshot)

**Now:** Nothing claimed.

**Next:** SQA pass 3 before v1.0 (H-851): fresh release x64 of main 3779f9f on emulator-5556; closed #162 #165 #167 #168 #170 #173 #174 #449 #437 #451 #455 #456 #457 #463 #473 #477 #478 #486 #460 #430 #501 #537; bugs → SQA milestone, P1/P2 first

**Pending on resume (agent-0, 2026-09-26):** that pass 3 is done. What is open is the **1.0.1 device pass** (handoffs H-1125 and H-1130): a fresh release x64 build of main `0d23968e` (v1.0.1) on emulator-5556, covering the 17 fixes since v1.0.0 (`git log v1.0.0..v1.0.1`). v1.0.1 was tagged without it on the owner's word, so findings go into 1.0.2. P1 and P2 are reported to agent-0 first.

**Notes for the next session:**

- 2026-09-25 00:31: SQA ledger lives in the owner's Claude memory (sqa-agent3.md). Worktree dp-wt/agent-3 is detached on origin/main; app/test/sqa/ holds UNCOMMITTED probe tests (chip semantics, FSRS elapsed, grammar distractors, cloze gap), never to be committed. The emulator-5556 app is on bcb766f with learner data: B1.2 active, exams unlocked, glass theme, swipe on, revisions 5. device.py/d.py needs --serial emulator-5556; uiautomator single-quotes attributes containing a double quote.
- 2026-09-25 00:31 (end of session): SQA pass 1 done: M0–M6 closed issues tested on emulator-5556; 23 SQA issues (4 verified fixed, 1 false positive closed)
- 2026-09-25 14:41: SQA pass 2 done at 3bbd5e5: every closed milestone issue and every closed SQA fix is tested. Open SQA: #345 #390 #396 #405 #406. emulator-5556: app data kept; plans to 9 Nov; clock real. Storage is tight: install with pm uninstall -k + install. Other people's apps on the emulator are not mine; left alone.
- 2026-09-25 14:41 (end of session): SQA pass 2 complete; 14 fixes verified, 2 new bugs filed (#405, #406).

## Shared memories for this role

- [sqa-agent3](../shared-memory/sqa-agent3.md): the SQA ledger: role, setup, every pass, every bug filed and fix verified, device techniques.
- [device-lock-check](../shared-memory/device-lock-check.md): emulator ownership; never touch the developers' emulator.
- [ci-minutes](../shared-memory/ci-minutes.md): CI is off; the local gate and SQA are the checks.
- [v1-release](../shared-memory/v1-release.md): what was released; the 1.0.1 device pass is still open.

The project's own memory (the owner's rules, the decisions already made, the technical lessons) is `MEMORY.md` on the board. Read it every session.
