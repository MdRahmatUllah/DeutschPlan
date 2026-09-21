# Adding or changing content

1. Edit the workbook at the repository root (or add a new one and register it in `content/manifest.yaml`). Keep header names; add words to *All Words* with a `Level`; add grammar rows to *Grammar*.
2. Avoid cells starting with `=`, `-`, `+`, `@` (prefix with text); keep one example per line.
3. `make content` — the tool prints counts per step, uid collisions and verification results.
4. Review `content/build/content_manifest.json` diff: added/removed/changed uids. Changing `german`, `pos` or `english` of an existing entry changes its uid and **resets that word's progress for learners** — prefer editing other columns, or accept and note it in the release notes.
5. Add interference tips in `content/interference_tips.csv` when a new false friend or trap enters.
6. Run `flutter test test/data/` (content data tests) and commit workbook + manifest + asset together.
