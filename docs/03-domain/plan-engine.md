# Plan engine

`domain/plan_engine.dart` — pure Dart. Implements BR-PLAN-01…10 and BR-COURSE-04/05.

## openDay(date) — idempotent

```
1. generateNewThrough(date)        // fills missed study days up to backlog_catchup_days
2. ensureRevise(date)              // picks revise_count cards once per date
3. ensureGrammarDue(date)          // topics with due <= date
4. sentences = SentencePicker.forDay(date)   // persisted in sentence_log
5. return DailyPlan(revise, newToday, grammarDue, backlog, sentences, activeStep, estimateMinutes)
```

A day is opened atomically: steps 1 and 2 run in one transaction (`PlanStore.atomically`), so callers that overlap (setup's finish and a live Today) plan it once (#548). *Start next step* and L2's *Start* are atomic the same way.

### generateNewThrough

```
day = last_planned_date + 1  (or enrollment.started_on)
day = max(day, today - backlog_catchup_days)
for each day ≤ today:
  if !isStudyDay(day) or pause_new_when_backlog && backlogNotEmpty: continue
  need = daily_new(enrollment)
  while need > 0:
    picked = next To-do words of active step in seq order not yet planned, limit need
    insert plan_items(day, uid, 'new')
    need -= picked.length
    if need > 0:  // step exhausted
      mark enrollment completed_on = day
      if !auto_advance or no next step: break
      enroll(next step, started_on = day, daily_new same)
last_planned_date = max(last_planned_date, today)
```

`last_planned_date` never moves back (#346): a clock or time zone that goes back reopens a past day as it was planned. Recording it would plan the days after it again, and give a finished day a Revise block. A day with no active step, after the course or after a step with auto-advance off, is recorded too, with no new words and as a study day (the finished step's rest days no longer apply, as `streak` counts them), so it picks its Revise block once like any other (BR-PLAN-08, #457). A step started on such a day (L2's *Start*, restart setup) begins tomorrow, as it does over an active step; *Start next step* moves the date back and begins today. Before onboarding nothing is recorded: a first step enrolled today still plans today.

### ensureRevise (BR-PLAN-03)

1. Due first: `word_state.status IN (learning, done) AND due <= day 23:59`, excluding today's new words and suspended words, ordered by due, limit n.
2. Fill: remaining slots from learned words ordered by `(day - last_review) / stability DESC` (lowest retrievability first).
3. Persist as `plan_items(day, uid, 'revise')`. A course word's row carries its own step. A word of the learner's own (`custom:<id>`, #363) carries the step being studied, or the last one started. It is a candidate from the day it is added to revision, due, before its first review, and never once its `custom_words` row is gone.

### Backlog

`plan_items WHERE kind='new' AND completed_at IS NULL AND plan_date < today`, grouped by `plan_date` descending; not a suspended word's row (#368), nor a course word a content update removed from `c.words` (BR-CONTENT-02, #456), whose rows stay. Skip sets `skipped=1` without completing.

### Rest day

`isStudyDay(date) == false` → no new rows, no backlog generation for that day, revise is still offered (optional), `daily_stats` counts as complete for the streak.

Today keeps the study days it was planned with (BR-PLAN-08, #147): planning a day records the mask as `planned_study_days`, and `openDay` decides that day's `isStudyDay` from it. Switching today off in M5 leaves today a study day, and switching a rest day on leaves it a rest day; the new mask plans tomorrow.

## Completion and statuses

- `rate(uid, rating, planDate?, kind?, source)` → `Fsrs.review` → upsert `word_state`; status = `done` if `stability >= done_stability_days` else `learning`, except that a suspended word stays suspended (BR-STATUS-03, #351); `card_mode = cloze` after two consecutive ≥ Good and back to plain on a rating below Good, unless `card_mode_manual` says the learner chose it; write `review_log`, mark `plan_items.completed_at`, bump `daily_stats`, push undo.
- `markKnown(uid)` = `rate(uid, 4, source: known)`.
- `suspend(uid)` sets `suspended` and keeps the FSRS state. W1's also drops the word's open revision for today and skips its open `new` row for today (#351). Its backlog rows stay (#368): T4 lists them without studying them, while `backlogBefore`, Today's backlog and the backlog pause (BR-PLAN-07) leave a suspended word's rows out. `resume(uid)` derives the status from the schedule. The new-word pick and the revision candidates leave suspended words out.
- Day complete (BR-PLAN-10) is computed, not stored: all today's plan items completed or skipped, grammar due empty, sentences rated or `sentence_count == 0`.

## Schedule check ("Am I on schedule?")

`planned = COUNT(new items with plan_date <= today)`, `introduced = COUNT(new items completed)`, `behind = planned - introduced`; days behind = `behind / daily_new`.

## Streak

Count consecutive days back from today (or yesterday if today has no activity yet) where `daily_stats` has activity **or** the day was a rest day.

Each past day is judged by the study-days mask in force *on it* (#377). `study_days_history` keeps the masks over time; a change in M5 or restart setup is in force from the next day (BR-PLAN-08), or from today when today isn't planned yet (it will be planned with the new one), and the first change also keeps the mask before it. So turning a rest day on never breaks a streak already earned, turning one off never mends a missed one, and a day after the change is judged by the new mask. With no history, and from the last change on, a day is judged by the enrolment's mask: a stale history (a merged backup's) never overrules it.

## Time estimate (BR-PLAN-09)

Defaults 25/45/60/40 s; after 7 sessions use the learner's median seconds per item type from `review_log` timestamps (grammar from `grammar_practice_log`), the gaps taken within each local day (a stored UTC instant is grouped by its local date, #347).

## Tests (must exist)

`test/domain/plan_engine_test.dart`: first day, missed two days → backlog 14, skip → backlog next day, rest day no growth, step exhausted → auto-advance, pause flag, revise fill order, idempotent reopen, midnight rollover.
