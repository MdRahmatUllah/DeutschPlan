# agent-1

session: active
last-seen: 2026-09-28 06:33
last-read: 2303

## Now

#1004 fix(today, day-complete): the day's "N words · M min" counts a backlog word's minutes but not the word (from #990's review) — claimed 2026-09-28 05:53.

## Next

In review: #828 (#669). Then down my P2 list, 1-2 open PRs at a time: #654, #660, #661, #662, #663, #667, #674, #676, #680, #684, #713.

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
- 2026-09-26 19:36: v1.0.1 tagged on 0d23968e (2026-09-26). Everything assigned to agent-1 is merged: #561/#562, #565/#570, #571/#575, #572/#582, #574/#578, #581/#589, #588/#591. Open work is all Later (iOS needs a Mac; #154 and #533 wait on the owner). agent-3's 1.0.1 device pass feeds 1.0.2; take its findings first. emulator-5558 is off by the owner's decision. The golden audit runs en+bn with the keyboard pass (about 75 s for the text audits); DpScript.largeTypingInView reads the keyboard inside a scaffold's body.
- 2026-09-27 15:49: Usage limit hit 2026-09-27. Open: PR #882 (#613) awaiting review. Next per H-1690: #638, #627, #623, #662, #663, #680, #682. Main's app_router_test is red since #856 (reported H-1748). #860 should-fix (old content.db lacks words.kind) offered as a follow-up.
- 2026-09-27 19:04: Usage limit 2026-09-27. #663+#757 WIP on branch feat/663-voice-installed-follows (pushed, no PR): voiceInstalled watches voiceDownloadProvider.select(phase); M4 _delete invalidates voiceInstalledProvider; 238 related tests pass. TODO: a test with FakeDownloads.live emitting ready (fails before), plants, docs (today.md FR-T1-06, settings.md), device check, PR closing #663 and #757. Open PRs awaiting review: #926 (#674), #928 (#676, stacked on #926), #930 (#623; pubspec lock held until it merges).
- 2026-09-27 22:00: Usage limit 2026-09-27 ~22:15. Open PRs: #930 (#623; review fixes pushed, waiting on agent-2's re-review; pubspec lock held until merged) and #953 (TTS/models batch #663 #755 #756 #757 #868; device-checked; no review yet). Emulator-5558: voice re-downloading to Ready. Next: the deep-link batch #747 #748, then quiz #680 #682 #667 #727. Board: agent-0's merged-but-'review' entries (#713 #697 #921) reported (H-2065).
- 2026-09-27 23:52: Next session: open the quiz batch PR from feat/667-682-727-quiz (body: the #667/#682/#727 items plus #949 test tag, #950 Left on (flag: a step the plan finished reads Left on until Done, per the owner's wording), #963 FR-L6-02 docs). Review #972/#975 if still open. Then #729 #742 #935. Owner rule: merge origin/main in (no rebase) before merging.

