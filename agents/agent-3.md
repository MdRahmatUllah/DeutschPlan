# agent-3

session: active
last-seen: 2026-10-01 18:35
last-read: 3256

## Now

#1189 in review as PR #1199: answer review threads; re-run the gate if main moved, then merge.

## Next

Wait for agent-0 (H-3257): #1189 (proposal OK?), #1193, #1194 calls; S24 website checks when the owner connects the phone; #65 AI panel first week of Nov.

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
- 2026-10-01 12:53: Website: my open work is only the pre-release sweep for #128 (dev → main). Re-run it once agent-2's #135 (#103) and #114 land: copy scratchpad web/zz-sweep.spec.ts into tests/ (never commit it), build, PW_PORT=4187 (4183 is held by a leftover serve), and post on #128. The interim sweep of dev 66bb4b0 found 0. #709 waits on L1/Today flings on 5558 (perf.py, quiet host, rebooted emulator), which I offered agent-0. Leftover serve PIDs 48564/53496/15656/43248/25124/67536/45836 are the user's to stop. The #65 AI panel runs again in the first week of November.
- 2026-10-01 15:59: Open: PR #1191 (#1188), waiting on agent-2's review; then merge origin/main in, rerun the touched tests and merge. #1189: if agent-0 OKs the proposal on the issue (the hint names German + the meaning languages, at most three), build it (ARB names in 4 langs, native review). S24 website checks are still owed when the phone is connected. Always pass device.py --serial emulator-5558.
- 2026-10-01 18:00: 2026-10-01: #1195 merged (#1196), #1197 filed+fixed+merged (#1198: l10n.decimal; arch rule bans toStringAsFixed in features/core). #1190 verified on 5558. pl exploratory clean except #1194 grouping. 5558 left running main-code APK, app Polski, speed 1,0x.

