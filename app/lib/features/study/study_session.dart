import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show PlanKind, PlanRepository, ReviewSource;
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'study_session.g.dart';

/// One card of a session: a word to revise or learn, or a grammar topic's
/// practice set.
@immutable
class StudyItem {
  const StudyItem(this.kind, this.uid, {this.planDate});

  final SessionBlockKind kind;

  /// A word uid, or a topic uid for [SessionBlockKind.grammar].
  final String uid;

  /// A backlog word's own plan day, which its rating completes: it is not
  /// today's (FR-T4-02).
  final String? planDate;

  @override
  bool operator ==(Object other) =>
      other is StudyItem && other.kind == kind && other.uid == uid;

  @override
  int get hashCode => Object.hash(kind, uid);

  @override
  String toString() => 'StudyItem(${kind.name}, $uid)';
}

/// How a card went. Ratings are FSRS's 1–4; the new-word buttons are their
/// own outcomes (FR-T2-03, FR-T2-04).
enum CardOutcome { again, hard, good, easy, knewIt, skipped }

/// A block of the session as the progress strip draws it.
typedef StudyBlock = ({SessionBlockKind kind, int size, int done});

/// Where a session is: its queue, the card showing, and how each went.
@immutable
class StudySessionState {
  const StudySessionState({
    required this.items,
    this.position = 0,
    this.results = const <int, CardOutcome>{},
    this.revealed = false,
    this.startedAt,
  });

  /// When the session opened, for T3's "20 cards · 12 min".
  final DateTime? startedAt;

  /// BR-PLAN-02's order: Revise, then New, then Grammar.
  final List<StudyItem> items;

  /// The card showing; `items.length` once the session is over.
  final int position;

  /// How each card went, by its place in [items].
  final Map<int, CardOutcome> results;

  /// The current card has been turned over (FR-T2-01). Each card starts face
  /// down, so the rating bar is hidden until then.
  final bool revealed;

  StudyItem? get current => finished ? null : items[position];
  bool get finished => position >= items.length;

  /// The words are done: what is left, if anything, is grammar, which L15
  /// practises on its own screen. T3's summary comes up here.
  bool get wordsDone =>
      current == null || current!.kind == SessionBlockKind.grammar;

  /// The grammar topics still to practise: T3's next step when there are any.
  List<String> get grammarLeft => <String>[
    for (final item in items.skip(position))
      if (item.kind == SessionBlockKind.grammar) item.uid,
  ];
  int get left => items.length - position;

  /// The blocks in play order, with how far each has got.
  List<StudyBlock> get blocks {
    final blocks = <StudyBlock>[];
    for (var i = 0; i < items.length; i++) {
      final kind = items[i].kind;
      final done = i < position ? 1 : 0;
      if (blocks.isEmpty || blocks.last.kind != kind) {
        blocks.add((kind: kind, size: 1, done: done));
      } else {
        final last = blocks.removeLast();
        blocks.add((kind: kind, size: last.size + 1, done: last.done + done));
      }
    }
    return blocks;
  }

  /// The current card's block, and its place in it: "Revise · 4 / 10".
  ({SessionBlockKind kind, int index, int size})? get place {
    final item = current;
    if (item == null) return null;
    var start = position;
    while (start > 0 && items[start - 1].kind == item.kind) {
      start--;
    }
    var end = position;
    while (end + 1 < items.length && items[end + 1].kind == item.kind) {
      end++;
    }
    return (
      kind: item.kind,
      index: position - start + 1,
      size: end - start + 1,
    );
  }

  /// FR-T2-06: the current card opens its block, so the banner plays.
  bool get startsBlock =>
      !finished && (position == 0 || items[position - 1].kind != current!.kind);

  StudySessionState advance(CardOutcome outcome) => StudySessionState(
    items: items,
    startedAt: startedAt,
    position: position + 1,
    results: <int, CardOutcome>{...results, position: outcome},
  );

  /// Back to the card before, forgetting how it went: an *Undo*.
  StudySessionState back() => StudySessionState(
    items: items,
    startedAt: startedAt,
    position: position - 1,
    results: <int, CardOutcome>{...results}..remove(position - 1),
  );

  StudySessionState reveal() => StudySessionState(
    items: items,
    startedAt: startedAt,
    position: position,
    results: results,
    revealed: true,
  );
}

/// T2's session (`docs/04-screens/study-session.md`).
///
/// keepAlive, so backgrounding the app does not lose the place; the screen
/// clears it on close. A crash loses the notifier but not the progress:
/// every rating is written as it happens, and the queue is rebuilt from what
/// is still open, so the session resumes at the card it stopped on.
@Riverpod(keepAlive: true)
class StudySession extends _$StudySession {
  @override
  Future<StudySessionState> build(SessionArgs args) async {
    final now = _shownAt = ref.read(clockProvider)();
    final date = args.planDate;
    // A card rated or skipped since the args were made is not asked again.
    final open = date == null
        ? null
        // The repository over the kept-alive database, not its auto-disposed
        // provider: a kept-alive notifier must not hold one open.
        : await PlanRepository(ref.read(appDatabaseProvider)).stillOpen(date);

    // The backlog words still open, each on the day it was planned for.
    final backlog = <String, String>{};
    if (args.blocks.any((b) => b.kind == SessionBlockKind.backlog)) {
      final today = date ?? planDate(now);
      for (final row in await PlanRepository(
        ref.read(appDatabaseProvider),
      ).backlog(today)) {
        backlog.putIfAbsent(row.wordUid, () => row.planDate);
      }
    }

    bool wanted(SessionBlockKind kind, String uid) => switch (kind) {
      SessionBlockKind.revise =>
        open == null || open.contains((PlanKind.revise.wire, uid)),
      SessionBlockKind.newWords =>
        open == null || open.contains((PlanKind.newWord.wire, uid)),
      SessionBlockKind.grammar => true,
      SessionBlockKind.backlog => backlog.containsKey(uid),
    };

    // BR-PLAN-02: the blocks in their fixed order, whatever order they came.
    final ordered = <SessionBlock>[...args.blocks]
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return StudySessionState(
      startedAt: now,
      items: <StudyItem>[
        for (final block in ordered)
          for (final uid in block.uids)
            if (wanted(block.kind, uid))
              StudyItem(block.kind, uid, planDate: backlog[uid]),
      ],
    );
  }

  /// Built over the kept-alive database and settings rather than read from
  /// the auto-disposed `ratingServiceProvider`: a kept-alive notifier must
  /// not hold one open.
  RatingService get _rating {
    final db = ref.read(appDatabaseProvider);
    final settings = ref.read(settingsProvider);
    return RatingService(
      db,
      settings,
      PlanRepository(db),
      WordRepository(db, settings),
      ref.read(clockProvider),
    );
  }

  /// One write at a time: a double tap must not rate a word twice.
  bool _busy = false;

  /// When the current card came up, for the time a rating records.
  DateTime? _shownAt;

  /// Seconds on the current card, for `daily_stats` and BR-PLAN-09's
  /// estimate. ponytail: capped at five minutes, so a phone left on the
  /// table does not become a 40-minute card; a real idle detector if the
  /// estimate drifts.
  int _secondsOnCard() {
    final shown = _shownAt;
    if (shown == null) return 0;
    final seconds = ref.read(clockProvider)().difference(shown).inSeconds;
    return seconds.clamp(0, 300);
  }

  /// The plan row a write on [item] completes, if any: today's for the
  /// day's words, its own day's for a backlog word, none outside the plan.
  ({String? date, PlanKind? kind}) _row(StudyItem item) => switch (item.kind) {
    SessionBlockKind.backlog => (date: item.planDate, kind: PlanKind.newWord),
    _ when args.planDate == null => (date: null, kind: null),
    SessionBlockKind.newWords => (date: args.planDate, kind: PlanKind.newWord),
    _ => (date: args.planDate, kind: PlanKind.revise),
  };

  /// FR-T2-02: rates the card — one transaction through [RatingService] —
  /// and moves on.
  Future<bool> rate(Rating rating) => _act((item) async {
    final row = _row(item);
    await _rating.rate(
      item.uid,
      rating,
      source: ReviewSource.daily,
      planDate: row.date,
      kind: row.kind,
      seconds: _secondsOnCard(),
    );
    advance(switch (rating) {
      Rating.again => CardOutcome.again,
      Rating.hard => CardOutcome.hard,
      Rating.good => CardOutcome.good,
      Rating.easy => CardOutcome.easy,
    });
  });

  /// Runs [write] on the current card. False when it did not run: no card,
  /// or a write still in flight (a double tap) — nothing to offer an *Undo*
  /// for.
  Future<bool> _act(Future<void> Function(StudyItem item) write) async {
    final item = state.value?.current;
    if (item == null || _busy) return false;
    _busy = true;
    try {
      await write(item);
      return true;
    } finally {
      _busy = false;
    }
  }

  /// FR-T2-04: *I know it* rates the new word Easy (BR-STATUS-04), completes
  /// its plan row and moves on.
  Future<bool> knewIt() => _act((item) async {
    final row = _row(item);
    await _rating.markKnown(item.uid, planDate: row.date, kind: row.kind);
    advance(CardOutcome.knewIt);
  });

  /// FR-T2-03: *Skip → backlog* leaves the row open and skipped
  /// (BR-PLAN-06), so it waits in tomorrow's backlog, and moves on.
  Future<bool> skip() => _act((item) async {
    final date = _row(item).date;
    if (date != null) {
      await PlanRepository(ref.read(appDatabaseProvider))
          .skip(planDate: date, uid: item.uid, kind: PlanKind.newWord);
    }
    advance(CardOutcome.skipped);
  });

  /// The *Undo* of [knewIt] or [skip]: the write taken back and the card
  /// asked again. False when there was nothing to take back, or a write was
  /// still in flight.
  Future<bool> undo() async {
    final current = state.value;
    if (current == null || current.position == 0 || _busy) return false;
    final last = current.position - 1;
    final outcome = current.results[last];
    if (outcome == null) return false;
    _busy = true;
    try {
      final date = _row(current.items[last]).date;
      if (outcome == CardOutcome.skipped) {
        if (date != null) {
          await PlanRepository(ref.read(appDatabaseProvider)).skip(
            planDate: date,
            uid: current.items[last].uid,
            kind: PlanKind.newWord,
            skipped: false,
          );
        }
      } else {
        await _rating.undo();
      }
      state = AsyncData<StudySessionState>(current.back());
      _shownAt = ref.read(clockProvider)();
      return true;
    } finally {
      _busy = false;
    }
  }

  /// FR-T2-01: turns the current card over.
  void reveal() {
    final current = state.value;
    if (current == null || current.finished || current.revealed) return;
    state = AsyncData<StudySessionState>(current.reveal());
  }

  /// Moves past the current card, recording how it went.
  void advance(CardOutcome outcome) {
    final current = state.value;
    if (current == null || current.finished) return;
    state = AsyncData<StudySessionState>(current.advance(outcome));
    _shownAt = ref.read(clockProvider)();
  }
}
