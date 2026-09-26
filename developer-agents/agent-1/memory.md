# agent-1's memory

What agent-1 (developer, lane B) knows that the code and the docs don't tell you. Two parts:

1. **Board memory**, a snapshot of `agents/agent-1.md` on the `team` branch (last seen 2026-09-26 19:36). The live copy is always newer: read it first, at `<root>/dp-team/agent-1/agents/agent-1.md`.
2. **Shared memories** this role leans on. They are in [`../shared-memory/`](../shared-memory/), which every agent loads once it is restored (see [`../README.md`](../README.md)).

## Board memory (snapshot)

**Now:** Nothing claimed.

**Next:** Nothing open. Next: agent-3's 1.0.1 SQA findings (1.0.2) when they come; reviews.

**Notes for the next session:**

- Worktree: F:/appDevs/dp-wt/agent-1 (create it: ONBOARDING.md §2).
- Lane B: #151 → #140 → #137 → #141 → #138 → #139 → #156 → #142 (needs #81) → #143 → #280 → #152 (after #245) → #153 → #155 (needs #146) → #154 (after #283) → #173 (ADR draft) → #166 → #164 → #167 → #174 → #163.
- #151: `services/tts/tts_engine.dart` and `system_tts.dart` exist ("#151 owns this seam and grows it"). Add name/isAvailable/speed/state; add a `tts` provider so W1, R1 and the quiz runner stop reading `systemTtsProvider`. `DpSpeakerButton` shows the states.
- #140 turns `WordRoute.open` into a sheet on phones and a pane on tablets; it is called from backlog, category_words, step_words, sentences and study. Honour `?speak=1`; fix the stale `TODO(#136)` in routes.dart.
- `search_repository.dart` already has the four tiers; `WordRow` (+ `step:`) is the list row; `withMeanings` gives meanings in the learner's language.
- #141 creates the `Translator` interface (an 'unavailable' implementation) that #154 fills.
- #143 edits `domain/quiz_builder.dart` (agent-0's file): message agent-0 first.
- The manifest's Supertonic (#245) and Hy-MT (#283) URLs are wrong: build #156/#152 against fakes.
- 2026-09-25 21:49: Session 2026-09-25: merged #413,#415,#418,#410,#422,#424,#431; PR #447 (#155 M4) in review (fold #439's shortfallFor+NotEnoughSpace after it merges). Supertonic: R8 keep rule for ai.onnxruntime is required; emulator-5558 is on AndroidWifi now; its app has the 9-file voice installed. Device tool: tap labels with '·' fail from this console, use at:x,y.
- 2026-09-26 13:32: feat/551-maxlines-audit (cf7abf6f) is kept on the remote only as a reference for agent-2's #556 should-fix (hint wrap past 130 % + maintainHintSize:false). Delete it once #556 merges. It has no PR.
- 2026-09-26 19:36: v1.0.1 tagged on 0d23968e (2026-09-26). Everything assigned to agent-1 is merged: #561/#562, #565/#570, #571/#575, #572/#582, #574/#578, #581/#589, #588/#591. Open work is all Later (iOS needs a Mac; #154 and #533 wait on the owner). agent-3's 1.0.1 device pass feeds 1.0.2; take its findings first. emulator-5558 is off by the owner's decision. The golden audit runs en+bn with the keyboard pass (about 75 s for the text audits); DpScript.largeTypingInView reads the keyboard inside a scaffold's body.

## Shared memories for this role

- [merge-open-prs-first](../shared-memory/merge-open-prs-first.md): open PRs before new work; ask for reviews directly.
- [no-merging-others-prs](../shared-memory/no-merging-others-prs.md): review others' PRs; hand the merge back to the author.
- [read-full-review](../shared-memory/read-full-review.md): read the whole latest review before merging.
- [device-lock-check](../shared-memory/device-lock-check.md): take the device lock alone and read it.
- [perf-reboot-emulator](../shared-memory/perf-reboot-emulator.md): reboot emulator-5558 before perf.py if its swap is full.
- [test-viewinsets-physical](../shared-memory/test-viewinsets-physical.md): keyboard insets in widget tests are physical pixels.
- [test-semantics-dispose-inline](../shared-memory/test-semantics-dispose-inline.md): dispose a SemanticsHandle inline.
- [basic-gate-per-pr](../shared-memory/basic-gate-per-pr.md): basic check per PR.
- [no-chaining-past-failure](../shared-memory/no-chaining-past-failure.md): no `;` chains past a failure.
- [v1-scope](../shared-memory/v1-scope.md): what v1 includes; an empty ready list means ask agent-0.

The project's own memory (the owner's rules, the decisions already made, the technical lessons) is `MEMORY.md` on the board. Read it every session.
