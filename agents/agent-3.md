# agent-3

session: active
last-seen: 2026-10-01 03:57
last-read: 3118

## Now

Nothing claimed.

## Next

Website pull board: #99 (mock exams) waits for agent-1's pl/bn, then I merge dev in, re-render its cards in #101's layout and merge. #111 (FSRS page) waits for agent-0 (facts, de), agent-1 (pl, bn) and agent-2 (ru); agent-4 approved the code. #61's drift test is built on feat/61-drift-test (checks 1, 3 and 4; check 5 needs screens.generated.json to record its app ref), plants running; its PR opens when a slot frees.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.
- 2026-09-25 00:31: SQA ledger lives in the owner's Claude memory (sqa-agent3.md). Worktree dp-wt/agent-3 is detached on origin/main; app/test/sqa/ holds UNCOMMITTED probe tests (chip semantics, FSRS elapsed, grammar distractors, cloze gap), never to be committed. The emulator-5556 app is on bcb766f with learner data: B1.2 active, exams unlocked, glass theme, swipe on, revisions 5. device.py/d.py needs --serial emulator-5556; uiautomator single-quotes attributes containing a double quote.
- 2026-09-25 00:31 (end of session): SQA pass 1 done: M0–M6 closed issues tested on emulator-5556; 23 SQA issues (4 verified fixed, 1 false positive closed)
- 2026-09-25 14:41: SQA pass 2 done at 3bbd5e5: every closed milestone issue and every closed SQA fix is tested. Open SQA: #345 #390 #396 #405 #406. emulator-5556: app data kept; plans to 9 Nov; clock real. Storage is tight: install with pm uninstall -k + install. Other people's apps on the emulator are not mine; left alone.
- 2026-09-25 14:41 (end of session): SQA pass 2 complete; 14 fixes verified, 2 new bugs filed (#405, #406).
- 2026-09-29 22:42: 2026-09-29: S24 (R5CWC2LXVWZ) now holds the OWNER's own learning (since 28 Sep, their 4x2 widget on page 2): never rate cards, reset, or leave a PR build on it; install -r keeps data; back to main after a PR check. Flutter frames: gfxinfo sees none, use scratchpad sflat.py (SurfaceFlinger --latency on the BLAST layer). Swipes can hit an open keyboard: check mInputShown first.
- 2026-09-29 23:32: 2026-09-29: never start a shared emulator as a Bash background task: the harness kills it at its time limit (5558 went down after #1030). After main gains a .drift/content change, run the ADR 17 generation steps (mirror_content_schema, drift steps, build_runner) before building.
- 2026-10-01 02:02: Resume: (1) #99 at 41b09f5 in sogda-website-wt/agent-3-base (agent-1's pl/bn fixes, committed, NOT pushed): git fetch && merge origin/dev, pnpm og (keep only mock-exams cards), build, Playwright on 4183, push, merge. (2) #111: take agent-2's 4 ru fixes (H-3109) and agent-4's nits (@/content import, routing.locales); waits for agent-0 (facts, de) and agent-1 (pl, bn). (3) #61 drift test on feat/61-drift-test in agent-3: plants were running (../a3-plant61.txt); PR when a slot frees. (4) Six stale serve processes on 4193 are the user's to stop; use LH_PORT=4197.

