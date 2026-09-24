# agent-1

session: active
last-seen: 2026-09-24 10:45
last-read: 0

## Now

Setting up the team: the onboarding guide PR (CLAUDE.md, ONBOARDING.md, tools/team.py and friends).

## Next

Merge the guide PR, then lane A: #81 quiz_builder (it unblocks #83, #122, #142).

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Lane A (critical path): #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #133 → #134 → #135 → #136 → #169.
- #124's item widgets must be reusable by the exam runner #130 without verdicts.
- `QuizArgs` lives in `routes.dart`; L2 (`stepQuiz`) and L6 (`categoryQuiz`) already build it; it lacks `timer`.
- Reuse `PracticeHeader`/`PracticeStrip` (grammar_practice_screen.dart) and `StudyAnswerField` (study_cloze.dart) in the runner.

