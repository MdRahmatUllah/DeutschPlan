import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/domain/plan_engine.dart' show PlanKind;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'study_summary.g.dart';

/// What is left of the day once a session ends (FR-T3-02). First the day's
/// open blocks in their order (BR-PLAN-02), since a session from one section
/// card or from T4 leaves the rest of the day to come (#328). Then today's
/// open practice sentences and the backlog. Last, whether the day is complete
/// (BR-PLAN-10) with T6 still to come: a day already celebrated is not done
/// again (FR-T6-01).
class StudyNext {
  const StudyNext({
    required this.sentences,
    required this.backlog,
    required this.dayDone,
    this.revise = const <String>[],
    this.newWords = const <String>[],
    this.grammar = const <String>[],
  });

  /// The day's revise and new words still open, neither done nor skipped,
  /// in the order they were planned.
  final List<String> revise;
  final List<String> newWords;

  /// The topics due today.
  final List<String> grammar;

  final int sentences;
  final int backlog;
  final bool dayDone;
}

@riverpod
Future<StudyNext> studyNext(Ref ref, String date) async {
  final db = ref.watch(appDatabaseProvider);
  final plans = DriftPlanStore(db, ref.watch(settingsProvider));
  final open = await ref.watch(planRepositoryProvider).stillOpen(date);
  Future<List<String>> left(PlanKind kind) async => <String>[
    for (final uid in await plans.plannedOn(date, kind))
      if (open.contains((kind.wire, uid))) uid,
  ];
  // A rest day offers no grammar, as Today shows none (BR-PLAN-02).
  final grammar = await ref.watch(planEngineProvider).studyDayOn(date)
      ? await plans.grammarDueOn(date)
      : const <String>[];
  final picked = await ref.watch(sentencePickerProvider).forDay(date);
  final rated = await ref.watch(sentenceStoreProvider).rated(date);
  final revise = await left(PlanKind.revise);
  final newWords = await left(PlanKind.newWord);
  return StudyNext(
    revise: revise,
    newWords: newWords,
    grammar: grammar,
    sentences: math.max(0, picked.length - rated),
    backlog: (await plans.backlogBefore(date)).length,
    // BR-PLAN-10 counts the grammar due, as Today's "Tag geschafft" does.
    // The rows read, not every open one: a word a content update removed
    // keeps its row but can't be studied, and must not hold the day open.
    dayDone:
        revise.isEmpty &&
        newWords.isEmpty &&
        grammar.isEmpty &&
        !await ref.watch(planRepositoryProvider).dayCompleteShown(date),
  );
}

/// Where T3 sends the learner.
enum StudyNextStep { revise, newWords, grammar, sentences, backlog, done }

/// T3 · the session summary (`session-summary.md`): a sheet over the faded
/// session. "Gut gemacht!", the session's own count and time and rating
/// pills (FR-T3-01), up to five words rated Again with play, and the next
/// step: the next open block, the backlog if any, and *Done for now*
/// always (FR-T3-02). Dragged down, it is *Done for now* (FR-T3-03).
class StudySummarySheet extends ConsumerStatefulWidget {
  const StudySummarySheet({
    required this.session,
    required this.next,
    required this.onStep,
    super.key,
  });

  final StudySessionState session;

  /// Null for a session outside the day's plan: nothing comes next.
  final StudyNext? next;

  final ValueChanged<StudyNextStep> onStep;

  /// The artboard's medium detent, its 8 + 24 px padding included.
  static const double height = 520;

  /// How far down, or how fast, a drag dismisses it.
  static const double dismissAt = 120;
  static const double fling = 700;

  /// FR-T3-02: the next open block in the day's order (BR-PLAN-02). That's
  /// its revisions, then its new words, then the grammar (the session's own,
  /// else the day's), then its sentences. With nothing left, *Done for now*
  /// leads.
  static StudyNextStep primaryFor(StudySessionState session, StudyNext? next) {
    if (next?.revise.isNotEmpty ?? false) return StudyNextStep.revise;
    if (next?.newWords.isNotEmpty ?? false) return StudyNextStep.newWords;
    if (grammarFor(session, next).isNotEmpty) return StudyNextStep.grammar;
    if ((next?.sentences ?? 0) > 0) return StudyNextStep.sentences;
    return StudyNextStep.done;
  }

  /// The topics T3's grammar step practises: those left in the session, else
  /// the day's due ones, which a session from one section card didn't queue.
  static List<String> grammarFor(StudySessionState session, StudyNext? next) =>
      session.grammarLeft.isNotEmpty
      ? session.grammarLeft
      : next?.grammar ?? const <String>[];

  @override
  ConsumerState<StudySummarySheet> createState() => _StudySummarySheetState();
}

class _StudySummarySheetState extends ConsumerState<StudySummarySheet> {
  double _drag = 0;

  void _end(DragEndDetails details) {
    final fast = (details.primaryVelocity ?? 0) > StudySummarySheet.fling;
    if (_drag > StudySummarySheet.dismissAt || fast) {
      widget.onStep(StudyNextStep.done);
      return;
    }
    setState(() => _drag = 0);
  }

  void _play(String text) => unawaited(say(ref, context, text));

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final session = widget.session;
    final next = widget.next;

    // FR-T3-01: the session's own results, not the day's totals. I know it
    // is an Easy rating (BR-STATUS-04); a skip is not a card done.
    final outcomes = session.results.values;
    int count(Set<CardOutcome> of) => outcomes.where(of.contains).length;
    final cards = count(<CardOutcome>{
      CardOutcome.again,
      CardOutcome.hard,
      CardOutcome.good,
      CardOutcome.easy,
      CardOutcome.knewIt,
    });
    final pills = <(int, String, Color)>[
      (count({CardOutcome.again}), l10n.ratingAgain, tokens.color.again),
      (count({CardOutcome.hard}), l10n.ratingHard, tokens.color.hard),
      (count({CardOutcome.good}), l10n.ratingGood, tokens.color.good),
      (
        count({CardOutcome.easy, CardOutcome.knewIt}),
        l10n.ratingEasy,
        tokens.color.easy,
      ),
    ];
    final watch = <String>[
      for (final MapEntry(:key, :value) in session.results.entries)
        if (value == CardOutcome.again) session.items[key].uid,
    ].take(5).toList();

    final primary = StudySummarySheet.primaryFor(session, next);
    final backlog = next?.backlog ?? 0;
    final started = session.startedAt;
    final minutes = started == null
        ? 1
        : math.max(1, ref.read(clockProvider)().difference(started).inMinutes);

    final large = DpScript.large(context);
    final head = <Widget>[
      Center(
        child: Container(
          width: 36,
          height: 5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: tokens.surface.muted,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      DpText(l10n.summaryTitle, role: DpTextRole.headline),
      const SizedBox(height: 2),
      DpText(
        l10n.summaryStats(cards, minutes),
        role: DpTextRole.caption,
        color: tokens.color.textSecondary,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final (n, rating, colour) in pills)
            if (n > 0)
              _Pill(label: l10n.summaryPill(n, rating), colour: colour),
        ],
      ),
    ];
    final watchRows = <Widget>[
      if (watch.isNotEmpty) ...<Widget>[
        const SizedBox(height: 18),
        DpText(
          l10n.summaryWatch.toUpperCase(),
          role: DpTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 4),
        for (final uid in watch) _WatchRow(uid: uid, onPlay: _play),
      ],
    ];
    final buttons = <Widget>[
      const SizedBox(height: 10),
      DpButton(
        label: switch (primary) {
          StudyNextStep.revise => l10n.summaryRevise(next!.revise.length),
          StudyNextStep.newWords => l10n.summaryNew(next!.newWords.length),
          StudyNextStep.grammar => l10n.summaryGrammar(
            StudySummarySheet.grammarFor(session, next).length,
          ),
          StudyNextStep.sentences => l10n.summarySentences(next!.sentences),
          StudyNextStep.backlog || StudyNextStep.done => l10n.summaryDone,
        },
        onPressed: () => widget.onStep(primary),
      ),
      if (backlog > 0) ...<Widget>[
        const SizedBox(height: 10),
        DpButton(
          label: l10n.summaryBacklog(backlog),
          kind: DpButtonKind.secondary,
          onPressed: () => widget.onStep(StudyNextStep.backlog),
        ),
      ],
      if (primary != StudyNextStep.done) ...<Widget>[
        const SizedBox(height: 10),
        DpButton(
          label: l10n.summaryDone,
          kind: DpButtonKind.text,
          onPressed: () => widget.onStep(StudyNextStep.done),
        ),
      ],
    ];
    final sheet = DpSurface(
      kind: DpSurfaceKind.cardStrong,
      radius: tokens.shape.sheet,
      // The sheet runs its own radius past the screen's foot, so only its
      // top corners show rounded.
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + tokens.shape.sheet),
      child: SizedBox(
        height:
            math.min(
              StudySummarySheet.height,
              MediaQuery.sizeOf(context).height * 0.85,
            ) -
            8 -
            24,
        // Past 130 % text the sheet's fixed parts alone were taller than
        // it (#165): it all scrolls, the buttons with it.
        child: large
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[...head, ...watchRows, ...buttons],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ...head,
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: watchRows,
                    ),
                  ),
                  ...buttons,
                ],
              ),
      ),
    );

    return GestureDetector(
      onVerticalDragUpdate: (details) =>
          setState(() => _drag = math.max(0, _drag + details.delta.dy)),
      onVerticalDragEnd: _end,
      child: Transform.translate(
        offset: Offset(0, tokens.shape.sheet + _drag),
        child: sheet,
      ),
    );
  }
}

/// T3's presentation: the scrim over the faded session and the sheet rising
/// from the foot. Laid over the screen rather than pushed as a route, so the
/// undo bar of the last card stays above it and its *Undo* still works.
class StudySummaryOverlay extends StatelessWidget {
  const StudySummaryOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: still ? Duration.zero : tokens.motion.standard,
      curve: Curves.easeOutCubic,
      builder: (context, t, sheet) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: ColoredBox(
              color: tokens.surface.scrim.withValues(
                alpha: tokens.surface.scrim.a * t,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionalTranslation(
              translation: Offset(0, 1 - t),
              child: sheet,
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A rating pill: "2 Again", filled in the rating's colour.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The artboard's 28, grown with the text size (#165).
    return Container(
      height: MediaQuery.textScalerOf(context).scale(28),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.color.ink, width: 1.5),
      ),
      // Hugs its label: a pill, not a bar.
      child: Center(
        widthFactor: 1,
        child: DpText(
          label,
          role: DpTextRole.label,
          weight: 700,
          color: tokens.color.onAccent,
        ),
      ),
    );
  }
}

/// A word to watch: the headword with its article, and play.
class _WatchRow extends ConsumerWidget {
  const _WatchRow({required this.uid, required this.onPlay});

  final String uid;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = ref.watch(studyWordProvider(uid)).value?.word;
    // The artboard's 44, grown with the text size (#165).
    final height = MediaQuery.textScalerOf(context).scale(44);
    if (word == null) return SizedBox(height: height);
    final spoken = spokenForm(word);
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(
            child: DpHeadword(
              word.german,
              article: word.article,
              role: DpTextRole.bodyLarge,
            ),
          ),
          StudyPlayButton(
            label: AppLocalizations.of(context).summaryPlay(spoken),
            onPressed: () => onPlay(spoken),
          ),
        ],
      ),
    );
  }
}
