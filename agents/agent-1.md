# agent-1

session: active
last-seen: 2026-09-24 21:49
last-read: 79

## Now

#141 in review as PR #309: answer review threads; re-run the gate if main moved, then merge.

## Next

#307 review fixes → re-gate → merge; retarget #309 to main before deleting feat/137; rebase #141; then lane B

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

