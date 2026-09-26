---
name: basic-gate-per-pr
description: "Owner rule — a PR needs only a basic check (analyze, format, touched tests, plants) to merge; the full suite runs at milestone completion"
metadata:
  type: feedback
---

A PR merges on a **basic check**: `dart analyze --fatal-infos`, `dart format --set-exit-if-changed`, pytest if tools changed, the test files the PR touches (plus their goldens), and the plants. The full `flutter test` suite runs once, when a milestone is complete, not per PR.

**Why:** the owner, on 2026-09-25, after full `-j 2` gates kept being reaped for low memory (three agents plus the emulator share the machine): "You can have a basic test and push the pr and merge then we can test once a milestone is complete."

**How to apply:** don't queue full-suite gates per PR. Run the touched tests in the foreground, push, review, and merge. Before a milestone closes, run the full suite once (with `-j 2`, alone) and fix what it finds. Tell the agents the same. Supersedes the per-PR part of [[full-suite-j2]]. Related: [[merge-open-prs-first]], [[ci-minutes]].
