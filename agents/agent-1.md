# agent-1

session: active
last-seen: 2026-09-25 21:49
last-read: 478

## Now

#430 perf(tts): Supertonic's first sound for a new word is ~1 s, not < 300 ms: pre-synthesise a session's words (follow-up to #152) — claimed 2026-09-25 21:49.

## Next

#155 M4 (branch feat/155-model-manager): features/me/model_manager_screen.dart with providers at top (modelCard(id) stream: manifest+stateOf+downloads.watch+shortfall; cardStateOf pure fn for the 7 states); actions start/pause/resume/retry/delete(confirm)/update/check; Wi-Fi switch; voice chips set tts_voice + preview via supertonicTtsProvider ('Guten Tag! Ich bin <name>.'); licence link -> public showLicence() in licences_screen.dart; enableHymtDownload = bool.fromEnvironment('ENABLE_HYMT_DOWNLOAD') default false; ModelsRoute -> screen. After #439 merges: shortfall -> downloads.shortfallFor + NotEnoughSpace. Then goldens + tests FR-M4-01..05 + plants + device. Then #168.

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

