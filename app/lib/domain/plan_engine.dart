/// BR-PLAN-01…05 and BR-COURSE-04. `docs/03-domain/plan-engine.md`.
///
/// The heart of the product: what the learner is asked to do today, and what
/// they were asked to do on the days they missed.
///
/// Plain Dart. It reaches storage through [PlanStore], which `data/` implements
/// over drift — so every rule below is testable against a map in memory,
/// without a database or a Flutter binding. That is not ceremony: the rules
/// here are about *dates*, and a test that has to build a database to move the
/// calendar forward is a test nobody writes.
///
/// #76 built `openDay`, `generateNewThrough` and `ensureRevise`; #77 added the
/// backlog pause, auto-advance and the step-complete state. `rate` and friends
/// are #78; the streak, the schedule check and the time estimate are #79;
/// practice sentences are #80.
library;

import 'dart:convert';

import 'package:sogda/domain/dry_run_plan_store.dart';
import 'package:sogda/domain/fsrs.dart';
import 'package:sogda/domain/plan_stats.dart';

/// A local date, `YYYY-MM-DD` — the same shape every date column uses.
///
/// A study day is a local day (BR-PLAN-01), so the engine works in dates and
/// never in instants. An interval measured in hours would put two cards of the
/// same day on either side of a boundary the learner cannot see.
typedef PlanDate = String;

/// Formats a local [DateTime] as a [PlanDate].
PlanDate planDate(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// Parses a [PlanDate] to midnight UTC.
///
/// UTC because a [PlanDate] is a calendar date, not an instant, and calendar
/// arithmetic on local midnights is wrong twice a year: across spring-forward
/// two consecutive local midnights are 23 hours apart, so `difference().inDays`
/// between them is *zero*. A card due on 29 March would read as not yet due on
/// the 30th, and the day-by-day walk would skip a day.
///
/// The weekday is the same either way, so [PlanEngine.isStudyDay] is unaffected.
DateTime parsePlanDate(PlanDate date) {
  final parts = date.split('-');
  if (parts.length != 3) {
    throw ArgumentError.value(date, 'date', 'expects YYYY-MM-DD');
  }
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// [days] calendar days after [date].
///
/// Safe because [parsePlanDate] anchors in UTC, where a day is always 24
/// hours. The same arithmetic on a *local* midnight drifts by an hour across a
/// daylight-saving change and in October lands on the previous day — which is
/// the reason for the UTC anchor, not for the constructor used here.
PlanDate addDays(PlanDate date, int days) {
  final day = parsePlanDate(date);
  return planDate(DateTime.utc(day.year, day.month, day.day + days));
}

/// Whole days from [from] to [to]; negative when [to] is earlier.
///
/// Exact, because [parsePlanDate] anchors both ends in UTC. The same
/// subtraction on local midnights loses a day at every spring-forward.
int daysBetween(PlanDate from, PlanDate to) =>
    parsePlanDate(to).difference(parsePlanDate(from)).inDays;

/// The open enrollment: the step the learner is studying (BR-COURSE-04).
///
/// Named for what it is rather than the table it comes from, which also keeps
/// it clear of drift's generated `Enrollment` row.
class ActiveStep {
  const ActiveStep({
    required this.sublevelCode,
    required this.startedOn,
    required this.dailyNew,
    required this.studyDaysMask,
  });

  final String sublevelCode;
  final PlanDate startedOn;

  /// The step's pace, set at enrollment and moved by M3 and restart setup.
  /// BR-PLAN-08: a change reaches the plan from tomorrow; days already
  /// planned are not rewritten.
  final int dailyNew;
  final int studyDaysMask;
}

/// A word the learner has met, with the FSRS fields the revise fill ranks on.
class RevisionCandidate {
  const RevisionCandidate({
    required this.uid,
    required this.stability,
    required this.lastReview,
    this.due,
  });

  final String uid;
  final double stability;

  /// The local day it was last reviewed.
  final PlanDate lastReview;

  /// The local day it falls due, or null for a word with no schedule yet.
  final PlanDate? due;
}

/// What the engine needs from storage.
///
/// Deliberately narrow: every method here is one query, and nothing on it
/// knows about drift. The alternative — handing the engine a database — would
/// put the revise ordering in SQL, where it could not use the same
/// retrievability formula the scheduler does.
abstract interface class PlanStore {
  /// Runs [body] as one unit: no other [atomically] block, and no other
  /// write, runs until it completes (#548).
  ///
  /// What makes opening a day happen once. Its no-double guard reads, then
  /// writes; two openings that overlap (setup's finish and a live Today)
  /// would both read an empty day and both plan it.
  Future<T> atomically<T>(Future<T> Function() body);

  /// The open enrollment, or null before the learner has started a step.
  Future<ActiveStep?> activeStep();

  /// #377: the study-days masks in force over time, oldest first; empty
  /// when they have never changed.
  Future<List<MaskSpan>> studyDaysHistory();

  /// The next [limit] To-do words of [sublevelCode] in teaching order that
  /// have never been planned.
  Future<List<String>> unplannedWords(
    String sublevelCode, {
    required int limit,
  });

  /// Every word the learner has met and not suspended, with its FSRS fields.
  ///
  /// The whole set rather than a top-n, because the engine ranks it with
  /// [Fsrs.retrievability] — the same formula the scheduler uses. Ordering in
  /// SQL would mean a second, drifting copy of the forgetting curve. At course
  /// scale this is a few thousand rows of three columns.
  Future<List<RevisionCandidate>> revisionCandidates();

  /// The words already planned on [date], by kind, **in the order they were
  /// planned**.
  ///
  /// A list rather than a set, because the order is the answer: the learner
  /// walks the new words in teaching order and the revisions in BR-PLAN-03's
  /// priority, and both of those are the order the engine wrote them in. A set
  /// would say the order does not matter and then be relied on for it anyway.
  Future<List<String>> plannedOn(PlanDate date, PlanKind kind);

  /// Grammar topics whose FSRS due falls on or before [date].
  Future<List<String>> grammarDueOn(PlanDate date);

  /// The day's grammar (#754): [grammarDueOn], and every topic practised on
  /// [date], whose practice moved its due on. So a day built again (a
  /// restart, *Start* on another step) keeps what it has done.
  Future<List<String>> grammarOfDay(PlanDate date);

  /// Adds plan rows. Rows already present are left alone — that is what makes
  /// reopening a day idempotent (BR-PLAN-04).
  Future<void> addToPlan(PlanDate date, PlanKind kind, List<String> uids);

  /// BR-PLAN-11: the document queue's words still waiting, oldest first, at
  /// most [limit]: not planned yet by any route (its own day, the course's
  /// New today, W1's *Add to today*), still To-do, and still in the course.
  Future<List<String>> docWaiting({required int limit});

  /// The queue's words that went into [date]'s plan: its used slots.
  Future<List<String>> docPlannedOn(PlanDate date);

  /// Records [uids] as planned on [date] (`doc_queue.planned_on`).
  Future<void> markDocPlanned(PlanDate date, List<String> uids);

  /// Puts [uids] at the end of the queue as of [at]; a word already queued
  /// keeps its place (BR-DOC-04's *Add*).
  Future<void> queueDocWords(List<String> uids, String at);

  /// Open `new` rows from before [today], newest day first (BR-PLAN-05).
  Future<List<String>> backlogBefore(PlanDate today);

  /// The last date `generateNewThrough` ran to, or null on a fresh install.
  Future<PlanDate?> lastPlannedDate();
  Future<void> setLastPlannedDate(PlanDate date);

  /// The study days [lastPlannedDate]'s day was planned with, or null before
  /// one was recorded. BR-PLAN-08: that day stays what it was opened as,
  /// study day or rest day, whatever the mask says since (#147).
  Future<int?> plannedMask();
  Future<void> setPlannedMask(int mask);

  /// The step after [sublevelCode] in course order, or null at the end of the
  /// course (BR-COURSE-05).
  Future<String?> stepAfter(String sublevelCode);

  /// Closes the enrollment for [sublevelCode] as finished on [on].
  Future<void> completeStep(String sublevelCode, PlanDate on);

  /// Opens an enrollment. The pace carries over from the step that finished:
  /// BR-PLAN-08 freezes it per enrollment, and advancing a step is not the
  /// learner changing their mind about it.
  Future<void> enroll(ActiveStep step);

  /// Whether the learner has ever enrolled.
  ///
  /// What separates "has finished a step and not started the next" from "has
  /// never started" — both have no active step, and Today shows a different
  /// thing for each (BR-COURSE-05).
  Future<bool> hasEverEnrolled();

  /// The step whose enrollment closed most recently, or null if none has.
  ///
  /// Only used to name the step *after* it, for Today's *Start next step*.
  Future<String?> lastCompletedStep();

  /// #615: the day the enrollment [lastCompletedStep] names closed on, and
  /// its study-days mask; null if none has. With no step open, the streak
  /// judges the days up to then by it.
  Future<({PlanDate on, int mask})?> lastCompletedMask();

  /// The days on or before [today] that have any activity recorded, for the
  /// streak. Bounded by [lookbackDays] so it is one small query, not a scan.
  Future<Set<PlanDate>> activeDays(PlanDate today, {required int lookbackDays});

  /// New items planned on or before [today], and how many are done — the two
  /// halves of the schedule check.
  Future<(int planned, int introduced)> newItemProgress(PlanDate today);

  /// How many plan rows of [date] are neither completed nor skipped.
  Future<int> openPlanItems(PlanDate date);

  /// The learner's own median seconds per item, or null where there is not
  /// enough history to measure one (BR-PLAN-09): over the last
  /// [measuredTimingsWindow] study days before [before], so the answer is
  /// fixed for the day and the read does not grow with the history (#708).
  Future<MeasuredSeconds> measuredSeconds(PlanDate before);
}

/// What could be measured from the logs, per item type.
///
/// A null field means "not measurable", which is not the same as zero: the
/// caller keeps the default for it.
class MeasuredSeconds {
  const MeasuredSeconds({
    required this.sessions,
    this.revision,
    this.newWord,
    this.grammar,
  });

  /// Days with any activity, counted up to [measuredTimingsWindow].
  /// BR-PLAN-09 wants seven before it trusts these.
  final int sessions;

  final int? revision;
  final int? newWord;
  final int? grammar;

  /// Sentences are missing on purpose: `sentence_log` stores `shown_on` as a
  /// date, not an instant, so there is no gap to measure. The 40-second
  /// default stands until something records a timestamp.
  bool get enough => sessions >= measuredTimingsAfterSessions;
}

/// Which block a plan row belongs to.
enum PlanKind {
  newWord('new'),
  revise('revise');

  const PlanKind(this.wire);

  /// What `plan_items.kind` stores.
  final String wire;
}

/// A day's plan, in BR-PLAN-02 order.
class DailyPlan {
  const DailyPlan({
    required this.date,
    required this.revise,
    required this.newToday,
    required this.grammarDue,
    required this.backlog,
    required this.activeStep,
    required this.isStudyDay,
    this.nextStep,
    this.stepComplete = false,
    this.newPaused = false,
  });

  final PlanDate date;

  /// BR-PLAN-02 puts these in order: Revise, then New today, then Grammar due,
  /// then Practice sentences. Sentences are not plan rows: the sentence picker
  /// keeps them in `sentence_log`, and Today reads them from there.
  final List<String> revise;
  final List<String> newToday;
  final List<String> grammarDue;

  /// New words planned for an earlier day and still open (BR-PLAN-05).
  final List<String> backlog;

  /// Null before the learner has enrolled, and between finishing a step and
  /// starting the next with auto-advance off.
  final String? activeStep;

  /// The step that follows, when there is no active one (BR-COURSE-05).
  ///
  /// Today shows "Step complete" and offers *Start next step*; null here with
  /// [stepComplete] true means the course itself is finished.
  final String? nextStep;

  /// The active step ran out and nothing replaced it (BR-COURSE-05).
  ///
  /// Distinct from having never enrolled, which also leaves [activeStep] null
  /// but is the onboarding case rather than a finished step.
  final bool stepComplete;

  /// False on a rest day (BR-PLAN-01): no new words, no backlog growth.
  final bool isStudyDay;

  /// BR-PLAN-07: the pause flag is on and the backlog is not empty, so no new
  /// words were planned today. Revisions carried on.
  final bool newPaused;

  /// The two word blocks, in BR-PLAN-02 order: Revise then New today.
  ///
  /// Only the word blocks. `PlanKind` is `plan_items.kind`, which has no value
  /// for grammar or for sentences, so this cannot name the other two blocks
  /// BR-PLAN-02 lists — [grammarDue] is read directly, and sentences live in
  /// `sentence_log` (#80). Named `wordBlocks` rather than `blocks` so it stops reading as the
  /// whole day: a screen that rendered `blocks` would silently show no
  /// grammar.
  List<(PlanKind, List<String>)> get wordBlocks => <(PlanKind, List<String>)>[
    (PlanKind.revise, revise),
    (PlanKind.newWord, newToday),
  ];
}

/// The plan engine.
class PlanEngine {
  PlanEngine({
    required PlanStore store,
    required int reviseCount,
    required int backlogCatchupDays,
    bool autoAdvance = true,
    bool pauseNewWhenBacklog = false,
    int docDailyCap = 0,
    Fsrs? fsrs,
  }) : this._(
         store,
         reviseCount,
         backlogCatchupDays,
         autoAdvance,
         pauseNewWhenBacklog,
         docDailyCap,
         fsrs ?? Fsrs(),
       );

  PlanEngine._(
    this._store,
    this._reviseCount,
    this._backlogCatchupDays,
    this._autoAdvance,
    this._pauseNewWhenBacklog,
    this._docDailyCap,
    this._fsrs,
  );

  final PlanStore _store;

  /// BR-PLAN-02, default 10.
  final int _reviseCount;

  /// BR-PLAN-05, default 30. How far back a returning learner's missed days
  /// are generated — beyond it the days are simply gone, which is the point:
  /// coming back after six months should not produce a thousand-word backlog.
  final int _backlogCatchupDays;

  /// BR-COURSE-05, default on.
  final bool _autoAdvance;

  /// BR-PLAN-07, default off. Today offers it when the backlog passes three
  /// times `daily_new`.
  final bool _pauseNewWhenBacklog;

  /// BR-PLAN-11, `doc_daily_cap`: the words a study day takes from the
  /// document queue, after the course's and outside `daily_new`. 0 holds
  /// them all in the queue.
  final int _docDailyCap;

  final Fsrs _fsrs;

  /// BR-PLAN-09's timings per plan date (#708). They measure only the days
  /// before it, so they cannot change during it: Today's rebuild after every
  /// rating, resume and widget refresh reads them once a day, not each time.
  /// An import rebuilds the engine, and with it this.
  // ponytail: one entry per day Today has estimated (not the preview, #817);
  // an engine alive for weeks keeps a few dozen, which is nothing.
  final Map<PlanDate, Future<MeasuredSeconds>> _measured =
      <PlanDate, Future<MeasuredSeconds>>{};

  /// BR-COURSE-05 with auto-advance off: Today's *Start next step*.
  ///
  /// Enrolls the step after the last finished one, at the learner's current
  /// pace, and plans an open today again at once, so its first new words are
  /// today's rather than tomorrow's: a day the last step ran out part-way
  /// through is topped up to the new pace (#687 AN-7). Today stays opened,
  /// so it keeps the revisions it picked (#342). Returns the step, or null
  /// when a step is already active or the course is finished.
  ///
  /// [PlanStore.atomically], as [openDay] is (#548): an opening in between
  /// would see the step without today given back to it.
  Future<String?> startNextStep(
    PlanDate today, {
    required int dailyNew,
    required int studyDaysMask,
  }) => _store.atomically(() async {
    if (await _store.activeStep() != null) return null;
    final next = await _nextStepAfterFinishing(true);
    if (next == null) return null;

    await _store.enroll(
      ActiveStep(
        sublevelCode: next,
        startedOn: today,
        dailyNew: dailyNew,
        studyDaysMask: studyDaysMask,
      ),
    );
    final last = await _store.lastPlannedDate();
    if (last != null && daysBetween(today, last) >= 0) {
      await _store.setLastPlannedDate(addDays(today, -1));
      await generateNewThrough(today);
    }
    return next;
  });

  /// FR-L2-03's *Start*: [code] becomes the active step (BR-COURSE-04). The
  /// current enrollment, if any, completes [today] and [code]'s opens with
  /// [dailyNew] and [studyDaysMask].
  ///
  /// Today's plan is left as it is (BR-PLAN-08): unlike [startNextStep],
  /// the last planned date does not move back, so the new step's words start
  /// tomorrow.
  ///
  /// Atomic (#548): an opening between the two writes would find no step.
  Future<void> switchStep(
    String code,
    PlanDate today, {
    required int dailyNew,
    required int studyDaysMask,
  }) => _store.atomically(() async {
    final current = await _store.activeStep();
    if (current?.sublevelCode == code) return;
    if (current != null) {
      await _store.completeStep(current.sublevelCode, today);
    }
    await _store.enroll(
      ActiveStep(
        sublevelCode: code,
        startedOn: today,
        dailyNew: dailyNew,
        studyDaysMask: studyDaysMask,
      ),
    );
  });

  /// [openDay] for [date], writing nothing: the plan it would open, for
  /// Today's Tomorrow card and T6 (FR-T6-02).
  ///
  /// The same engine over a [DryRunPlanStore], so the preview is what opening
  /// the day will actually do rather than a second guess at it.
  Future<DailyPlan> previewDay(PlanDate date) => PlanEngine._(
    DryRunPlanStore(_store),
    _reviseCount,
    _backlogCatchupDays,
    _autoAdvance,
    _pauseNewWhenBacklog,
    _docDailyCap,
    _fsrs,
  ).openDay(date);

  /// Opens [date] and returns its plan. Idempotent (BR-PLAN-04).
  ///
  /// The order is the doc's: fill in the missed days first, then pick today's
  /// revisions, then read back what is planned. Picking revisions before
  /// generating would let a word planned as new today also be picked to
  /// revise, which is what BR-PLAN-03's exclusion is for.
  Future<DailyPlan> openDay(PlanDate date) async {
    // Deciding and writing as one (#548): a second opening waits, then finds
    // the day planned and adds nothing.
    await _store.atomically(() async {
      // A day opened before keeps its revisions, even none (BR-PLAN-08): a
      // revise_count raised mid-day waits for tomorrow (#342).
      final last = await _store.lastPlannedDate();
      final reopened = last != null && last.compareTo(date) >= 0;
      await generateNewThrough(date);
      if (!reopened) await ensureRevise(date);
    });

    final step = await _store.activeStep();
    final backlog = await _store.backlogBefore(date);

    // No active step is two different things. Before onboarding it means the
    // learner has not started; after a step runs out with auto-advance off it
    // means Today shows "Step complete" and offers the next one.
    final finished = step == null && await _store.hasEverEnrolled();

    return DailyPlan(
      date: date,
      revise: await _store.plannedOn(date, PlanKind.revise),
      newToday: await _store.plannedOn(date, PlanKind.newWord),
      grammarDue: await _store.grammarOfDay(date),
      backlog: backlog,
      activeStep: step?.sublevelCode,
      nextStep: await _nextStepAfterFinishing(finished),
      stepComplete: finished,
      isStudyDay: await studyDayOn(date),
      newPaused: _pauseNewWhenBacklog && backlog.isNotEmpty,
    );
  }

  /// The step to offer as *Start next step*, or null when there is none.
  ///
  /// Nullable all the way through rather than an empty-string sentinel: when
  /// [finished] is true every enrollment row is closed, so `lastCompletedStep`
  /// has one to return, and a fallback would be an unreachable branch dressed
  /// up as a handled case.
  Future<String?> _nextStepAfterFinishing(bool finished) async {
    if (!finished) return null;

    final last = await _store.lastCompletedStep();
    return last == null ? null : _store.stepAfter(last);
  }

  /// Plans new words for every study day from where planning left off through
  /// [today] (BR-PLAN-05).
  ///
  /// Walks day by day rather than planning a batch against today, because a
  /// word has to carry the date it was *meant* for: that date is what makes it
  /// backlog rather than part of today, and what the backlog list groups by.
  Future<void> generateNewThrough(PlanDate today) async {
    var step = await _store.activeStep();
    if (step == null) {
      // No new words to plan, but a day after the course (or after a step
      // with auto-advance off) is still opened once: recorded, so reopening
      // it keeps the Revise block it picked (BR-PLAN-08, #457). With no step
      // it is planned as a study day, as `streak` counts it: the finished
      // step's mask would make Today call it a rest day. Not before
      // onboarding, where a step enrolled today must still plan today.
      if (await _store.hasEverEnrolled()) {
        await _recordPlanned(today, mask: allDays);
      }
      return;
    }

    // BR-PLAN-01 (#606, the owner's call): the setup day, the day the first
    // step starts with nothing planned yet, is a study day whatever the
    // mask. FR-S2-03 opens Today with the first day planned, and the mask
    // applies from tomorrow.
    final setupDay =
        step.startedOn == today && await _store.lastPlannedDate() == null;
    final days = await _daysToPlan(today, step);
    // BR-PLAN-08: [today] is being planned now, with this mask, and keeps it
    // for the rest of the day. The pace carries over when a step advances,
    // so the mask is the same after one.
    if (days.isNotEmpty) {
      await _store.setPlannedMask(setupDay ? allDays : step.studyDaysMask);
    }
    for (final day in days) {
      // Re-read each turn: `_planDay` may have advanced the step, and the new
      // one carries its own mask.
      final current = step;
      if (current == null) break;

      if (!isStudyDay(day, setupDay ? allDays : current.studyDaysMask)) {
        continue;
      }

      // BR-PLAN-07. Checked per day, not once: planning a day creates the
      // rows that are backlog for the day after, so a learner who is already
      // behind stays paused for the whole catch-up rather than digging deeper.
      if (await _isPaused(day)) continue;

      // Already planned — reopening the same day must not double it. A day
      // the last step ran out part-way through is topped up (AN-7).
      final planned = await _coursePlannedOn(day);
      if (planned >= current.dailyNew) continue;

      step = await _planDay(day, current, planned: planned);
      if (step == null) break; // the course ran out, or auto-advance is off
    }

    // BR-PLAN-11: today's words from documents, after the course's. Today
    // only: a missed day's would be backlog, which the queue's words never
    // are; they wait in the queue instead.
    if (days.contains(today) &&
        isStudyDay(
          today,
          setupDay ? allDays : step?.studyDaysMask ?? allDays,
        ) &&
        !await _isPaused(today)) {
      await _topUpDocWords(today);
    }

    await _recordPlanned(today);
  }

  /// [day]'s new words from the course: its `new` rows less the ones the
  /// document queue gave it (BR-PLAN-11: outside `daily_new`).
  Future<int> _coursePlannedOn(PlanDate day) async =>
      (await _store.plannedOn(day, PlanKind.newWord)).length -
      (await _store.docPlannedOn(day)).length;

  /// BR-PLAN-11: [day] takes the document queue's oldest waiting words, up
  /// to [_docDailyCap] less the ones it has already.
  Future<void> _topUpDocWords(PlanDate day) async {
    final room = _docDailyCap - (await _store.docPlannedOn(day)).length;
    if (room <= 0) return;
    final picked = await _store.docWaiting(limit: room);
    if (picked.isEmpty) return;
    await _store.addToPlan(day, PlanKind.newWord, picked);
    await _store.markDocPlanned(day, picked);
  }

  /// FR-D2-02/03 (BR-DOC-04, BR-PLAN-11): [uids] join the document queue,
  /// and an opened study day [today] with room takes them at once. Returns
  /// each one's first day: [today] when it's in today's plan, the study day
  /// the queue reaches it on, or null with a cap of 0. A word already planned
  /// by another route, or no longer To-do, is left out of the answer.
  Future<Map<String, PlanDate?>> addDocWords(
    List<String> uids,
    PlanDate today, {
    required String at,
  }) => _store.atomically(() async {
    await _store.queueDocWords(uids, at);
    final step = await _store.activeStep();
    final mask = await _store.plannedMask() ?? step?.studyDaysMask ?? allDays;
    final open =
        step != null &&
        await _store.lastPlannedDate() == today &&
        isStudyDay(today, mask) &&
        !await _isPaused(today);
    if (open) await _topUpDocWords(today);

    final todays = (await _store.docPlannedOn(today)).toSet();
    final waiting = await _store.docWaiting(limit: 1 << 20);
    final wanted = uids.toSet();
    final days = step?.studyDaysMask ?? allDays;
    // A day not opened yet takes its share when it opens.
    final roomToday =
        !open &&
            await _store.lastPlannedDate() != today &&
            isStudyDay(today, days) &&
            !await _isPaused(today)
        ? _docDailyCap - todays.length
        : 0;
    final starts = <String, PlanDate?>{
      for (final uid in uids)
        if (todays.contains(uid)) uid: today,
    };
    for (final (position, uid) in waiting.indexed) {
      if (!wanted.contains(uid)) continue;
      if (_docDailyCap <= 0) {
        starts[uid] = null;
      } else if (position < roomToday) {
        starts[uid] = today;
      } else {
        starts[uid] = _nthStudyDay(
          today,
          (position - roomToday) ~/ _docDailyCap + 1,
          days,
        );
      }
    }
    return starts;
  });

  /// The [n]th study day after [from] under [mask] (n ≥ 1).
  PlanDate _nthStudyDay(PlanDate from, int n, int mask) {
    var day = from;
    var left = n;
    // A mask always has a study day (BR-PLAN-01), so this ends; bounded
    // anyway, a week per step.
    for (var guard = 0; guard < 7 * n + 7 && left > 0; guard++) {
      day = addDays(day, 1);
      if (isStudyDay(day, mask)) left--;
    }
    return day;
  }

  /// Records [today] as planned. Never backwards (#346): a clock or time zone
  /// that moves back reopens a past day as it was; recording it as the last
  /// one planned would plan the days after it again, and give a finished one
  /// a Revise block.
  ///
  /// [mask], when given, is what the day is planned with (BR-PLAN-08), written
  /// only with the date: a day a step ran out on keeps the mask it had.
  Future<void> _recordPlanned(PlanDate today, {int? mask}) async {
    final last = await _store.lastPlannedDate();
    if (last == null || last.compareTo(today) < 0) {
      if (mask != null) await _store.setPlannedMask(mask);
      await _store.setLastPlannedDate(today);
    }
  }

  /// Plans one study day, advancing the step if it runs out (BR-COURSE-05).
  ///
  /// Returns the step to carry into the next day, or null when there is none
  /// left to plan from. [planned] are the new words [day] has already.
  Future<ActiveStep?> _planDay(
    PlanDate day,
    ActiveStep step, {
    int planned = 0,
  }) async {
    var current = step;
    var need = current.dailyNew - planned;

    // Bounded. Each turn either fills the day or advances a step, and the
    // course is finite, so this terminates — but a content file with a run of
    // empty steps would otherwise spin, and an unbounded loop in a day-opening
    // path is not something to find out about from a frozen phone.
    for (var guard = 0; guard < 100 && need > 0; guard++) {
      final picked = await _store.unplannedWords(
        current.sublevelCode,
        limit: need,
      );

      if (picked.isNotEmpty) {
        await _store.addToPlan(day, PlanKind.newWord, picked);
        need -= picked.length;
        if (need <= 0) return current;
      }

      // The step is exhausted: close it, and take the next if we may.
      await _store.completeStep(current.sublevelCode, day);

      final next = await _store.stepAfter(current.sublevelCode);
      if (!_autoAdvance || next == null) return null;

      // The pace carries over. BR-PLAN-08 freezes it per enrollment, and
      // advancing is not the learner changing their mind about it.
      current = ActiveStep(
        sublevelCode: next,
        startedOn: day,
        dailyNew: current.dailyNew,
        studyDaysMask: current.studyDaysMask,
      );
      await _store.enroll(current);
    }

    // Falling out of the loop with words still to place means the guard
    // tripped, which cannot happen: every turn either fills the day or
    // advances a step, and the course is finite. Asserting it is the
    // difference between a bug and a learner quietly getting a short day.
    assert(need <= 0, 'gave up planning $day with $need words still to place');
    return current;
  }

  /// BR-PLAN-07: new words are paused while the backlog is not empty.
  Future<bool> _isPaused(PlanDate day) async =>
      _pauseNewWhenBacklog && (await _store.backlogBefore(day)).isNotEmpty;

  /// The days `generateNewThrough` should walk, oldest first.
  ///
  /// Starts the day after planning last reached, or at enrollment on a fresh
  /// install, and never earlier than `backlog_catchup_days` before [today].
  Future<List<PlanDate>> _daysToPlan(
    PlanDate today,
    ActiveStep enrollment,
  ) async {
    final last = await _store.lastPlannedDate();
    var from = last == null ? enrollment.startedOn : addDays(last, 1);

    final earliest = addDays(today, -_backlogCatchupDays);
    if (daysBetween(earliest, from) < 0) from = earliest;

    // ActiveStep is a floor whatever the catch-up window says: there was no
    // course to plan before the learner started one.
    if (daysBetween(enrollment.startedOn, from) < 0) {
      from = enrollment.startedOn;
    }

    final span = daysBetween(from, today);
    return <PlanDate>[for (var i = 0; i <= span; i++) addDays(from, i)];
  }

  /// Picks [_reviseCount] words to revise on [date], once (BR-PLAN-03).
  ///
  /// Due first by earliest due, then filled with the lowest-retrievability
  /// learned words. Today's new words are excluded — meeting a word for the
  /// first time and revising it in the same session is not revision.
  Future<void> ensureRevise(PlanDate date) async {
    if (_reviseCount <= 0) return;

    // Idempotent: a day already picked keeps what it picked, even if the
    // schedule has moved on since.
    if ((await _store.plannedOn(date, PlanKind.revise)).isNotEmpty) return;

    await _topUpRevise(date);
  }

  /// Picks revisions for [date] up to [_reviseCount], leaving out the words
  /// [date] already holds, new or to revise.
  Future<void> _topUpRevise(PlanDate date) async {
    final have = await _store.plannedOn(date, PlanKind.revise);
    final limit = _reviseCount - have.length;
    if (limit <= 0) return;

    final excluded = <String>{
      ...have,
      ...await _store.plannedOn(date, PlanKind.newWord),
    };
    final candidates = <RevisionCandidate>[
      for (final c in await _store.revisionCandidates())
        if (!excluded.contains(c.uid)) c,
    ];

    final picked = selectRevisions(
      candidates,
      on: date,
      limit: limit,
      fsrs: _fsrs,
    );
    if (picked.isEmpty) return;

    await _store.addToPlan(date, PlanKind.revise, picked);
  }

  /// After an *Import and merge* (#622, #937): [today] planned again from
  /// the merged data. The import has dropped the open new rows of words the
  /// file has a schedule for, and today's open revisions. This tops the new
  /// words up to the pace, under the mask today was planned with
  /// (BR-PLAN-08, the setup day's included), and the revisions up to
  /// `revise_count` from the merged schedule, leaving out what today holds.
  /// What was done today stays. A day not opened yet is [openDay]'s.
  Future<void> replanToday(PlanDate today) => _store.atomically(() async {
    if (await _store.lastPlannedDate() != today) return;

    final step = await _store.activeStep();
    final mask = await _store.plannedMask() ?? step?.studyDaysMask ?? allDays;
    if (step != null && isStudyDay(today, mask) && !await _isPaused(today)) {
      final planned = await _coursePlannedOn(today);
      if (planned < step.dailyNew) {
        await _planDay(today, step, planned: planned);
      }
      await _topUpDocWords(today);
    }
    if (_reviseCount > 0) await _topUpRevise(today);
  });

  /// How many days in a row the learner has kept going, each past day judged
  /// by [_studyDayThen] (BR-PLAN-01, -08).
  Future<int> streak(PlanDate today) async => streakLength(
    today: today,
    activeDays: await _store.activeDays(today, lookbackDays: streakLookback),
    isStudyDay: await _studyDayThen(),
    maxLookback: streakLookback,
  );

  /// FR-M2-02: the longest streak so far, rest days as [streak] counts them.
  Future<int> bestStreak(PlanDate today) async => longestStreak(
    activeDays: await _store.activeDays(today, lookbackDays: 36500),
    isStudyDay: await _studyDayThen(),
    today: today,
  );

  /// Whether a past day was a study day, by the mask in force on it (#377):
  /// turning a rest day on never breaks a streak already earned.
  ///
  /// The open step's mask; with none open (#615), the last closed step's up
  /// to the day it closed, so finishing a step or the course leaves the
  /// streak as it was, and every day after it, as those days are planned
  /// (#457). Before any step, every day.
  Future<bool Function(PlanDate)> _studyDayThen() async {
    final history = await _store.studyDaysHistory();
    final step = await _store.activeStep();
    final closed = step == null ? await _store.lastCompletedMask() : null;

    return (PlanDate day) => isStudyDay(
      day,
      step != null
          ? maskOn(day, history, step.studyDaysMask)
          : closed != null && day.compareTo(closed.on) <= 0
          ? maskOn(day, history, closed.mask)
          : allDays,
    );
  }

  /// "Am I on schedule?" — planned against introduced.
  ///
  /// [fallbackDailyNew] is the pace to divide by when there is no open
  /// enrolment, which is the state a finished step leaves behind when
  /// auto-advance is off. The caller passes the `daily_new` setting.
  Future<ScheduleStatus> scheduleCheck(
    PlanDate today, {
    int fallbackDailyNew = 1,
  }) async {
    final (planned, introduced) = await _store.newItemProgress(today);
    final step = await _store.activeStep();

    return ScheduleStatus(
      planned: planned,
      introduced: introduced,
      // The enrolment's pace, not the setting: BR-PLAN-08 freezes it, and
      // those days were planned at whatever it was then.
      //
      // [fallbackDailyNew] covers the gap between steps, where there is no
      // enrolment to read a pace from. Zero there would report "0 days behind"
      // beside a non-zero backlog and "not on schedule" — three numbers that
      // contradict each other on the same screen.
      dailyNew: step?.dailyNew ?? fallbackDailyNew,
    );
  }

  /// BR-PLAN-09: how long [plan] should take.
  ///
  /// The learner's own medians once there are seven sessions, the published
  /// defaults before that — and the defaults stay for anything that could not
  /// be measured, which is what [MeasuredSeconds] leaves null.
  ///
  /// [remember] false reads afresh and keeps nothing (#817): tomorrow's
  /// preview is drawn while today can still be studied, and a read kept
  /// under tomorrow's date would miss the evening once tomorrow comes, the
  /// engine outliving midnight.
  Future<Duration> estimate(
    DailyPlan plan, {
    int sentences = 0,
    bool remember = true,
  }) async {
    final pending = remember
        ? _measured[plan.date] ??= _store.measuredSeconds(plan.date)
        : _store.measuredSeconds(plan.date);
    final MeasuredSeconds measured;
    try {
      measured = await pending;
    } catch (_) {
      // A failed read is not remembered: the next rebuild asks again. The
      // removed future is the one that just failed, rethrown below.
      if (remember) _measured.remove(plan.date)?.ignore();
      rethrow;
    }

    return timeEstimate(
      revisions: plan.revise.length,
      newWords: plan.newToday.length,
      grammar: plan.grammarDue.length,
      sentences: sentences,
      seconds: measured.enough
          ? ItemSeconds.defaults.withMeasured(
              revision: measured.revision,
              newWord: measured.newWord,
              grammar: measured.grammar,
            )
          : ItemSeconds.defaults,
    );
  }

  /// BR-PLAN-10, computed rather than stored.
  Future<bool> isDayComplete(DailyPlan plan, {int openSentences = 0}) async =>
      dayComplete(
        openPlanItems: await _store.openPlanItems(plan.date),
        grammarDue: plan.grammarDue.length,
        openSentences: openSentences,
        isStudyDay: plan.isStudyDay,
      );

  /// How far back the streak looks. A year and a bit: beyond that the number
  /// is a curiosity, and the scan is not free.
  static const int streakLookback = 400;

  /// BR-PLAN-01: whether [date] is a study day. BR-PLAN-08: the day planned
  /// last is what it was planned as, and M5's new study days are tomorrow's.
  /// Today's plan and T3's next step (#328) both ask here.
  Future<bool> studyDayOn(PlanDate date) async {
    final planned = date == await _store.lastPlannedDate()
        ? await _store.plannedMask()
        : null;
    final step = await _store.activeStep();
    return isStudyDay(date, planned ?? step?.studyDaysMask ?? allDays);
  }

  /// BR-PLAN-01: whether [date] is a study day under [mask].
  ///
  /// The mask is seven bits, Monday at bit 0 — `DateTime.monday` is 1, so the
  /// shift is one less. 127 is all seven, which is the default.
  bool isStudyDay(PlanDate date, int mask) =>
      mask & (1 << (parsePlanDate(date).weekday - 1)) != 0;

  /// Every day of the week enabled.
  static const int allDays = 127;
}

/// BR-PLAN-03's selection, as a pure function so it can be tested on lists.
///
/// Due cards first, earliest due first; then the remaining slots filled with
/// the lowest-retrievability words. Never more than [limit] — "excess due
/// cards wait", which is the rule that keeps a returning learner from being
/// handed two hundred cards.
List<String> selectRevisions(
  List<RevisionCandidate> candidates, {
  required PlanDate on,
  required int limit,
  required Fsrs fsrs,
}) {
  if (limit <= 0) return const <String>[];

  final due = <RevisionCandidate>[];
  final rest = <RevisionCandidate>[];

  for (final candidate in candidates) {
    final dueOn = candidate.due;
    if (dueOn != null && daysBetween(dueOn, on) >= 0) {
      due.add(candidate);
    } else {
      rest.add(candidate);
    }
  }

  // Earliest due first: the card that has been waiting longest is the one the
  // learner is most likely to have lost.
  due.sort((a, b) {
    final byDue = a.due!.compareTo(b.due!);
    return byDue != 0 ? byDue : a.uid.compareTo(b.uid);
  });

  if (due.length >= limit) {
    return <String>[for (final c in due.take(limit)) c.uid];
  }

  // Lowest retrievability first. Computed rather than approximated by
  // `elapsed / stability`, so the fill order and the scheduler agree on what
  // "most likely to be forgotten" means. Once per candidate, not per
  // comparison (#687 AN-13).
  final ranked = <(String, double)>[
    for (final c in rest)
      (c.uid, fsrs.retrievability(daysBetween(c.lastReview, on), c.stability)),
  ];
  ranked.sort((a, b) {
    final byRecall = a.$2.compareTo(b.$2);
    return byRecall != 0 ? byRecall : a.$1.compareTo(b.$1);
  });

  return <String>[
    for (final c in due) c.uid,
    for (final (uid, _) in ranked.take(limit - due.length)) uid,
  ];
}

/// A study-days mask and the first day it was in force (#377). The first
/// span's day is empty: it was in force before any change.
typedef MaskSpan = ({PlanDate from, int mask});

/// The mask in force on [day]: the latest of [history] from on or before
/// it. [fallback], the enrolment's own, with no history (every install until
/// the study days first change) and from the last change on, so a stale
/// history (a merged backup's) never overrules it.
int maskOn(PlanDate day, List<MaskSpan> history, int fallback) {
  if (history.isEmpty || day.compareTo(history.last.from) >= 0) {
    return fallback;
  }
  var mask = history.first.mask;
  for (final span in history) {
    if (span.from.compareTo(day) > 0) break;
    mask = span.mask;
  }
  return mask;
}

/// `study_days_history` as stored: a JSON list of `{from, mask}`, oldest
/// first. Anything else (a backup can bring any text) is no history.
List<MaskSpan> decodeMaskHistory(String? json) {
  if (json == null || json.isEmpty) return <MaskSpan>[];
  try {
    if (jsonDecode(json) case final List<Object?> spans) {
      return <MaskSpan>[
        for (final span in spans)
          if (span case {'from': final String from, 'mask': final int mask})
            (from: from, mask: mask),
      ]..sort((a, b) => a.from.compareTo(b.from));
    }
  } on FormatException {
    // Below.
  }
  return <MaskSpan>[];
}

String encodeMaskHistory(List<MaskSpan> history) => jsonEncode(<Object>[
  for (final span in history)
    <String, Object>{'from': span.from, 'mask': span.mask},
]);

/// [history] with [mask] in force from [from] (BR-PLAN-08: the day after
/// the change). The first change also keeps [previous], the mask before it,
/// as the one in force until then.
List<MaskSpan> withMask(
  List<MaskSpan> history, {
  required int previous,
  required int mask,
  required PlanDate from,
}) => <MaskSpan>[
  if (history.isEmpty) (from: '', mask: previous),
  for (final span in history)
    if (span.from.compareTo(from) < 0) span,
  (from: from, mask: mask),
];
