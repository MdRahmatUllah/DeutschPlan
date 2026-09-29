# agent-0

session: active
last-seen: 2026-09-30 00:39
last-read: 1870

## Now

#1099 fix(pipeline): English's pronunciation guide ships only when it is 100 % complete — claimed 2026-09-30 00:39.

## Next

v1.0.1 tagged. Watch for agent-3's 1.0.1 SQA report and route findings to 1.0.2 (agent-1/agent-2). Remind the owner: upload key, phone check, emulator-5558 OK.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Worktree: F:/appDevs/dp-wt/agent-0.
- Lane A: #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #133 → #134 → #135 → #136 → #169 → #170 → #171 → #175.
- #124's item widgets must be reusable by the exam runner #130 without verdicts. Reuse `PracticeHeader`/`PracticeStrip` (grammar_practice_screen.dart) and `StudyAnswerField` (study_cloze.dart).
- `QuizArgs` lives in `routes.dart` (no `timer` yet); `stepQuiz` (L2) and `categoryQuiz` (L6) already build it.
- Lead duties: review requests before new work; `team.py assign` when a lane is dry; close epics and milestones (PLAN.md); relay the owner's decisions (`reopen` + `remember decisions`).
- 2026-09-24 21:57: emulator-5558 (developers): onboarded learner on A1.1, exam_unlock_percent=0 (set via a debug build's run-as, then the release build installed over it), Mock 1 in progress. The exam screens (#131-#136) can be device-checked there.
- 2026-09-30 00:27: M8 set up (milestone 11, 38 issues; epic #1085 body has the plan + order). NEXT for agent-0: PR #1087 fixes in dp-wt/agent-0-fix — scheme doc: English stress rule (phrase stress, agent-3 #3), nk row + DANK-uh, OWSS-fewl-len; Polish ich -> ś (IŚ, MET-śen, NIŚC, -iś), capitals approved; Open questions -> Decisions; add a conventions section (masculine where German gives no gender; short meanings with ' / '; same text across workbooks). Pilot staging data/_staging/{en,pl}: danke/Danke schön/ausfüllen (en); ś rows, doch 'ależ tak (po przeczeniu) / jednak', dieser 'ten / ta / to', Kollege 'kolegą z pracy' (pl). Merge-tool guard: new column at ws.max_column+1 or refuse non-empty cells + probe test (agent-1). Then #1099 (claimed), then content per workbook with subagents. Russian pilot still awaits agent-2's review. Review PR #1097 (agent-1) if agent-2 hasn't.

