# user.db — learner data (on device, writable)

Created on first launch from `assets/db/user_schema.sql` (the authoritative DDL) and mirrored by drift table classes so queries are typed. Lives in app-support storage; never leaves the device except through the learner's own export.

## Tables

| Table | Purpose | Key rules |
| --- | --- | --- |
| `schema_version` | migration bookkeeping | drift `MigrationStrategy` bumps it |
| `settings` (key, value) | all preferences | see keys below |
| `enrollments` (sublevel_code PK, started_on, daily_new, study_days_mask, completed_on) | steps started | one row with `completed_on IS NULL` = active step |
| `word_state` (word_uid PK, status, introduced_on, due, stability, difficulty, reps, lapses, fsrs_state, last_review, card_mode, times_logged, note) | per-word learning state | `card_mode`: `plain` or `cloze`; status per BR-STATUS |
| `review_log` (id, word_uid, reviewed_at, rating, source, elapsed_days, scheduled_days) | every rating | never deleted; used for stats and future FSRS optimisation |
| `plan_items` (plan_date, word_uid, kind, sublevel_code, completed_at, skipped) PK(plan_date, word_uid, kind) | the daily plan | open `new` rows with plan_date < today = backlog |
| `grammar_state` (grammar_uid PK, status, due, stability, difficulty, reps, lapses, last_review) | grammar scheduling | same FSRS fields as words |
| `grammar_practice_log` (id, grammar_uid, practised_at, items, correct) | practice history | |
| `sentence_log` (word_uid, ord, shown_on, self_rating) | practice sentences shown | avoids repeats within `sentence_repeat_gap_days` |
| `quiz_attempts` / `quiz_answers` | quizzes | direction, source, seed, per-answer verdict |
| `exam_attempts` (id, sublevel_code, seed, started_at, finished_at, paused_sec, duration_sec, score_points, max_points, passed, status) | mock exams | status: `in_progress`, `finished`, `abandoned` |
| `exam_answers` (attempt_id, ord, section, item_ref, prompt, options_json, expected, given, flagged, points, self_rubric_json) | per question | recordings referenced by path in `given` for Speaking |
| `custom_words` (id, created_at, article, german, meaning, where_seen, example, matched_uid, times_seen) | "My words" | `matched_uid` set when the word exists in content |
| `daily_stats` (day PK, new_done, reviews_done, grammar_done, sentences_done, seconds) | per-day totals | streak and charts |
| `content_updates` (version PK, added, removed, changed_json, seen) | update cards | |
| `translation_cache` | Hy-MT outputs | keyed by (src_lang, tgt_lang, src_text, model) |
| `undo_stack` (id, created_at, payload_json) | last-action undo | trimmed to 20 rows |

## Settings keys and defaults

| Key | Default | Screen |
| --- | --- | --- |
| `daily_new` | 7 | Onboarding, Settings |
| `revise_count` | 10 | Settings |
| `sentence_count` | 3 | Settings |
| `sentence_repeat_gap_days` | 14 | — |
| `study_days_mask` | 127 (Mon–Sun) | Reminder & days |
| `reminder_enabled` / `reminder_time` / `reminder_only_when_due` | 0 / 19:30 / 1 | Reminder & days |
| `auto_advance` | 1 | Settings |
| `pause_new_when_backlog` | 0 | Today, Backlog |
| `backlog_catchup_days` | 30 | — |
| `desired_retention` | 0.90 | Settings |
| `done_stability_days` | 7 | Settings |
| `swipe_to_rate` | 0 | Settings |
| `meaning_language` | `both` | Onboarding, Settings |
| `ui_language` | `en` | Onboarding, Settings |
| `theme_mode` | `system` (light / dark / glass) | Settings |
| `show_pron_bn` | 1 | Settings |
| `tts_engine` / `tts_voice` / `tts_speed` | supertonic / Anna / 1.0 | Settings, Model manager |
| `autoplay_headword` / `autoplay_example` | 1 / 0 | Settings |
| `exam_unlock_percent` / `exam_pass_percent` / `exam_timer_default` | 90 / 60 / 1 | Settings |
| `mt_enabled` / `mt_variant` | 0 / `q1_25` | Settings, Model manager |
| `listening_questions` | 1 | Settings (accessibility) |
| `last_planned_date` | — | engine |
| `learner_name` | — | Me |

## Migrations

Schema version lives in `schema_version` and in drift's `schemaVersion`. Every change ships a migration step in `lib/data/db/migrations.dart` and a test in `test/db/migration_test.dart` that opens a fixture of each previous version. Never drop columns with data; add nullable columns or new tables.

## Transactions

- Rating a card = one transaction: upsert `word_state`, insert `review_log`, update `plan_items`, bump `daily_stats`, push `undo_stack`.
- Plan generation for a day = one transaction.
- Exam answers are written per question so a crash loses at most one answer.

## Backups

`user.db` uses WAL mode. Export (M6) serialises every table except `translation_cache` and `undo_stack` to JSON with the schema version; import validates the version and either replaces or merges (per-word most recent `last_review` wins).
