import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/plan_engine.dart'
    show addDays, parsePlanDate;
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// T1's header block: the German date and greeting, the streak, the gear.
///
/// Lagoon on paper; a Lagoon-tinted glass panel under glass. It runs up under
/// the status bar, and the ring card overlaps its bottom 24 dp.
class TodayHeader extends StatelessWidget {
  const TodayHeader({
    required this.view,
    required this.onStreak,
    required this.onSettings,
    super.key,
  });

  final TodayView view;
  final VoidCallback onStreak;
  final VoidCallback onSettings;

  /// How far the ring card reaches up into the header.
  static const double overlap = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // Glass tints a white panel, so the ink is the page's; the solid field
    // takes the ink made for Lagoon.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onPrimary;
    final greeting = view.isRestDay
        ? l10n.todayRestDay
        : view.isDone
        ? l10n.todayGreetingDone
        : switch (dayPart(view.hour)) {
            DayPart.morning => l10n.todayGreetingMorning,
            DayPart.day => l10n.todayGreetingDay,
            DayPart.evening => l10n.todayGreetingEvening,
          };

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10 + MediaQuery.paddingOf(context).top,
        16,
        16 + overlap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    germanDate(view.date),
                    role: DpTextRole.label,
                    color: ink,
                    german: true,
                  ),
                  const SizedBox(height: 4),
                  DpText(
                    // "Rest day" is a heading, not a greeting: no name on it.
                    view.learnerName == null || view.isRestDay
                        ? greeting
                        : l10n.todayGreetingNamed(greeting, view.learnerName!),
                    role: DpTextRole.headline,
                    color: ink,
                    // German: at 200 % "geschafft" breaks at a syllable (#165).
                    allowBreaks: true,
                    // German in every UI language, as the date is; "Rest
                    // day" is the app's own copy (#162).
                    german: !view.isRestDay,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          DpChip(
            label: AppLocalizations.of(context).digits(view.streak),
            kind: DpChipKind.streak,
            semanticLabel: l10n.todayStreak(view.streak),
            onTap: onStreak,
          ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.settings_outlined,
            label: l10n.todaySettings,
            colour: ink,
            onTap: onSettings,
          ),
        ],
      ),
    );

    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.primary),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.primary, child: content);
  }
}

/// The ring, the step chip, the course day and the step's word bar.
class ProgressRingCard extends StatelessWidget {
  const ProgressRingCard({
    required this.view,
    required this.onStart,
    required this.onStep,
    super.key,
    this.onStudyDays,
  });

  final TodayView view;

  /// The ring opens T2, as the button does. Null when nothing is open.
  final VoidCallback? onStart;

  /// FR-T1-08: the step chip goes to the Learn tab.
  final VoidCallback onStep;

  /// TodayRest's "Change days in Settings → Study days".
  final VoidCallback? onStudyDays;

  static const double ringSize = 132;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final step = view.step;
    final words = view.stepWords;

    // One stop for a screen reader: its text read as the card, not run
    // into the next card's (#162).
    return Semantics(
      container: true,
      child: DpSurface(
        // The paper card has the artboard's 2 px ink edge and offset shadow;
        // the glass one is a plain panel.
        selected: !tokens.isGlass,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            // One node (#315): the ring's name and value, with the tap. Apart, a
            // screen reader found a nameless button over the ring's label.
            MergeSemantics(
              child: Semantics(
                button: onStart != null,
                onTap: onStart,
                child: GestureDetector(
                  onTap: onStart,
                  behavior: HitTestBehavior.opaque,
                  // Tweens from 0 on open, and on to the new count after a
                  // session. Still under reduce motion.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: view.completed.toDouble(),
                    ),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => DpProgressRing(
                      completed: value.round(),
                      total: view.total,
                      size: ringSize,
                      // TodayDone: the ring turns Lime, with a tick for the time.
                      colour: view.isDone ? tokens.color.easy : null,
                      caption: view.isRestDay
                          ? l10n.todayRestNoPlan
                          : view.left == 0
                          ? null
                          : l10n.todayEstimate(view.estimateMinutes),
                      captionIcon: view.isDone ? Icons.check : null,
                      // TodayRest: nothing planned, and the ring says so.
                      countLabel: view.isRestDay ? l10n.todayRestFree : null,
                      semanticLabel: l10n.todayRing(view.completed, view.total),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (step != null) ...<Widget>[
                    DpChip(
                      label: step,
                      kind: DpChipKind.step,
                      selected: true,
                      onTap: onStep,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (view.isRestDay) ...<Widget>[
                    DpText(
                      l10n.todayRestOff(
                        DateFormat.EEEE(
                          Localizations.localeOf(context).toString(),
                        ).format(parsePlanDate(view.date)),
                      ),
                      role: DpTextRole.body,
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      link: true,
                      child: GestureDetector(
                        onTap: onStudyDays,
                        behavior: HitTestBehavior.opaque,
                        child: DpText(
                          l10n.todayRestStudyDays,
                          role: DpTextRole.caption,
                          color: tokens.color.textSecondary,
                        ),
                      ),
                    ),
                  ] else
                    DpText(
                      view.isDone
                          ? l10n.todayDoneLine(
                              view.courseDay,
                              view.words,
                              view.minutes,
                            )
                          : l10n.todayCourseDay(view.courseDay),
                      role: DpTextRole.body,
                    ),
                  if (step != null && !view.isRestDay) ...<Widget>[
                    const SizedBox(height: 8),
                    DpSegmentedBar(
                      done: words.done,
                      learning: words.learning,
                      todo: words.todo,
                      height: 6,
                    ),
                    const SizedBox(height: 8),
                    DpText(
                      l10n.todayStepWords(words.done, words.total, step),
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What sits at the end of a section card.
enum SectionTrailing { none, progress, done, open }

/// One block of today's plan: Revise, New today, Backlog, Grammar due or
/// Practice sentences.
class PlanSectionCard extends StatelessWidget {
  const PlanSectionCard({
    required this.icon,
    required this.tile,
    required this.title,
    required this.subtitle,
    required this.trailing,
    super.key,
    this.tileInk,
    this.progress = BlockProgress.none,
    this.ringColour,
    this.onTap,
  });

  final IconData icon;

  /// The icon tile's fill. The block's colour, from the palette.
  final Color tile;

  /// The icon's colour on [tile], for a fill with an ink of its own — Cobalt
  /// takes `onDer`. Otherwise the bright fills take the dark ink and Oat the
  /// page's.
  final Color? tileInk;

  final String title;
  final String subtitle;
  final SectionTrailing trailing;

  /// For [SectionTrailing.progress]: how far the block has got.
  final BlockProgress progress;
  final Color? ringColour;

  /// FR-T1-04: a session with only this block, or the screen it opens.
  final VoidCallback? onTap;

  static const double height = 66;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final onTile =
        tileInk ??
        (tile == tokens.surface.muted
            ? tokens.color.ink
            : tokens.color.onAccent);

    return Semantics(
      // Its own node even when it can't be pressed (Revise · 0): its text
      // was read run into the next card's (#162).
      container: true,
      button: onTap != null,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height - 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tile,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.color.ink, width: 1.5),
                ),
                child: Icon(icon, size: 20, color: onTile),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(title, role: DpTextRole.body, weight: 600),
                    const SizedBox(height: 2),
                    DpText(
                      subtitle,
                      role: DpTextRole.label,
                      weight: 400,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              switch (trailing) {
                SectionTrailing.none => const SizedBox.shrink(),
                SectionTrailing.progress => DpProgressRing(
                  completed: progress.done,
                  total: progress.total,
                  size: 28,
                  colour: ringColour,
                  showCount: false,
                ),
                SectionTrailing.done => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.color.easy,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.color.ink, width: 1.5),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: tokens.color.onAccent,
                  ),
                ),
                SectionTrailing.open => Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: tokens.color.ink,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// "Grammar this week": the step's next topic and the first line of its rule.
class GrammarPreviewCard extends StatelessWidget {
  const GrammarPreviewCard({
    required this.preview,
    required this.onTap,
    super.key,
    this.showRule = true,
  });

  final GrammarPreview preview;

  /// TodayDone drops the rule line: the day's work is over, and the card is
  /// only a pointer to the week's topic.
  final bool showRule;

  /// FR-T1-08: the Learn tab, then the topic.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = tokens.surface.outlineWidth;

    return Semantics(
      button: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: onTap,
        // Inset by the outline, so the Sun strip sits inside the border the
        // way the artboard's `overflow: hidden` keeps it.
        padding: EdgeInsets.all(edge),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.shape.card - edge),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ColoredBox(
                  color: tokens.color.accent,
                  child: const SizedBox(width: 6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DpText(
                          l10n.todayGrammarWeek.toUpperCase(),
                          semanticsLabel: l10n.todayGrammarWeek,
                          role: DpTextRole.caption,
                          weight: 700,
                          letterSpacing: 0.6,
                          color: tokens.color.textSecondary,
                        ),
                        const SizedBox(height: 2),
                        DpText(
                          preview.topic,
                          role: DpTextRole.body,
                          weight: 600,
                        ),
                        if (showRule && preview.rule.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          DpText(
                            preview.rule,
                            role: DpTextRole.label,
                            weight: 400,
                            maxLines: 1,
                            color: tokens.color.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: tokens.color.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// FR-T1-06's one contextual card: a coloured strip, what happened, one
/// action, and a dismiss button where dismissing makes sense.
///
/// No artboard draws these on Today, so it borrows the grammar card's shape:
/// the same bar surface and 6 dp strip, which is what the page already uses
/// for "something beside the plan".
class ContextualCard extends StatelessWidget {
  const ContextualCard({
    required this.offer,
    required this.onAction,
    required this.onDismiss,
    super.key,
  });

  final ContextualOffer offer;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = tokens.surface.outlineWidth;
    final step = offer.step ?? '';

    final (
      Color strip,
      String title,
      String body,
      String? action,
    ) = switch (offer.kind) {
      ContextualKind.stepComplete => (
        tokens.color.easy,
        l10n.todayCardStepTitle,
        l10n.todayCardStepBody(step),
        l10n.todayCardStepAction,
      ),
      ContextualKind.courseComplete => (
        tokens.color.easy,
        l10n.todayCardCourseTitle,
        l10n.todayCardCourseBody,
        null,
      ),
      ContextualKind.contentUpdate => (
        tokens.color.der,
        l10n.todayCardUpdateTitle,
        l10n.todayCardUpdateBody(offer.added, offer.removed, offer.changed),
        null,
      ),
      ContextualKind.pauseOffer => (
        tokens.color.hard,
        l10n.todayCardPauseTitle,
        l10n.todayCardPauseBody(offer.backlog),
        l10n.todayCardPauseAction,
      ),
      ContextualKind.examsUnlocked => (
        tokens.color.primary,
        l10n.todayCardExamsTitle,
        l10n.todayCardExamsBody(offer.percent, step),
        l10n.todayCardExamsAction,
      ),
      ContextualKind.voice => (
        tokens.color.accent,
        l10n.todayCardVoiceTitle,
        l10n.todayCardVoiceBody,
        l10n.todayCardVoiceAction,
      ),
    };

    // One stop for a screen reader: its text read as the card, not run
    // into the next card's (#162).
    return Semantics(
      container: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        padding: EdgeInsets.all(edge),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.shape.card - edge),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ColoredBox(color: strip, child: const SizedBox(width: 6)),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DpText(title, role: DpTextRole.body, weight: 600),
                        const SizedBox(height: 2),
                        DpText(
                          body,
                          role: DpTextRole.label,
                          weight: 400,
                          color: tokens.color.textSecondary,
                        ),
                        if (action != null)
                          DpButton(
                            label: action,
                            onPressed: onAction,
                            kind: DpButtonKind.text,
                            expand: false,
                          ),
                      ],
                    ),
                  ),
                ),
                if (offer.dismissible)
                  Align(
                    alignment: Alignment.topCenter,
                    child: _IconAction(
                      icon: Icons.close,
                      label: l10n.todayCardDismiss,
                      colour: tokens.color.textSecondary,
                      onTap: onDismiss,
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// TodayRest's note: why nothing is planned, and what revising anyway buys.
class RestDayNote extends StatelessWidget {
  const RestDayNote({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final before = view.dueTomorrow ?? 0;
    // One stop for a screen reader: its text read as the card, not run
    // into the next card's (#162).
    return Semantics(
      container: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DpText(l10n.todayRestNote, role: DpTextRole.body),
            // Only with something to revise: a lead with no numbers after it
            // would promise and stop.
            if (view.revise.open > 0 && before > 0) ...<Widget>[
              DpText(
                // The next study day by name when tomorrow is off too (#345).
                switch (view.nextStudyDay) {
                  final day? when day != addDays(view.date, 1) =>
                    l10n.todayRestLighterLeadDay(
                      DateFormat.EEEE(
                        Localizations.localeOf(context).toString(),
                      ).format(parsePlanDate(day)),
                    ),
                  _ => l10n.todayRestLighterLead,
                },
                role: DpTextRole.body,
              ),
              // ponytail: the artboard bolds this inline; DpText has no spans,
              // so it takes its own line. Add emphasis to DpText if another
              // screen needs the same.
              DpText(
                l10n.todayRestLighter(before, view.dueTomorrowIfRevised),
                role: DpTextRole.body,
                weight: 700,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// TodayDone's collapsed row: what the day held, all of it done.
class TodayDoneCard extends StatelessWidget {
  const TodayDoneCard({required this.view, super.key});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      if (view.revise.total > 0) l10n.todayDoneRevise(view.revise.total),
      if (view.newToday.total > 0) l10n.todayDoneNew(view.newToday.total),
      if (view.sentences.total > 0)
        l10n.todayDoneSentences(view.sentences.total),
      // Nothing waits: whether there was a backlog this morning or not, it is
      // clear now. With one still there the button offers it instead.
      if (view.backlog == 0) l10n.todayBacklogCleared,
    ];

    // One stop for a screen reader: its text read as the card, not run
    // into the next card's (#162).
    return Semantics(
      container: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.color.easy,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.color.ink, width: 1.5),
              ),
              child: Icon(Icons.check, size: 14, color: tokens.color.onAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    l10n.todayDoneTitle,
                    role: DpTextRole.body,
                    weight: 600,
                  ),
                  const SizedBox(height: 2),
                  DpText(
                    parts.join(' · '),
                    role: DpTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TodayDone's *Tomorrow* card: tomorrow's blocks and roughly how long.
class TomorrowCard extends StatelessWidget {
  const TomorrowCard({required this.tomorrow, super.key});

  final TomorrowPreview tomorrow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final category = tomorrow.category;

    // One stop for a screen reader: its text read as the card, not run
    // into the next card's (#162).
    return Semantics(
      container: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DpText(
              l10n.todayTomorrow.toUpperCase(),
              semanticsLabel: l10n.todayTomorrow,
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 8),
            if (tomorrow.restDay)
              DpText(l10n.todayTomorrowRest, role: DpTextRole.body)
            else ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (tomorrow.revise > 0)
                    DpPill(
                      label: l10n.todayTomorrowRevisions(tomorrow.revise),
                      fill: tokens.color.primary,
                      ink: tokens.color.onPrimary,
                    ),
                  if (tomorrow.newWords > 0)
                    DpPill(
                      label: l10n.todayTomorrowNew(tomorrow.newWords),
                      fill: tokens.color.accent,
                    ),
                  if (tomorrow.grammar > 0)
                    DpPill(
                      label: l10n.todayGrammarDue(tomorrow.grammar),
                      fill: tokens.surface.muted,
                      // Oat is the muted surface, so it takes the page's ink.
                      ink: tokens.color.ink,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DpText(
                category == null
                    ? l10n.todayEstimate(tomorrow.minutes)
                    : l10n.todayTomorrowContinues(tomorrow.minutes, category),
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The docked button under the plan, in the look its [action] takes.
class PrimaryActionBar extends StatelessWidget {
  const PrimaryActionBar({
    required this.action,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final TodayAction action;
  final String label;

  /// Null disables it, as "All done" is.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final button = switch (action) {
      // TodayDone: Lime with a tick, ink on it, a little faded, no shadow.
      TodayAction.done => Opacity(
        opacity: 0.85,
        child: DpButton(
          label: label,
          onPressed: null,
          colour: tokens.color.easy,
          onColour: tokens.color.onAccent,
          icon: Icon(Icons.check, size: 20, color: tokens.color.onAccent),
        ),
      ),
      // TodayRest: optional, so Oat rather than Lagoon.
      TodayAction.reviseAnyway => DpButton(
        label: label,
        onPressed: onPressed,
        colour: tokens.surface.muted,
        onColour: tokens.color.ink,
      ),
      _ => DpButton(label: label, onPressed: onPressed),
    };
    return Padding(padding: const EdgeInsets.all(16), child: button);
  }
}

/// A 44 dp icon button: the header's gear.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    // Its own node: inside a card that is one, it would merge into the
    // card and read as its text (#162).
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: AdaptiveTooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(icon, size: 24, color: colour),
        ),
      ),
    ),
  );
}
