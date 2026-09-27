# Adding or changing content

1. Edit the workbook in `data/` (or add a new one and register it in `content/manifest.yaml`). `data/` is git-ignored: the workbooks live only in the checkout where content is edited. Keep header names; add words to *All Words* with a `Level`; add grammar rows to *Grammar*.
2. Avoid cells starting with `=`, `-`, `+`, `@` (prefix with text); keep one example per line.
3. `make content` — the tool prints counts per step, uid collisions, what changed since the committed asset (added/removed/changed) and verification results.
4. Changing `german`, `pos`, `english` or `level` of an existing entry changes its uid. The build links the old uid to the new one when it is the same word (same level, German and part of speech; or same German, part of speech and English — PIPE-09), prints each `uid link`, and the app moves the learner's progress along it. Check the links are right. A word that is gone with nothing to link it to **stops the build**: its learners would lose their progress on it. Restore it, or rerun with `--allow-removed` and say so in the release notes.
5. Add interference tips in `content/interference_tips.csv` when a new false friend or trap enters.
6. Run `flutter test test/db/` (the content database tests) and commit `app/assets/db/content.db` and `content_manifest.json` together.
