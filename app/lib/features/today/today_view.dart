import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:deutschplan/domain/plan_engine.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// How far one block of today's plan has got.
@immutable
class BlockProgress {
  const BlockProgress({required this.done, required this.total});

  static const BlockProgress none = BlockProgress(done: 0, total: 0);

  final int done;
  final int total;

  int get open => total - done;

  /// Something was planned and all of it is done: the card's ink check.
  bool get finished => total > 0 && done >= total;
}

/// The grammar-this-week card: the active step's next topic.
@immutable
class GrammarPreview {
  const GrammarPreview({
    required this.uid,
    required this.topic,
    required this.rule,
  });

  final String uid;
  final String topic;

  /// The whole rule; the card shows its first line.
  final String rule;
}

/// Tomorrow's plan, from a dry run of `openDay(tomorrow)` (#96).
@immutable
class TomorrowPreview {
  const TomorrowPreview({
    required this.revise,
    required this.newWords,
    required this.grammar,
    required this.estimate,
    this.category,
    this.restDay = false,
  });

  final int revise;
  final int newWords;
  final int grammar;
  final Duration estimate;

  /// The category tomorrow's new words mostly share: "… continues".
  final String? category;

  /// Tomorrow is a rest day (BR-PLAN-01): nothing is scheduled, so the card
  /// says that rather than listing optional revisions as a plan.
  final bool restDay;

  /// Whole minutes, rounded up.
  int get minutes => (estimate.inSeconds / 60).ceil();
}

/// T1's contextual cards (FR-T1-06), in priority order.
enum ContextualKind {
  /// BR-COURSE-05 with auto-advance off: the step ran out, *Start next step*.
  stepComplete,

  /// The last step ran out: revision carries on.
  courseComplete,

  /// BR-CONTENT-03: the course was updated, with its counts.
  contentUpdate,

  /// BR-PLAN-07: the backlog passed three times `daily_new`.
  pauseOffer,

  /// BR-EXAM-01: enough of the step is introduced for its mock exams.
  examsUnlocked,

  /// The on-device voice is not in use yet.
  voice,
}

/// The one contextual card Today shows, and what it needs to say.
@immutable
class ContextualOffer {
  const ContextualOffer(
    this.kind, {
    this.step,
    this.added = 0,
    this.removed = 0,
    this.changed = 0,
    this.version,
    this.backlog = 0,
    this.percent = 0,
  });

  final ContextualKind kind;

  /// The step it is about: the next one to start, or the one whose exams are
  /// unlocked.
  final String? step;

  /// A content update's counts, and its version for `markSeen`.
  final int added;
  final int removed;
  final int changed;
  final String? version;

  final int backlog;

  /// How much of the step is introduced, for the exams card.
  final int percent;

  /// What `dismissed_cards` records for it. Null when it cannot be dismissed
  /// that way: a finished step waits for an answer, and a content update is
  /// marked seen in its own table.
  String? get dismissId => switch (kind) {
    ContextualKind.pauseOffer => 'pause',
    ContextualKind.examsUnlocked => 'exams:$step',
    ContextualKind.voice => 'voice',
    _ => null,
  };

  /// Whether it has a dismiss button at all.
  bool get dismissible =>
      kind != ContextualKind.stepComplete &&
      kind != ContextualKind.courseComplete;
}

/// What the contextual cards are chosen from, gathered by the provider.
@immutable
class ContextualFacts {
  const ContextualFacts({
    this.dismissed = const <String>{},
    this.stepComplete = false,
    this.nextStep,
    this.contentUpdate,
    this.backlog = 0,
    this.dailyNew = 7,
    this.pauseOn = false,
    this.step,
    this.introduced = 0,
    this.stepWords = 0,
    this.examUnlockPercent = 90,
    this.systemVoice = false,
  });

  final Set<String> dismissed;
  final bool stepComplete;
  final String? nextStep;
  final ({String version, int added, int removed, int changed})? contentUpdate;
  final int backlog;
  final int dailyNew;
  final bool pauseOn;
  final String? step;
  final int introduced;
  final int stepWords;
  final int examUnlockPercent;

  /// The on-device voice is not installed, so the platform's is speaking.
  final bool systemVoice;
}

/// `dismissed_cards` as ids. Anything unreadable — a value from another
/// build, a restored backup, a half-written write — counts as nothing
/// dismissed: a list of hidden cards must never be what hides the plan.
Set<String> dismissedIds(String? stored) {
  if (stored == null) return const <String>{};
  try {
    return (jsonDecode(stored) as List<dynamic>).cast<String>().toSet();
  } on Object {
    return const <String>{};
  }
}

/// FR-T1-06: at most one card — the first that applies and was not dismissed,
/// in [ContextualKind]'s order. What must be answered comes first (a finished
/// step), then news (a content update), then offers, most useful first.
ContextualOffer? contextualFor(ContextualFacts facts) {
  ContextualOffer? unlessDismissed(ContextualOffer offer) =>
      facts.dismissed.contains(offer.dismissId) ? null : offer;

  if (facts.stepComplete) {
    return facts.nextStep == null
        ? const ContextualOffer(ContextualKind.courseComplete)
        : ContextualOffer(ContextualKind.stepComplete, step: facts.nextStep);
  }
  final update = facts.contentUpdate;
  if (update != null) {
    return ContextualOffer(
      ContextualKind.contentUpdate,
      version: update.version,
      added: update.added,
      removed: update.removed,
      changed: update.changed,
    );
  }
  final offers = <ContextualOffer>[
    // BR-PLAN-07: "Today offers this when backlog > 3 × daily_new".
    if (!facts.pauseOn && facts.backlog > 3 * facts.dailyNew)
      ContextualOffer(ContextualKind.pauseOffer, backlog: facts.backlog),
    // BR-EXAM-01: "≥ exam_unlock_percent of the step's words are introduced".
    if (facts.step != null &&
        facts.stepWords > 0 &&
        facts.introduced * 100 >= facts.examUnlockPercent * facts.stepWords)
      ContextualOffer(
        ContextualKind.examsUnlocked,
        step: facts.step,
        percent: facts.introduced * 100 ~/ facts.stepWords,
      ),
    if (facts.systemVoice) const ContextualOffer(ContextualKind.voice),
  ];
  for (final offer in offers) {
    final shown = unlessDismissed(offer);
    if (shown != null) return shown;
  }
  return null;
}

/// Everything T1 draws, read once from the plan and the database.
///
/// A plain value, so the screen is a function of it and the goldens and
/// widget tests can hand one in without a database.
@immutable
class TodayView {
  const TodayView({
    required this.date,
    required this.hour,
    required this.revise,
    required this.newToday,
    required this.openRevise,
    required this.openNew,
    required this.grammarDue,
    required this.backlog,
    required this.streak,
    required this.estimate,
    required this.courseDay,
    required this.stepWords,
    this.grammarDone = 0,
    this.sentences = BlockProgress.none,
    this.isStudyDay = true,
    this.minutes = 0,
    this.tomorrow,
    this.dueTomorrow,
    this.contextual,
    this.backlogFrom,
    this.backlogTo,
    this.step,
    this.learnerName,
    this.newCategory,
    this.grammar,
  });

  final PlanDate date;

  /// The local hour, for the greeting.
  final int hour;

  final BlockProgress revise;
  final BlockProgress newToday;

  /// The words a Revise or New session would show: the block's open ones.
  final List<String> openRevise;
  final List<String> openNew;

  /// Topics due today (BR-PLAN-02's third block) and not yet practised.
  final List<String> grammarDue;

  /// Today's topics practised since the day opened.
  final int grammarDone;

  /// Practice sentences (#80): the day's picked ones, and how many are rated.
  final BlockProgress sentences;

  /// False on a rest day (BR-PLAN-01): nothing is scheduled, and revising is
  /// optional.
  final bool isStudyDay;

  /// Minutes studied today, from `daily_stats`.
  final int minutes;

  /// Tomorrow's plan, previewed once today is done; null before that.
  final TomorrowPreview? tomorrow;

  /// On a rest day: the words due by tomorrow, if today's are left alone.
  final int? dueTomorrow;

  /// FR-T1-06's one contextual card, if any applies.
  final ContextualOffer? contextual;

  /// TodayRest: a day off in the study days (BR-PLAN-01).
  bool get isRestDay => !isStudyDay;

  /// TodayRest's "12 → 6": tomorrow's due words after revising today's.
  int get dueTomorrowIfRevised => math.max(0, (dueTomorrow ?? 0) - revise.open);

  /// New words planned on earlier days and still open (BR-PLAN-05), and the
  /// days they were planned for.
  final int backlog;
  final PlanDate? backlogFrom;
  final PlanDate? backlogTo;

  final int streak;

  /// BR-PLAN-09, for what is still open.
  final Duration estimate;

  /// 1 on the day the first step was started.
  final int courseDay;

  /// The active step's words as the mini bar splits them. [total] also
  /// counts suspended words, which the bar leaves out.
  final ({int done, int learning, int todo, int total}) stepWords;

  /// Null between steps (BR-COURSE-05).
  final String? step;

  /// `learner_name`; the greeting leaves it out when empty.
  final String? learnerName;

  /// The category most of today's new words share.
  final String? newCategory;

  final GrammarPreview? grammar;

  /// FR-T1-02's numerator.
  int get completed =>
      revise.done + newToday.done + grammarDone + sentences.done;

  /// FR-T1-02's denominator: revise + new + grammar + sentences.
  int get total =>
      revise.total +
      newToday.total +
      grammarDue.length +
      grammarDone +
      sentences.total;

  int get left => total - completed;

  /// TodayDone: a study day whose plan is all done. A day with nothing
  /// planned — new words paused, nothing due, a finished step — is not "Tag
  /// geschafft": nothing was done on it.
  bool get isDone => isStudyDay && total > 0 && left == 0;

  /// The words studied today: TodayDone's "17 words".
  int get words => revise.total + newToday.total;

  /// "Revision starts tomorrow" rather than "nothing due": nothing can be due
  /// on the first day, and saying so explains the empty card.
  bool get firstDay => courseDay <= 1;

  /// Whole minutes, rounded up, and at least one while anything is open — a
  /// last card is never "≈ 0 min".
  int get estimateMinutes =>
      left == 0 ? 0 : math.max(1, (estimate.inSeconds / 60).ceil());
}

/// What the docked button offers, in FR-T1-03's order.
enum TodayAction {
  /// "Start today · {n} cards" — nothing done yet.
  start,

  /// "Continue · {n} left" — a study block is still open.
  resume,

  /// "Practice sentences · {n}" — the study blocks are done.
  sentences,

  /// "Review backlog · {n}" — only once the day itself is done.
  backlog,

  /// "All done — see you tomorrow": Lime, and disabled.
  done,

  /// "Revise anyway · {n}" — a rest day with revisions due.
  reviseAnyway,
}

/// FR-T1-03's button: what it offers, and the number on it.
@immutable
class TodayViewState {
  const TodayViewState(this.action, [this.count = 0]);

  final TodayAction action;
  final int count;

  bool get enabled => action != TodayAction.done;

  @override
  bool operator ==(Object other) =>
      other is TodayViewState && other.action == action && other.count == count;

  @override
  int get hashCode => Object.hash(action, count);

  @override
  String toString() => 'TodayViewState(${action.name}, $count)';
}

/// FR-T1-03, as a pure function of the day.
///
/// The counts are the ring's: "Continue · 8 left" beside 12 / 20 counts the
/// sentences still to come, as the ring does.
TodayViewState todayViewState(TodayView view) {
  if (!view.isStudyDay) {
    // BR-PLAN-01: nothing is due on a rest day, so an empty one is done.
    return view.revise.open > 0
        ? TodayViewState(TodayAction.reviseAnyway, view.revise.open)
        : const TodayViewState(TodayAction.done);
  }
  final study = view.revise.open + view.newToday.open + view.grammarDue.length;
  if (study > 0) {
    return view.completed == 0
        ? TodayViewState(TodayAction.start, view.total)
        : TodayViewState(TodayAction.resume, view.left);
  }
  if (view.sentences.open > 0) {
    return TodayViewState(TodayAction.sentences, view.sentences.open);
  }
  if (view.backlog > 0) {
    return TodayViewState(TodayAction.backlog, view.backlog);
  }
  return const TodayViewState(TodayAction.done);
}

/// The greeting's three parts of the day.
enum DayPart { morning, day, evening }

DayPart dayPart(int hour) => switch (hour) {
  < 11 => DayPart.morning,
  < 18 => DayPart.day,
  _ => DayPart.evening,
};

/// "Montag, 21. September": German whatever the UI language, because it is
/// part of the German the learner is looking at, like the greeting.
String germanDate(PlanDate date) => _germanDate.format(parsePlanDate(date));

/// Built on first use. The symbols load synchronously from the package's own
/// data — the returned future is already complete — and they have to be there
/// before the formatter is made.
final DateFormat _germanDate = () {
  unawaited(initializeDateFormatting('de'));
  return DateFormat('EEEE, d. MMMM', 'de');
}();
