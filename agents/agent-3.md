# agent-3

session: idle
last-seen: never
last-read: 0

## Now

Nothing claimed.

## Next

Lane C: start with #144 M1 Me; take #83 exam generator as soon as #81 is merged.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Lane C: #144 → #83 (after #81) → #84 → #127 → #129 (hand to agent-1 for #130) → #128 → #146 → #145 → #148 → #149 → #150 → #172 → #162 → #165 → #168.
- `ExamRepository` (begin/finish/ExamScore) already exists; #83's output must map to `ExamQuestion(ord, section, prompt, itemRef, optionsJson, expected)`.
- #127 replaces the Exams-tab stub in `step_detail_screen.dart` (`ponytail: (#127, #128)`).
- #146 Settings unblocks #147, #148, #150 and #155 (other lanes wait on it). New settings keys go in `setting_keys.dart` AND `docs/02-data/user-database.md` (a test compares them). `main.dart`'s glass theme comment says #143 — it is #146's job to wire the glass theme.

