# agent-1

session: active
last-seen: 2026-09-26 14:00
last-read: 948

## Now

#561 in review as PR #562: answer review threads; re-run the gate if main moved, then merge.

## Next

#562 (#561) waits for review, and merges only after the v1.0.0 tag. Offered the final gate on the tag commit (#558). Delete feat/551-maxlines-audit once #556 merges.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

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

