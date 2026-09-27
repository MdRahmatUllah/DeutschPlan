# M6 · Export / import

**Prototype.** `ExportImport`.

**Reached from.** M3, bootstrap error screen. **Leads to.** system share sheet / file picker.

**Layout.** Export card: copy "One JSON file with word states, review log, plans, quiz and exam history, settings and my words. Opens the share sheet — save to Files or Drive, or email it to yourself." · *Export progress · 1.8 MB* · "Last export: never". Import card: chosen file "sogda-2026-09-20.json" with preview "2,104 word states · last active 20 Sep · A2.1"; radio *Merge — keep the most recent of each word* / *Replace everything on this phone*; *Import and merge*; *Choose a different file*. Footer "Neither needs an account. The file never passes through a server."

**Filled in by #148:**
- The export's size is the file's own, built and measured when M6 opens: "Export progress · 1.8 MB", or KB under a megabyte. The file is `sogda-<yyyy-mm-dd>.json`.
- "Last export: 20 Sep" is `last_export`, the day of the last export the share sheet took. Dismissing the sheet isn't an export.
- A caption under it says the Speaking recordings stay on the phone (FR-M6-01's note).
- Before a file is chosen, the import card is one *Choose a file* button. The picker takes any file, because an export saved from a mail or a chat often loses its JSON type; the preview refuses what isn't a backup. Backing out of the picker keeps the file already chosen.
- Under the artboard's preview line, a second says when the file was exported and what else it holds, so a learner can judge a *Replace* (#396): "Exported 20 Sep · 5,321 reviews · 30 days planned · 4 quizzes · 1 exam · 3 words of my own". The reviews are `review_log`'s rows, the days planned `plan_items`' distinct `plan_date`s, the quizzes and exams their attempts, and the words `custom_words`; a count of none is left out.
- A file that can't be previewed shows its name and why in the Coral text colour: not a Sogda export, or from a newer build. The radios and the button stay hidden.
- The button follows the radio: *Import and merge*, or *Import and replace*. Replace asks first ("Replace everything on this phone?", *Replace* / *Keep my data*), because nothing brings the data back.
- After an import, the settings are read again (`SettingsRepository.reload`) and Today's plan is re-read. A toast says *Imported*, and the card is back to *Choose a file*. A failed import says "Nothing on this phone changed", which FR-M6-04's single transaction makes true.
- The radios are drawn the same on both platforms, as the artboards draw them: a screen reader hears one group, and which one is checked.

**Functional requirements**
- FR-M6-01 Export = JSON `{schema_version, content_version, exported_at, tables{…}}` excluding `translation_cache`, `undo_stack`; written to a temp file and shared with `share_plus`; recordings are not included (size), noted in the UI.
- FR-M6-02 Import validates schema version (migrate forward if older; refuse if newer), shows the preview before writing.
- FR-M6-03 Merge rule: per table row key, keep the row with the later `last_review`/`updated_at`; `review_log` is unioned by (word_uid, reviewed_at). Words of the learner's own come in under this phone's ids, and their `custom:<id>` rows follow them (#369, `user-database.md`).
  - Onto a phone where nothing has been studied yet (no `review_log` and no `grammar_practice_log`), a file with enrolments says where the learner is (#658). M6 comes after onboarding, so such a phone always has setup's first guess: an open step, its pace and study days, and today's plan. The file's enrolments and plan replace this phone's, and its settings win key by key; a key the file lacks stays. Everything else merges as above. On a phone in use, this phone's open step and settings stay, and an imported open step comes in closed.
- FR-M6-04 Replace wipes user tables in one transaction then inserts; a failed import leaves the previous data intact.

**Tests.** round-trip export→import equality; merge precedence; refuse newer schema.
