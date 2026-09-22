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
/// This issue (#76) owns `openDay`, `generateNewThrough` and `ensureRevise`.
/// The backlog query and skip semantics, auto-advance and the pause flag are
/// #77; `rate` and friends are #78; the streak, the schedule check and the
/// time estimate are #79; practice sentences are #80.
library;

import 'package:deutschplan/domain/fsrs.dart';

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

  /// Frozen at enrollment (BR-PLAN-08): a change to the setting takes effect
  /// from the next step, not retroactively across days already planned.
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
  });

  final PlanDate date;

  /// BR-PLAN-02 puts these in order: Revise, then New today, then Grammar due,
  /// then Practice sentences. Sentences join at #80; until then this is the
  /// whole plan and [blocks] says so rather than returning an empty list that
  /// looks like "no sentences today".
  final List<String> revise;
  final List<String> newToday;
  final List<String> grammarDue;

  /// New words planned for an earlier day and still open (BR-PLAN-05).
  final List<String> backlog;

  /// Null before the learner has enrolled, or once the last step is finished.
  final String? activeStep;

  /// False on a rest day (BR-PLAN-01): no new words, no backlog growth.
  final bool isStudyDay;

  /// The two word blocks, in BR-PLAN-02 order: Revise then New today.
  ///
  /// Only the word blocks. `PlanKind` is `plan_items.kind`, which has no value
  /// for grammar or for sentences, so this cannot name the other two blocks
  /// BR-PLAN-02 lists — [grammarDue] is read directly, and sentences arrive at
  /// #80. Named `wordBlocks` rather than `blocks` so it stops reading as the
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
    Fsrs? fsrs,
  }) : this._(store, reviseCount, backlogCatchupDays, fsrs ?? Fsrs());

  PlanEngine._(
    this._store,
    this._reviseCount,
    this._backlogCatchupDays,
    this._fsrs,
  );

  final PlanStore _store;

  /// BR-PLAN-02, default 10.
  final int _reviseCount;

  /// BR-PLAN-05, default 30. How far back a returning learner's missed days
  /// are generated — beyond it the days are simply gone, which is the point:
  /// coming back after six months should not produce a thousand-word backlog.
  final int _backlogCatchupDays;

  final Fsrs _fsrs;

  /// Opens [date] and returns its plan. Idempotent (BR-PLAN-04).
  ///
  /// The order is the doc's: fill in the missed days first, then pick today's
  /// revisions, then read back what is planned. Picking revisions before
  /// generating would let a word planned as new today also be picked to
  /// revise, which is what BR-PLAN-03's exclusion is for.
  Future<DailyPlan> openDay(PlanDate date) async {
    await generateNewThrough(date);
    await ensureRevise(date);

    final enrollment = await _store.activeStep();

    return DailyPlan(
      date: date,
      revise: await _store.plannedOn(date, PlanKind.revise),
      newToday: await _store.plannedOn(date, PlanKind.newWord),
      grammarDue: await _store.grammarDueOn(date),
      backlog: await _store.backlogBefore(date),
      activeStep: enrollment?.sublevelCode,
      isStudyDay: isStudyDay(date, enrollment?.studyDaysMask ?? allDays),
    );
  }

  /// Plans new words for every study day from where planning left off through
  /// [today] (BR-PLAN-05).
  ///
  /// Walks day by day rather than planning a batch against today, because a
  /// word has to carry the date it was *meant* for: that date is what makes it
  /// backlog rather than part of today, and what the backlog list groups by.
  Future<void> generateNewThrough(PlanDate today) async {
    final enrollment = await _store.activeStep();
    if (enrollment == null) return;

    for (final day in await _daysToPlan(today, enrollment)) {
      if (!isStudyDay(day, enrollment.studyDaysMask)) continue;

      // Already planned — reopening the same day must not double it.
      final planned = await _store.plannedOn(day, PlanKind.newWord);
      if (planned.isNotEmpty) continue;

      final picked = await _store.unplannedWords(
        enrollment.sublevelCode,
        limit: enrollment.dailyNew,
      );

      // The step is exhausted. Advancing to the next one is #77 (BR-COURSE-05),
      // so planning stops here rather than silently planning nothing for every
      // remaining day.
      if (picked.isEmpty) break;

      await _store.addToPlan(day, PlanKind.newWord, picked);
    }

    await _store.setLastPlannedDate(today);
  }

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
