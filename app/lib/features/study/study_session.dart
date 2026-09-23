import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show PlanRepository;
import 'package:deutschplan/domain/plan_engine.dart' show PlanKind;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'study_session.g.dart';

/// One card of a session: a word to revise or learn, or a grammar topic's
/// practice set.
@immutable
class StudyItem {
  const StudyItem(this.kind, this.uid);

  final SessionBlockKind kind;

  /// A word uid, or a topic uid for [SessionBlockKind.grammar].
  final String uid;

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
  });

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
    position: position + 1,
    results: <int, CardOutcome>{...results, position: outcome},
  );

  StudySessionState reveal() => StudySessionState(
    items: items,
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
    final date = args.planDate;
    // A card rated or skipped since the args were made is not asked again.
    final open = date == null
        ? null
        // The repository over the kept-alive database, not its auto-disposed
        // provider: a kept-alive notifier must not hold one open.
        : await PlanRepository(ref.read(appDatabaseProvider)).stillOpen(date);

    bool wanted(SessionBlockKind kind, String uid) => switch (kind) {
      SessionBlockKind.revise =>
        open == null || open.contains((PlanKind.revise.wire, uid)),
      SessionBlockKind.newWords =>
        open == null || open.contains((PlanKind.newWord.wire, uid)),
      SessionBlockKind.grammar => true,
    };

    // BR-PLAN-02: the blocks in their fixed order, whatever order they came.
    final ordered = <SessionBlock>[...args.blocks]
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return StudySessionState(
      items: <StudyItem>[
        for (final block in ordered)
          for (final uid in block.uids)
            if (wanted(block.kind, uid)) StudyItem(block.kind, uid),
      ],
    );
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
  }
}
