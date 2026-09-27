# user.db — learner data (on device, writable)

*On disk the file is `user.sqlite` in app support: `AppDatabase.open` names it `user`, and drift_flutter adds `.sqlite`. These docs call it user.db.*

Created on first launch from `lib/data/db/user_schema.drift`, which is the authoritative DDL *and* the file drift generates the typed table classes from — one source, so the schema and the Dart cannot drift apart (ADR 22). It is ordinary SQL; anything wanting the raw DDL can read it. Lives in app-support storage; never leaves the device except through the learner's own export.

## Tables

| Table | Purpose | Key rules |
| --- | --- | --- |
| `settings` (key, value) | all preferences | see keys below |
| `enrollments` (sublevel_code PK, started_on, daily_new, study_days_mask, completed_on) | steps started | one row with `completed_on IS NULL` = active step |
| `word_state` (word_uid PK, status, introduced_on, due, stability, difficulty, reps, lapses, fsrs_state, last_review, card_mode, times_logged, note, card_mode_manual) | per-word learning state | `card_mode`: `plain` or `cloze`; `card_mode_manual`: 1 once the learner chose the card in W1, so BR-FSRS-06 keeps it (v3, #316); status per BR-STATUS |
| `review_log` (id, word_uid, reviewed_at, rating, source, elapsed_days, scheduled_days) | every rating | kept for stats and future FSRS optimisation; a row goes only with its rating's *Undo*, a step reset (FR-M7-01), *Reset everything* or an import's *Replace* (#700) |
| `plan_items` (plan_date, word_uid, kind, sublevel_code, completed_at, skipped) PK(plan_date, word_uid, kind) | the daily plan | open `new` rows with plan_date < today = backlog |
| `grammar_state` (grammar_uid PK, status, due, stability, difficulty, reps, lapses, last_review) | grammar scheduling | same FSRS fields as words |
| `grammar_practice_log` (id, grammar_uid, practised_at, items, correct) | practice history | |
| `sentence_log` (word_uid, ord, shown_on, self_rating) | practice sentences shown | avoids repeats within `sentence_repeat_gap_days` |
| `quiz_attempts` / `quiz_answers` | quizzes | direction, source, seed, per-answer verdict |
| `exam_attempts` (id, sublevel_code, seed, started_at, finished_at, paused_sec, duration_sec, score_points, max_points, passed, status) | mock exams | status: `in_progress`, `finished`, `abandoned` |
| `exam_answers` (attempt_id, ord, section, item_ref, prompt, options_json, expected, given, flagged, points, self_rubric_json) | per question | recordings referenced by path in `given` for Speaking |
| `custom_words` (id, created_at, article, german, meaning, where_seen, example, matched_uid, times_seen) | "My words" | `matched_uid` set when the word exists in content. Scheduled, a word is `custom:<id>` wherever a course uid goes: `word_state`, `plan_items`, `review_log`, `quiz_answers` (#363) |
| `daily_stats` (day PK, new_done, reviews_done, grammar_done, sentences_done, seconds, completed_shown) | per-day totals | streak and charts; `completed_shown` is 1 once the day's T6 has been shown (FR-T6-01, `claimDayComplete`) |
| `content_updates` (version PK, added, removed, changed_json, seen, recorded_at) | update cards | `recorded_at` is when this device saw the update; `version` is the build time |
| `translation_cache` | Hy-MT outputs | keyed by (src_lang, tgt_lang, src_text, model) |
| `undo_stack` (id, created_at, payload_json) | last-action undo | trimmed to 20 rows |

## Settings keys and defaults

`SettingsRepository` (`lib/data/repositories/`) reads this table into memory once and serves it synchronously, because settings are read during `build`. `setting_keys.dart` is the typed catalogue, and `test/data/settings_repository_test.dart` parses the table below and fails if a key or a default here and there disagree — so this is the source, not a copy of one.

A write is in memory before it is on disk. A write that fails, or a transaction rolled back around one, reads the table back and tells the listeners of what moved, so a reminder scheduled from the write is taken back (`SettingsRepository.guard`, #688). `last_planned_date` and `planned_study_days` are read from the table, not from memory (`fresh`): the background task writes them through its own connection at 00:05, and an app alive since yesterday would otherwise plan the day again, and give a day opened without revisions some (BR-PLAN-08, #688).

| Key | Default | Screen |
| --- | --- | --- |
| `daily_new` | 7 | Onboarding, Settings |
| `revise_count` | 10 | Settings |
| `sentence_count` | 3 | Settings |
| `sentence_repeat_gap_days` | 14 | — |
| `study_days_mask` | 127 (Mon–Sun) | Reminder & days |
| `study_days_history` | — | engine — #377: the masks over time, a JSON list of `{from, mask}` (a change is in force from the next day), so the streak judges each past day by the mask it had |
| `reminder_enabled` / `reminder_time` / `reminder_only_when_due` | 0 / 19:30 / 1 | Reminder & days |
| `auto_advance` | 1 | Settings |
| `pause_new_when_backlog` | 0 | Today, Backlog |
| `backlog_catchup_days` | 30 | — |
| `desired_retention` | 0.90 | Settings |
| `done_stability_days` | 7 | Settings |
| `swipe_to_rate` | 0 | Settings |
| `quiz_custom_words` | 0 | Settings — FR-R2-04's all-learned quizzes ask my words too |
| `meaning_language` | `both` | Onboarding, Settings |
| `ui_language` | `en` | Onboarding, Settings |
| `theme_mode` | `system` (light / dark / glass) | Settings |
| `show_pron_bn` | 1 | Settings; S2's meaning language sets it (off for English only, #527) |
| `tts_engine` / `tts_voice` / `tts_speed` | supertonic / Anna / 1.0 | Settings, Model manager |
| `autoplay_headword` / `autoplay_example` | 1 / 0 | Settings |
| `exam_unlock_percent` / `exam_pass_percent` / `exam_timer_default` | 90 / 60 / 1 | Settings |
| `mt_enabled` | 0 | Settings, Model manager |
| `listening_questions` | 1 | Settings (accessibility) |
| `models_wifi_only` | 1 | Model manager — FR-M4-01's *Wi-Fi only*: model downloads wait for Wi-Fi |
| `last_planned_date` | — | engine |
| `coach_mark_seen` | 0 | Today — FR-S2-03's one-time mark on the primary button |
| `dismissed_cards` | — | Today — FR-T1-06's dismissed contextual cards, a JSON list of ids (`pause`, `voice`, `exams:A2.1`) |
| `recent_searches` | — | Search — FR-R1-04's last 10 searches, newest first, a JSON list |
| `learner_name` | — | Me |
| `exam_timer` | 1 | L11 writes it on *Begin exam* (its switch starts from `exam_timer_default`); L12 reads it, fresh or resumed |
| `last_export` | — | M6 — the day of the last export the share sheet took (`2026-09-20`) |
| `planned_study_days` | 0 | engine — the study-days mask `last_planned_date`'s day was planned with, so an M5 change is tomorrow's (BR-PLAN-08) |

## Migrations

The schema version lives in SQLite's own `PRAGMA user_version`, which drift writes and reads; `AppDatabase.fileSchemaVersion()` reads it back and a test asserts it matches `schemaVersion`. There is no `schema_version` table — it would be a hand-kept second copy of one number, and drift reserves the name (ADR 23).

Each version has a fixture in `app/drift_schemas/drift_schema_v<n>.json`, captured by `make schema-dump`. The fixture is the only record of what a learner's file looks like at that version, since `user_schema.drift` always describes the newest — so it is committed, while everything derived from it (`lib/data/db/schema_versions.dart`, `test/db/generated/`) is regenerated by `make gen`.

Adding a version is four steps: bump `schemaVersion`, change `user_schema.drift`, run `make schema-dump`, run `make gen`. `onUpgrade` (`AppDatabase.upgrade`) turns foreign keys off, then runs drift's generated `stepByStep()` — which raises for a version it has no step for, rather than opening a learner's file against a schema it was never migrated to — and `PRAGMA foreign_key_check` in one transaction, then turns the keys back on (#656). The order matters. SQLite ignores `PRAGMA foreign_keys` inside a transaction, so `Migrator.alterTable`'s own pragma does nothing there, and recreating a parent such as `exam_attempts` with the keys on would let `ON DELETE CASCADE` delete every child row. drift neither wraps `onUpgrade` in a transaction nor re-checks the keys. With the check inside the transaction, a dangling reference rolls the whole migration back and leaves `user_version` at the old version, so the next launch tries again. `test/db/migration_test.dart` then opens every fixture and migrates it forward with no edit of its own, and also checks the live DDL still matches the fixture for its own version — the mistake that actually happens is editing the schema and forgetting to re-dump.

Never drop columns with data; add nullable columns or new tables.

## Transactions

- Rating a card = one transaction: upsert `word_state`, insert `review_log`, update `plan_items`, bump `daily_stats`, push `undo_stack`.
- Rating a practice sentence = one transaction: bump `daily_stats.sentences_done` on the sentence's first rating (a changed answer isn't another sentence, #659), set `sentence_log.self_rating`, and *Not yet*'s Hard rating of the headword, which is a card rating as above. A day of sentences alone is a day studied, for the streak and M1's heat map.
- Plan generation for a day = one transaction.
- Exam answers are written per question so a crash loses at most one answer.

## Backups

`user.db` uses WAL mode. Export (M6) serialises every table except `translation_cache` and `undo_stack` to JSON with the schema version; import validates the version and either replaces or merges (per-word most recent `last_review` wins). A replace keeps every id, so the round trip is exact, except that a `custom:<id>` row whose word isn't in the file stays out, as on a merge (#618). AUTOINCREMENT resumes above the file's highest id, so a deleted word's id is the next one given out, and the learner's next word would otherwise inherit that word's reviews and plan. On a merge, every AUTOINCREMENT id is this phone's to assign, since no row key holds one: quiz and exam attempts and their answers, `review_log`, `grammar_practice_log` and the learner's own words. A word of the learner's own gets a fresh id, or the local one when `(created_at, german)` matches. Every `custom:<id>` in `word_state`, `review_log`, `plan_items` and `quiz_answers` follows the word's new id. A `custom:<id>` whose word isn't in the file stays out, so a merge doesn't carry a deleted word's reviews. A compare quiz's `source_ref` isn't rewritten, since nothing reads it back (#369). Either way an import empties `undo_stack`: an Undo still on screen would put back a word's state from before it (#688). A Speaking answer comes in without its `given`, since the recordings stay on the phone that made them; its points stand (#688).
