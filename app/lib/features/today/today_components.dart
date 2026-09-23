import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
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
    final greeting = switch (dayPart(view.hour)) {
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
                  ),
                  const SizedBox(height: 4),
                  DpText(
                    view.learnerName == null
                        ? greeting
                        : l10n.todayGreetingNamed(greeting, view.learnerName!),
                    role: DpTextRole.headline,
                    color: ink,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          DpChip(
            label: view.streak.toString(),
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
  });

  final TodayView view;

  /// The ring opens T2, as the button does. Null when nothing is open.
  final VoidCallback? onStart;

  /// FR-T1-08: the step chip goes to the Learn tab.
  final VoidCallback onStep;

  static const double ringSize = 132;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final step = view.step;
    final words = view.stepWords;

    return DpSurface(
      // The paper card has the artboard's 2 px ink edge and offset shadow;
      // the glass one is a plain panel.
      selected: !tokens.isGlass,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Semantics(
            button: onStart != null,
            onTap: onStart,
            child: GestureDetector(
              onTap: onStart,
              behavior: HitTestBehavior.opaque,
              // Tweens from 0 on open, and on to the new count after a
              // session. Still under reduce motion.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: view.completed.toDouble()),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => DpProgressRing(
                  completed: value.round(),
                  total: view.total,
                  size: ringSize,
                  caption: view.left == 0
                      ? null
                      : l10n.todayEstimate(view.estimateMinutes),
                  semanticLabel: l10n.todayRing(view.completed, view.total),
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
                DpText(
                  l10n.todayCourseDay(view.courseDay),
                  role: DpTextRole.body,
                ),
                if (step != null) ...<Widget>[
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
    this.progress = BlockProgress.none,
    this.ringColour,
    this.onTap,
  });

  final IconData icon;

  /// The icon tile's fill. The block's colour, from the palette.
  final Color tile;

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
    // The bright tiles take the dark ink in every mode; Oat, which is the
    // muted surface, takes the page's.
    final onTile = tile == tokens.surface.muted
        ? tokens.color.ink
        : tokens.color.onAccent;

    return Semantics(
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
  });

  final GrammarPreview preview;

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
                        if (preview.rule.isNotEmpty) ...<Widget>[
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

/// The docked button under the plan.
class PrimaryActionBar extends StatelessWidget {
  const PrimaryActionBar({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// Null disables it, as "All done" is.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: DpButton(label: label, onPressed: onPressed),
  );
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
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, size: 24, color: colour),
      ),
    ),
  );
}
