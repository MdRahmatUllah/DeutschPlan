# The plan: every remaining milestone

Where the project is going and in what order. TASKS.md is the live state;
this is the route. Change it when reality changes, and say so in a handoff
(`team.py msg all --kind heads-up`).

## The team

Three agents work in parallel, each in its own worktree
(`F:/appDevs/dp-wt/<id>`):

- **agent-0 is the lead.** It takes lane A, the critical path. It assigns work (`team.py assign`), reviews the others' PRs, closes epics and milestones, and relays the owner's decisions.
- **agent-1 takes lane B:** the voice seam, words, search, translation and polish.
- **agent-2 takes lane C:** Me, settings, the exam engine, platform work and accessibility.

A fourth agent would join as `agent-3`. The lead then gives it part of a lane in a handoff.

Snapshot 2026-09-24:
- **Done:** M0 (60 issues), M1 (19), M2 (19) and M3 (12, closed with epic #9).
- **Left:**
  - M4 · Quiz & mock exams: 18 issues and 3 epics
  - M5 · Search, words, Me: 14 and 2
  - M6 · Voice, translation, widget: 11 and 2, plus decisions #245 and #283
  - M7 · Polish & release: 14 and 2, plus follow-ups #280–#282 and #284
- About 113 units of work at S=1, M=2, L=3, so roughly 38 per agent.

## Milestones and what "done" means

| Milestone | Specs | Done when |
|---|---|---|
| M4 Quiz & mock exams | 03-domain/quiz-engine.md, exam-generator.md; 04-screens/quiz.md, exam-hub.md, exam-runner.md, exam-writing-speaking.md, exam-results.md; BR-QUIZ, BR-EXAM | #81–#84, #122–#136 merged; epics #6, #10, #11 closed; the `/quiz` and `/exam/:attemptId` placeholders gone |
| M5 Search, words, Me | 03-domain/search.md; 04-screens/search.md, word-detail.md, compare.md, add-word.md, me.md, progress.md, settings.md, reminder-days.md, export-import.md, reset.md, about-licences.md | #137–#150 merged; epics #12, #13 closed; no `PlaceholderScreen` left under `/search`, `/me`, `/word`, `/compare` |
| M6 Voice, translation, widget | 03-domain/tts.md, translation.md, notifications-widget.md; 04-screens/model-manager.md, widget.md; ADR 8, 9 | #151–#161 merged; #245 and #283 decided and applied; epics #14, #15 closed |
| M7 Polish & release | 01-architecture/accessibility-performance.md; 05-dev-guide/testing.md, release.md | #162–#175 and the follow-ups merged; epics #16, #17 closed; release checklist green |

When the last issue of a milestone merges, the lead:
1. closes its epics;
2. closes the milestone (`gh api -X PATCH repos/MdRahmatUllah/DeutschPlan/milestones/<n> -f state=closed`; M4 is 5, M5 is 6, M6 is 7, M7 is 8);
3. reports to the owner (`team.py msg owner`), listing the open decisions.

## The critical path

#81 → #122 → #123 → #124 → #130 → #133/#134 → #135 → #136 → #162 → #165 → #168 → #175

The quiz and exam-runner chain (lane A) gates the whole M7 accessibility
tail. Lane C builds the exam engine (#83, #84, #127, #129) in parallel, so it
is ready when A reaches the runner. Anything that unblocks lane A comes first.

## Lanes

Take the first issue in your lane that is ready. If none is, see "When your
lane is blocked". Issues the lead has assigned to you come first.

**Lane A — agent-0 (lead) — quiz and exam runner, then release**
1. #81 quiz_builder. This is shared infrastructure: #122, #83, #142 and #143 all use it. `QuizArgs` already exists in `routes.dart` (it lacks `timer`), and L2's `stepQuiz` and L6's `categoryQuiz` already build it.
2. #122 L7 custom sheet (the `ponytail: #122` stub in `step_quiz.dart`).
3. #123 L8 runner shell.
4. #124 L8 item layouts, **reusable by #130 without verdicts**.
5. #125.
6. #126 L9 result.
7. #130 L12 exam runner. Needs #129 from lane C.
8. #131, #132, #133, #134 (mic permission in AndroidManifest and Info.plist).
9. #135, #136.
10. #169 integration smoke.
11. #170, #171, #175 release. These need the owner's app id, keys and accounts.

Between issues the lead also:
- reviews agent-1's and agent-2's PRs (review requests come first);
- assigns work when a lane runs dry;
- closes epics.

**Lane B — agent-1 — voice seam, words, search, translation, polish**
1. #151 TtsEngine, **and add a `tts` provider seam now**, so every new speaker (W1, R1, the quiz runner) codes against it instead of `systemTtsProvider`.
2. #140 W1 word detail. Every "open word" goes through `WordRoute.open`, and #136, #137, #143 and #160 build on it.
3. #137 R1 results.
4. #141 W1 actions. Creates the `Translator` interface with an "unavailable" implementation.
5. #138, #139.
6. #156 download manager. Build against fakes: the manifest URLs are wrong (#245, #283).
7. #142 W2 compare. Needs #81.
8. #143 R2 add word. Also edits `quiz_builder.dart`: message agent-0 first.
9. #280 iOS bar titles. Shared look, so take the lock.
10. #152 Supertonic, after decision #245. Then #153 TtsService: migrate every `systemTtsProvider` call site.
11. #155 M4 model manager. Needs #146 from lane C, and #153 and #156.
12. #154 Hy-MT, after decision #283. #173: draft the ADR only.
13. #166 localisation, #164 reduce motion, #167 performance, #174 error matrix, #163 contrast (after #162).

**Lane C — agent-2 — Me, settings, exam engine, platform, accessibility**
1. #144 M1 Me.
2. #83 exam generator, as soon as #81 is merged (it is on the critical path). If #81 is not merged yet, do #146 first.
3. #84 grading.
4. #127 L10 hub (the Exams-tab stub in `step_detail_screen.dart`).
5. #129 L11 intro. Hand it to agent-0 for #130.
6. #128.
7. #146 M3 settings. It unblocks #147, #148, #150 and #155. It also wires the glass theme.
8. #157 notifications, #158 background tasks, #159 widget snapshot, #160 Android widget.
9. #147 study days and reminder. Needs #146 and #158.
10. #145, #148, #149, #150, #172.
11. #161 iOS widget: written blind, marked unverified.
12. The accessibility tail: #162 → #165 → #168.

**Lane X — anyone, when their lane is blocked**
- Follow-ups: #281 (L6 tests), #282 (glass word lists), #284 (dev-guide reconciliation).
- Epics: the lead closes them.
- Decisions #239, #245 and #283 wait for the owner.

## Hand-offs between lanes

| From | To | What |
|---|---|---|
| A #81 (agent-0) | C #83, B #142, #143 | quiz_builder; the `compareSet` and custom-word sources |
| C #129 (agent-2) | A #130 | the intro starts the attempt the runner resumes |
| C #84 (agent-2) | A #133, #134, #135 | grading |
| B #151 `tts` seam (agent-1) | A #124, #130; B #137, #140 | the speaker API |
| B #153 (agent-1) | every speaker call site; #155, #167, #174 | the engine swap |
| C #146 (agent-2) | C #147, B #155 | the settings screen |
| B #140 (agent-1) | A #136, C #160 | W1 and `?speak=1` |
| A #134 (agent-0) | C #149 | recordings at `<appSupport>/recordings/<attemptId>.m4a` |
| all screens | C #162, #165, #168 | the a11y pass needs the screens to exist |

`team.py done` reports to everyone. When a lane waits on you, also send
them a note, e.g.
`team.py msg agent-0 -m "#129 merged: ExamIntroRoute starts the attempt with ExamRepository.begin(...)"`.

## When your lane is blocked

1. Handoffs first (`team.py status`). The lead may have assigned you something.
2. Review an open PR from another agent.
3. Take a ready issue from another lane, if it doesn't touch files that lane has in flight. Critical path first, then P1, then P2. #164, #166, #280, #281, #282 and #284 are floaters.
4. Build ahead against an interface or fake for your next item. Keep it on your branch until the blocker lands.
5. Never guess a decision. `team.py decision <n> -m "what must be decided"` and move on.
6. If truly nothing is ready: `team.py msg agent-0 --kind question -m "lane dry"`. The lead reassigns.

## Decisions only the owner makes

- **#245**: the Supertonic model's real size (~398 MB), which voice styles ship, the S2 offer and Wi-Fi rules.
- **#283**: the Hy-MT source and quantisation; both manifest URLs 404.
- **#239**: whether FSRS's doc chain or the code is right.
- **#173**: the Hy-MT region decision. An agent may draft the ADR.
- **#170, #171, #175**:
  - The real application id and bundle id (still `com.example.deutschplan`).
  - Signing keys, store accounts, the App Group.
  - Store copy, the version number, the tag.
  - A macOS host (#161, #171 and iOS #169 cannot run on this Windows machine).
- **Settings with no spec**: #150's About contact (not an invented email; #100 used GitHub issues); CI cost of integration runs (#167, #169).
- **Branch protection on `main`**: needs admin.

Spec gaps an agent may fill (update the doc in the same PR, and flag it in the PR body):
- `recent_searches` (#138)
- the custom-words-in-quizzes key (#143)
- a Wi-Fi-only download key (#156)
- a last-export key (#148)
- `compare_group`: no such column exists (#140/#142)
- writing and speaking prompt templates (#83; `skill_prompts` looks like a pipeline bug)
