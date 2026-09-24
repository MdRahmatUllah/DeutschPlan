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

import 'package:deutschplan/domain/dry_run_plan_store.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_stats.dart';

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
  /// The open enrollment, or null before the learner has started a step.
  Future<ActiveStep?> activeStep();

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

  /// Adds plan rows. Rows already present are left alone — that is what makes
  /// reopening a day idempotent (BR-PLAN-04).
  Future<void> addToPlan(PlanDate date, PlanKind kind, List<String> uids);

  /// Open `new` rows from before [today], newest day first (BR-PLAN-05).
  Future<List<String>> backlogBefore(PlanDate today);

  /// The last date `generateNewThrough` ran to, or null on a fresh install.
  Future<PlanDate?> lastPlannedDate();
  Future<void> setLastPlannedDate(PlanDate date);

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

  /// The days on or before [today] that have any activity recorded, for the
  /// streak. Bounded by [lookbackDays] so it is one small query, not a scan.
  Future<Set<PlanDate>> activeDays(PlanDate today, {required int lookbackDays});

  /// New items planned on or before [today], and how many are done — the two
  /// halves of the schedule check.
  Future<(int planned, int introduced)> newItemProgress(PlanDate today);

  /// How many plan rows of [date] are neither completed nor skipped.
  Future<int> openPlanItems(PlanDate date);

  /// The learner's own median seconds per item, or null where there is not
  /// enough history to measure one (BR-PLAN-09).
  Future<MeasuredSeconds> measuredSeconds();
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

  /// Days with any activity. BR-PLAN-09 wants seven before it trusts these.
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
    Fsrs? fsrs,
  }) : this._(
         store,
         reviseCount,
         backlogCatchupDays,
         autoAdvance,
         pauseNewWhenBacklog,
         fsrs ?? Fsrs(),
       );

  PlanEngine._(
    this._store,
    this._reviseCount,
    this._backlogCatchupDays,
    this._autoAdvance,
    this._pauseNewWhenBacklog,
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

  final Fsrs _fsrs;

  /// BR-COURSE-05 with auto-advance off: Today's *Start next step*.
  ///
  /// Enrolls the step after the last finished one, at the learner's current
  /// pace, and lets planning reach today again so its first new words are
  /// today's rather than tomorrow's. Returns the step, or null when a step is
  /// already active or the course is finished.
  Future<String?> startNextStep(
    PlanDate today, {
    required int dailyNew,
    required int studyDaysMask,
  }) async {
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
    }
    return next;
  }

  /// FR-L2-03's *Start*: [code] becomes the active step (BR-COURSE-04). The
  /// current enrollment, if any, completes [today] and [code]'s opens with
  /// [dailyNew] and [studyDaysMask].
  ///
  /// Today's plan is left as it is (BR-PLAN-08): unlike [startNextStep],
  /// the last planned date does not move back, so the new step's words start
  /// tomorrow.
  Future<void> switchStep(
    String code,
    PlanDate today, {
    required int dailyNew,
    required int studyDaysMask,
  }) async {
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
  }

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
    _fsrs,
  ).openDay(date);

  /// Opens [date] and returns its plan. Idempotent (BR-PLAN-04).
  ///
  /// The order is the doc's: fill in the missed days first, then pick today's
  /// revisions, then read back what is planned. Picking revisions before
  /// generating would let a word planned as new today also be picked to
  /// revise, which is what BR-PLAN-03's exclusion is for.
  Future<DailyPlan> openDay(PlanDate date) async {
    await generateNewThrough(date);
    await ensureRevise(date);

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
      grammarDue: await _store.grammarDueOn(date),
      backlog: backlog,
      activeStep: step?.sublevelCode,
      nextStep: await _nextStepAfterFinishing(finished),
      stepComplete: finished,
      isStudyDay: isStudyDay(date, step?.studyDaysMask ?? allDays),
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
    if (step == null) return;

    for (final day in await _daysToPlan(today, step)) {
      // Re-read each turn: `_planDay` may have advanced the step, and the new
      // one carries its own mask.
      final current = step;
      if (current == null) break;

      if (!isStudyDay(day, current.studyDaysMask)) continue;

      // BR-PLAN-07. Checked per day, not once: planning a day creates the
      // rows that are backlog for the day after, so a learner who is already
      // behind stays paused for the whole catch-up rather than digging deeper.
      if (await _isPaused(day)) continue;

      // Already planned — reopening the same day must not double it.
      if ((await _store.plannedOn(day, PlanKind.newWord)).isNotEmpty) continue;

      step = await _planDay(day, current);
      if (step == null) break; // the course ran out, or auto-advance is off
    }

    await _store.setLastPlannedDate(today);
  }

  /// Plans one study day, advancing the step if it runs out (BR-COURSE-05).
  ///
  /// Returns the step to carry into the next day, or null when there is none
  /// left to plan from.
  Future<ActiveStep?> _planDay(PlanDate day, ActiveStep step) async {
    var current = step;
    var need = current.dailyNew;

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

    final excluded = (await _store.plannedOn(date, PlanKind.newWord)).toSet();
    final candidates = <RevisionCandidate>[
      for (final c in await _store.revisionCandidates())
        if (!excluded.contains(c.uid)) c,
    ];

    final picked = selectRevisions(
      candidates,
      on: date,
      limit: _reviseCount,
      fsrs: _fsrs,
    );
    if (picked.isEmpty) return;

    await _store.addToPlan(date, PlanKind.revise, picked);
  }

  /// How many days in a row the learner has kept going.
  ///
  /// Reads the mask from the active step, falling back to every day when there
  /// is none — a learner between steps still has a streak.
  Future<int> streak(PlanDate today) async {
    final step = await _store.activeStep();
    final mask = step?.studyDaysMask ?? allDays;

    return streakLength(
      today: today,
      activeDays: await _store.activeDays(today, lookbackDays: streakLookback),
      isStudyDay: (day) => isStudyDay(day, mask),
      maxLookback: streakLookback,
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
  Future<Duration> estimate(DailyPlan plan, {int sentences = 0}) async {
    final measured = await _store.measuredSeconds();

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
  // "most likely to be forgotten" means.
  double recall(RevisionCandidate c) =>
      fsrs.retrievability(daysBetween(c.lastReview, on), c.stability);

  rest.sort((a, b) {
    final byRecall = recall(a).compareTo(recall(b));
    return byRecall != 0 ? byRecall : a.uid.compareTo(b.uid);
  });

  return <String>[
    for (final c in due) c.uid,
    for (final c in rest.take(limit - due.length)) c.uid,
  ];
}
