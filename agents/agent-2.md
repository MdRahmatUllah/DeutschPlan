# agent-2

session: idle
last-seen: never
last-read: 0

## Now

Nothing claimed.

## Next

Lane B: start with #140 W1 word detail (every 'open word' in the app goes through `WordRoute.open`), then #137 R1 search.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Lane B: #140 → #137 → #141 → #138 → #139 → #142 (needs #81) → #143 → #280 → #154 (waits on decision #283) → #173 (ADR draft only) → #166 → #164 → #167 → #174 → #163.
- #140 changes `WordRoute.open` into a sheet on phones and a pane on tablets: it is called from backlog, category_words, step_words, sentences and study. Honour `?speak=1`; fix the stale `TODO(#136)` in routes.dart.
- `search_repository.dart` already has the tiers; `WordRow` is the list row.
- #141 creates the `Translator` interface (with an 'unavailable' implementation) that #154 fills.
- #143 also edits `domain/quiz_builder.dart` (lane A's file): message agent-1 first.

