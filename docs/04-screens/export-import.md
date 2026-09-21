# M6 · Export / import

**Prototype.** `ExportImport`.

**Reached from.** M3, bootstrap error screen. **Leads to.** system share sheet / file picker.

**Layout.** Export card: copy "One JSON file with word states, review log, plans, quiz and exam history, settings and my words. Opens the share sheet — save to Files or Drive, or email it to yourself." · *Export progress · 1.8 MB* · "Last export: never". Import card: chosen file "deutschplan-2026-09-20.json" with preview "2,104 word states · last active 20 Sep · A2.1"; radio *Merge — keep the most recent of each word* / *Replace everything on this phone*; *Import and merge*; *Choose a different file*. Footer "Neither needs an account. The file never passes through a server."

**Functional requirements**
- FR-M6-01 Export = JSON `{schema_version, content_version, exported_at, tables{…}}` excluding `translation_cache`, `undo_stack`; written to a temp file and shared with `share_plus`; recordings are not included (size), noted in the UI.
- FR-M6-02 Import validates schema version (migrate forward if older; refuse if newer), shows the preview before writing.
- FR-M6-03 Merge rule: per table row key, keep the row with the later `last_review`/`updated_at`; `review_log` is unioned by (word_uid, reviewed_at).
- FR-M6-04 Replace wipes user tables in one transaction then inserts; a failed import leaves the previous data intact.

**Tests.** round-trip export→import equality; merge precedence; refuse newer schema.
