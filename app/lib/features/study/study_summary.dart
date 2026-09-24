import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
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

/// What is left of the day once a session ends (FR-T3-02): today's open
/// practice sentences, the backlog, and whether every plan row is done or
/// skipped (BR-PLAN-10) with T6 still to come — a day already celebrated is
/// not done again (FR-T6-01).
typedef StudyNext = ({int sentences, int backlog, bool dayDone});

@riverpod
Future<StudyNext> studyNext(Ref ref, String date) async {
  final db = ref.watch(appDatabaseProvider);
  final plans = DriftPlanStore(db, ref.watch(settingsProvider));
  final picked = await ref.watch(sentencePickerProvider).forDay(date);
  final rated = await ref.watch(sentenceStoreProvider).rated(date);
  return (
    sentences: math.max(0, picked.length - rated),
    backlog: (await plans.backlogBefore(date)).length,
    dayDone:
        await plans.openPlanItems(date) == 0 &&
        !await ref.watch(planRepositoryProvider).dayCompleteShown(date),
  );
}

/// Where T3 sends the learner.
enum StudyNextStep { grammar, sentences, backlog, done }

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

  /// FR-T3-02's order: the grammar still in the session, then the day's
  /// sentences; nothing left, and *Done for now* leads.
  static StudyNextStep primaryFor(StudySessionState session, StudyNext? next) {
    if (session.grammarLeft.isNotEmpty) return StudyNextStep.grammar;
    if ((next?.sentences ?? 0) > 0) return StudyNextStep.sentences;
    return StudyNextStep.done;
  }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
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
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
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
                ],
              ),
            ),
            const SizedBox(height: 10),
            DpButton(
              label: switch (primary) {
                StudyNextStep.grammar => l10n.summaryGrammar(
                  session.grammarLeft.length,
                ),
                StudyNextStep.sentences => l10n.summarySentences(
                  next!.sentences,
                ),
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
    return Container(
      height: 28,
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
    if (word == null) return const SizedBox(height: 44);
    final spoken = spokenForm(word);
    return SizedBox(
      height: 44,
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
