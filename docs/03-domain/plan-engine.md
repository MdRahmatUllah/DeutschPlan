# Plan engine

`domain/plan_engine.dart` — pure Dart. Implements BR-PLAN-01…10 and BR-COURSE-04/05.

## openDay(date) — idempotent

```
atomically:
  reopened = last_planned_date >= date   // a day opened before (#342)
  1. generateNewThrough(date)            // fills missed study days up to backlog_catchup_days
  2. if !reopened: ensureRevise(date)    // picks revise_count cards once per date
3. return DailyPlan(revise, newToday, grammarDue, backlog, activeStep,
                    nextStep, stepComplete, isStudyDay, newPaused)
```

`grammarDue` is read, not planned: the topics with `due <= date`. The day's sentences are `SentencePicker.forDay(date)`'s, persisted in `sentence_log`, and its time is `PlanEngine.estimate(plan)` (BR-PLAN-09); Today asks for both after opening the day.

A day is opened atomically: steps 1 and 2 run in one transaction (`PlanStore.atomically`), so callers that overlap (setup's finish and a live Today) plan it once (#548). *Start next step* and L2's *Start* are atomic the same way.

### generateNewThrough

```
day = last_planned_date + 1  (or enrollment.started_on)
day = max(day, today - backlog_catchup_days)
for each day ≤ today:
  if !isStudyDay(day) or pause_new_when_backlog && backlogNotEmpty: continue
  need = daily_new(enrollment) - the course's new words planned on day already  // #687; the document queue's don't count (BR-PLAN-11)
  if need <= 0: continue   // reopening a day never doubles it
  while need > 0:
    picked = next To-do words of active step in seq order not yet planned, limit need
    insert plan_items(day, uid, 'new')
    need -= picked.length
    if need > 0:  // step exhausted
      mark enrollment completed_on = day
      if !auto_advance or no next step: break
      enroll(next step, started_on = day, daily_new same)
if today was walked, is a study day and not paused:   // BR-PLAN-11, today only
  picked = the document queue's oldest waiting words, limit doc_daily_cap - today's already
  insert plan_items(today, uid, 'new'); doc_queue.planned_on = today
last_planned_date = max(last_planned_date, today)
```

`last_planned_date` never moves back (#346): a clock or time zone that goes back reopens a past day as it was planned. Recording it would plan the days after it again, and give a finished day a Revise block. A day with no active step, after the course or after a step with auto-advance off, is recorded too, with no new words and as a study day (the finished step's rest days no longer apply, as `streak` counts them), so it picks its Revise block once like any other (BR-PLAN-08, #457). A step started on such a day (L2's *Start*, restart setup) begins tomorrow, as it does over an active step; *Start next step* moves the date back and plans today again at once: a day the last step ran out on part-way through is topped up to the new pace from the new step, and today stays opened, so it keeps the Revise block it picked (#342, #687). An *Import and merge* doesn't move it: it plans today again in place (`replanToday`, #622, #937). The import has dropped the open `new` rows of words that now have a schedule, on every day, and today's open revisions. `replanToday` then tops today's new words up to the pace from words not met yet, under the mask today was planned with (BR-PLAN-08, so a setup day stays a study day, #606), and today's revisions up to `revise_count` from the merged schedule, leaving out what today already holds. What was done today stays (`export-import.md`). Before onboarding nothing is recorded: a first step enrolled today still plans today.

### The document queue (BR-PLAN-11)

Words a learner adds from a document (D2's *Add*, BR-DOC-04) wait in `doc_queue` in the order added. A study day takes up to `doc_daily_cap` of them, after the course's new words and outside `daily_new`, as ordinary `new` rows, so a session, the time estimate (BR-PLAN-09) and the day's completion treat them as new words. `planned_on` records the day each went into a plan, which is how a day counts the slots it has used, but only while that day still holds the word's `new` row: the plan is the truth, and the queue's day is a note. So a day whose rows went (a merge where the file wins, #658; *Reset word*) frees its queue words. They wait again, in their place, and the day's course words aren't counted short (#1285).
- **Today only.** A missed day walked by the catch-up gets the course's words and none of the queue's, which would be backlog. The queue's words wait instead, and are never backlog. Once planned, a word not studied is backlog like any new word.
- **Waiting** means not planned by any route (its day, the course's own New today, W1's *Add to today*), still To-do, and still a word of the course. A removed word's row stays unread, as its history does (BR-CONTENT-02). A rest day, the backlog pause (BR-PLAN-07) and a cap of 0 take none.
- **`addDocWords(uids, today)`** (FR-D2-02/03) queues the words, lets an opened study day take its share at once, and answers each word's first day: today, the study day the queue reaches it on under the cap (rest days skipped), or none with a cap of 0 or while the backlog pause holds, since the queue then waits for the backlog and no day can be said. A day not opened yet keeps its share for when it opens. `replanToday` (an import's merge) tops today up the same way.
- **No step under way** (a finished step with *Auto-advance* off, or the course done) holds nothing back: document words aren't the step's. The day opens as a study day, as `generateNewThrough` plans it, and takes its share; *Add*, `docSlotsLeft` and `replanToday` treat it so too.
- **The cap a day opened with** holds for that day (BR-PLAN-08): opening it records `doc_daily_cap` as `planned_doc_cap`, and *Add*, `replanToday` and `docSlotsLeft` read today's room from it. An M3 change plans the next day, and `addDocWords`' start days after today use it.

### ensureRevise (BR-PLAN-03)

1. Due first: `word_state.status IN (learning, done) AND due <= day 23:59`, excluding today's new words and suspended words, ordered by due, limit n.
2. Fill: remaining slots from learned words ordered by `(day - last_review) / stability DESC` (lowest retrievability first).
3. Persist as `plan_items(day, uid, 'revise')`. A course word's row carries its own step. A word of the learner's own (`custom:<id>`, #363) carries the step being studied, or the last one started. It is a candidate from the day it is added to revision, due, before its first review, and never once its `custom_words` row is gone.

### Backlog

`plan_items WHERE kind='new' AND completed_at IS NULL AND plan_date < today`, grouped by `plan_date` descending; not a suspended word's row (#368), nor a course word a content update removed from `c.words` (BR-CONTENT-02, #456), whose rows stay. Skip sets `skipped=1` without completing.

### Rest day

`isStudyDay(date) == false` → no new rows, no backlog generation for that day, revise is still offered (optional), and the streak carries over it without growing (see Streak).

Today keeps the study days it was planned with (BR-PLAN-08, #147): planning a day records the mask as `planned_study_days`, and `openDay` decides that day's `isStudyDay` from it. Switching today off in M5 leaves today a study day, and switching a rest day on leaves it a rest day; the new mask plans tomorrow.

## Completion and statuses

- `rate(uid, rating, planDate?, kind?, source)` → `Fsrs.review` → upsert `word_state`; status = `done` if `stability >= done_stability_days` else `learning`, except that a suspended word stays suspended (BR-STATUS-03, #351); `card_mode = cloze` after two consecutive ≥ Good and back to plain on a rating below Good, unless `card_mode_manual` says the learner chose it; write `review_log`, mark `plan_items.completed_at`, bump `daily_stats`, push undo.
- `markKnown(uid)` = `rate(uid, 4, source: known)`.
- `suspend(uid)` sets `suspended` and keeps the FSRS state. W1's also drops the word's open revision for today and skips its open `new` row for today (#351). Its backlog rows stay (#368): T4 lists them without studying them, while `backlogBefore`, Today's backlog and the backlog pause (BR-PLAN-07) leave a suspended word's rows out. `resume(uid)` derives the status from the schedule. The new-word pick and the revision candidates leave suspended words out.
- The day's grammar (`PlanStore.grammarOfDay`, #754) is the topics due on it and the ones practised on it (`grammar_practice_log`, the learner's local day): practice moves a topic's due on, so without the log a day built again would drop what it had done. What is still due is `grammarDueOn`.
- Day complete (BR-PLAN-10) is computed, not stored: all today's plan items completed or skipped, grammar due empty, sentences rated or `sentence_count == 0`.

## Schedule check ("Am I on schedule?")

`planned = COUNT(new items with plan_date <= today)`, `introduced = COUNT(new items completed)`, `behind = planned - introduced`; days behind = `behind / daily_new`.

## Streak

Walk back from today (or from yesterday if today has no activity yet) and count the days with activity in `daily_stats`. A rest day with none carries the streak without lengthening it, so a two-day study week never claims seven; a study day with none ends it (#687).

Each past day is judged by the study-days mask in force *on it* (#377). `study_days_history` keeps the masks over time; a change in M5 or restart setup is in force from the next day (BR-PLAN-08), or from today when today isn't planned yet (it will be planned with the new one), and the first change also keeps the mask before it. So turning a rest day on never breaks a streak already earned, turning one off never mends a missed one, and a day after the change is judged by the new mask. With no history, and from the last change on, a day is judged by the enrolment's mask: a stale history (a merged backup's) never overrules it. With no step open (after the course, or a step with auto-advance off), the days up to the day the last step closed are judged by that step's mask, so finishing a step or the course never shrinks the streak or the best one, and the days after it as study days, as they are planned (#457, #615).

## Time estimate (BR-PLAN-09)

Defaults 25/45/60/40 s; after 7 sessions use the learner's median seconds per item type from `review_log` timestamps (grammar from `grammar_practice_log`), the gaps taken within each local day (a stored UTC instant is grouped by its local date, #347). The window is the last 30 study days (`daily_stats` days with activity) before the plan date, today excluded (#708): the answer can't change during the day, so the engine reads it once per plan date rather than on every rebuild of Today, and the read stays the same size however long the history grows. Tomorrow's preview reads it afresh each time and keeps nothing (#817): it is drawn while today can still be studied, and the engine outlives midnight.

## Tests (must exist)

`test/domain/plan_engine_test.dart`: first day, missed two days → backlog 14, skip → backlog next day, rest day no growth, step exhausted → auto-advance, pause flag, revise fill order, idempotent reopen, midnight rollover.
