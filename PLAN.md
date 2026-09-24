# The plan: every remaining milestone

Where the project is going and in what order. TASKS.md is the live state;
this is the route. Change it when reality changes, and say so in a handoff
(`team.py msg all --kind heads-up`).

Snapshot 2026-09-24:
- **Done:** M0 (60 issues), M1 (19), M2 (19) and M3 (12, closed with epic #9).
- **Left:**
  - M4 · Quiz & mock exams: 18 issues and 3 epics
  - M5 · Search, words, Me: 14 and 2
  - M6 · Voice, translation, widget: 11 and 2, plus 2 decisions
  - M7 · Polish & release: 14 and 2, plus follow-ups #280–#282 and #284
- About 113 units of work at S=1, M=2, L=3.

## Milestones and what "done" means

| Milestone | Specs | Done when |
|---|---|---|
| M4 Quiz & mock exams | 03-domain/quiz-engine.md, exam-generator.md; 04-screens/quiz.md, exam-hub.md, exam-runner.md, exam-writing-speaking.md, exam-results.md; BR-QUIZ, BR-EXAM | #81–#84, #122–#136 merged; epics #6, #10, #11 closed; the `/quiz` and `/exam/:attemptId` placeholders gone |
| M5 Search, words, Me | 03-domain/search.md; 04-screens/search.md, word-detail.md, compare.md, add-word.md, me.md, progress.md, settings.md, reminder-days.md, export-import.md, reset.md, about-licences.md | #137–#150 merged; epics #12, #13 closed; no `PlaceholderScreen` left under `/search`, `/me`, `/word`, `/compare` |
| M6 Voice, translation, widget | 03-domain/tts.md, translation.md, notifications-widget.md; 04-screens/model-manager.md, widget.md; ADR 8, 9 | #151–#161 merged; #245 and #283 decided and applied; epics #14, #15 closed |
| M7 Polish & release | 01-architecture/accessibility-performance.md; 05-dev-guide/testing.md, release.md | #162–#175 and the follow-ups merged; epics #16, #17 closed; release checklist green |

When the last issue of a milestone merges: close its epics, then close the
milestone (`gh api -X PATCH repos/MdRahmatUllah/DeutschPlan/milestones/<n> -f state=closed`;
M3 is number 4, M4 is 5, M5 is 6, M6 is 7, M7 is 8). Then report to the owner
(a `team.py msg owner` handoff) with the open decisions.

## The critical path

#81 → #122 → #123 → #124 → #130 → #133/#134 → #135 → #136 → #162 → #165 → #168 → #175

The quiz and exam-runner chain (lane A) gates the whole M7 accessibility
tail. Anything that helps lane A move is worth more than anything else. Lane
C builds the exam engine in parallel so it is ready when A reaches the runner.

## Lanes (one agent each by default)

Each lane is ordered. Take the first issue in your lane that is ready. If
none is, see "When your lane is blocked".

**Lane A — agent-1 — quiz and exam runner (critical path)**
1. #81 quiz_builder. This is shared infrastructure: #122, #83, #142 and #143 all use it. `QuizArgs` already exists in `routes.dart`; it lacks `timer`. L2's and L6's builders already call it.
2. #122 L7 custom quiz sheet. It replaces the `ponytail: #122` stub in `step_quiz.dart`.
3. #123 L8 runner shell.
4. #124 L8 item layouts. **Build them so the exam runner #130 can reuse them without verdicts.**
5. #125 re-ask queue.
6. #126 L9 result.
7. #130 L12 exam runner. Needs #129 from lane C.
8. #131, #132 (fix the stale `TODO(#119)` in `routes.dart` there), #133, #134 (mic permission in AndroidManifest and Info.plist).
9. #135, #136.
10. #169 integration smoke.

**Lane B — agent-2 — search, words, translation seam, polish**
1. #140 W1 word detail first. Every "open word" in the app goes through `WordRoute.open`, and #136, #137, #143 and #160 build on it.
2. #137 R1 results.
3. #141 W1 actions. Creates the `Translator` interface with an "unavailable" implementation.
4. #138, #139.
5. #142 W2 compare. Needs #81.
6. #143 R2 add word. Also edits `quiz_builder.dart`: coordinate with lane A.
7. #280 iOS bar titles. Shared look, so take the lock.
8. #154 Hy-MT translator. Waits on decision #283.
9. #173: draft the ADR only; the region decision is the owner's.
10. #166 localisation.
11. #164 reduce motion.
12. #167 performance.
13. #174 error matrix.
14. #163 contrast. After #162.

**Lane C — agent-3 — Me, settings, data, exam engine, accessibility**
1. #144 M1 Me.
2. #83 exam generator, as soon as #81 merges. If #81 is not merged yet, do #146 first.
3. #84 grading.
4. #127 L10 hub. Replaces the Exams-tab stub in `step_detail_screen.dart`.
5. #129 L11 intro. Hand it off to lane A.
6. #128.
7. #146 M3 settings. Unblocks #147, #148, #150 and #155.
8. #145, #148, #149, #150, #172.
9. The accessibility tail: #162 → #165 → #168.

**Lane D — agent-4 — voice, platform, release**
1. #151 TtsEngine. **Also add a `tts` provider seam now**, so lanes A and B code against it instead of `systemTtsProvider`.
2. #156 download manager.
3. #157 notifications.
4. #158 background tasks.
5. #159 widget snapshot.
6. #160 Android widget.
7. #147 study days and reminder. Needs #146 from C and the composer from #158.
8. #152 Supertonic. After decision #245.
9. #153 TtsService. Migrate every `systemTtsProvider` call site.
10. #155 model manager.
11. #161 iOS widget: written blind, marked unverified.
12. #170, #171, #175. Credentials come from the owner.

**Lane X — anyone**
- Follow-ups: #281 (L6 tests), #282 (glass word lists), #284 (dev-guide reconciliation).
- Epics: close them when their children are done.
- Decisions: #239, #245, #283 wait for the owner.

## Hand-offs between lanes

| From | To | What |
|---|---|---|
| A #81 | C #83, B #142, B #143 | quiz_builder; the `compareSet` and custom-word sources |
| C #129 | A #130 | the intro starts the attempt the runner resumes |
| C #84 | A #133, #134, #135 | grading |
| D #151 (`tts` seam) | A #124, #130; B #137, #140 | the speaker API |
| D #153 | every speaker call site; D #155; B #167, #174 | the engine swap |
| C #146 | D #147, D #155 | the settings screen |
| B #140 | A #136, D #160 | W1 and `?speak=1` |
| A #134 | C #149 | recordings at `<appSupport>/recordings/<attemptId>.m4a` |
| all screens | C #162, #165, #168 | the a11y pass needs the screens to exist |

When you finish a hand-off item, `team.py done` reports it to everyone. If a
lane is waiting on you, also send them a note:
`team.py msg agent-N -m "#129 merged: ExamIntroRoute.open(context, step, seed) starts the attempt"`.

## When your lane is blocked

1. Check your handoffs (`team.py status`). Someone may have assigned you something.
2. Review an open PR from another lane (the review requests in `status`).
3. Take a ready issue from another lane, if it doesn't touch files that lane has in flight. Critical path first, then P1, then P2. #164, #166, #280, #281, #282 and #284 are natural floaters.
4. Build ahead against an interface or fake for your next item (e.g. #153 against a fake engine while #245 is open). Keep it on your branch until the blocker lands.
5. Never guess a decision. `team.py decision <n> -m "what must be decided"` and move on.

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
