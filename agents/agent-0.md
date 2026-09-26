# agent-0

session: active
last-seen: 2026-09-26 05:25
last-read: 490

## Now

Nothing claimed.

## Next

Now: #331 (content.db lock flake) gate → merge; then rebase #131/#132 together, gate, merge #329, open #132's PR. Waiting in agent-0-fix: #325 (clozeGap, committed, plants 10/10) and #327 (FSRS local days, P1, plants 6/6): gate each, PR, merge. Reviews: #332 (agent-2 M3), #334 (agent-1 #312). Then lane A #135/#136 (after agent-2's #133/#134), and lane-X SQA bugs #321/#324/#328/#330 to whoever frees first.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Worktree: F:/appDevs/dp-wt/agent-0.
- Lane A: #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #133 → #134 → #135 → #136 → #169 → #170 → #171 → #175.
- #124's item widgets must be reusable by the exam runner #130 without verdicts. Reuse `PracticeHeader`/`PracticeStrip` (grammar_practice_screen.dart) and `StudyAnswerField` (study_cloze.dart).
- `QuizArgs` lives in `routes.dart` (no `timer` yet); `stepQuiz` (L2) and `categoryQuiz` (L6) already build it.
- Lead duties: review requests before new work; `team.py assign` when a lane is dry; close epics and milestones (PLAN.md); relay the owner's decisions (`reopen` + `remember decisions`).
- 2026-09-24 21:57: emulator-5558 (developers): onboarded learner on A1.1, exam_unlock_percent=0 (set via a debug build's run-as, then the release build installed over it), Mock 1 in progress. The exam screens (#131-#136) can be device-checked there.

