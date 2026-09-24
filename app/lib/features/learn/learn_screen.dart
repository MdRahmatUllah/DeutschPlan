import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_screen.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A CEFR level as the course map and the grammar library band it: its
/// German name where the course gives one, and its colour.
abstract final class CourseLevel {
  /// German course text, the same in every UI language. `content.db` names
  /// the levels in English only, so the bands' names live here.
  static const Map<String, String> _names = <String, String>{
    'A1': 'Anfänger',
    'A2': 'Grundstufe',
    'B1': 'Mittelstufe',
  };

  /// "Anfänger"; null for a level with no name of its own.
  static String? name(String code) => _names[code];

  /// "A1 · Anfänger"; "B2" for a level with no name of its own.
  static String band(String code) =>
      _names[code] == null ? code : '$code · ${_names[code]}';

  /// The band's fill, cycling through the palette in course order, and the
  /// ink that reads on it.
  static (Color, Color) colours(DpTokens tokens, String code) {
    final c = tokens.color;
    return switch (code) {
      'A1' => (c.primary, c.onPrimary),
      'A2' => (c.accent, c.onAccent),
      'B1' => (c.die, c.onAccent),
      'B2' => (c.der, c.onDer),
      'C1' => (c.easy, c.onAccent),
      _ => (c.hard, c.onAccent),
    };
  }
}

/// L1's badge on a step tile (FR-L1-01), in the order they win.
enum StepBadge { passed, current, examsUnlocked, none, locked }

/// FR-L1-01: *Passed* for any passed mock, *Current* for the active step,
/// *Exams unlocked* once enough is introduced, and the lock for a step not
/// started.
StepBadge stepBadge(StepProgress step) {
  if (step.passed) return StepBadge.passed;
  if (step.active) return StepBadge.current;
  if (step.unlocked) return StepBadge.examsUnlocked;
  if (step.introduced == 0) return StepBadge.locked;
  return StepBadge.none;
}

/// L1 · Learn (`docs/04-screens/learn.md`, `Learn-android.html`): the whole
/// course as a path. A Sun header with the course-wide totals, a band per
/// level with its two step tiles, the current tile expanded with today's
/// cards and *Study*, and the grammar library and word categories cards.
class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  final GlobalKey _current = GlobalKey();
  bool _shown = false;

  /// FR-L1-02: the current tile, scrolled into view once, on open. Only as
  /// far as it takes: a tile already on screen leaves the header in place.
  void _showCurrent() {
    if (_shown) return;
    final tile = _current.currentContext;
    if (tile == null) return;
    _shown = true;
    Scrollable.ensureVisible(
      tile,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(stepProgressProvider);
    final steps = state.value;
    final day = ref.watch(todayViewProvider);

    final Widget body;
    if (steps != null) {
      // Once the day is in too: its row grows the current tile, and a tile
      // scrolled to before it grew would end with its button off screen.
      if (!_shown && !day.isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCurrent();
        });
      }
      body = _Course(steps: steps, today: day.value, currentKey: _current);
    } else if (state.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
            message: l10n.learnLoadFailed,
            retryLabel: l10n.retry,
            onRetry: () => ref.invalidate(stepProgressProvider),
          ),
        ),
      );
    } else {
      body = const SizedBox.expand();
    }

    // Glass has no paper of its own: the aurora is, led by Sun.
    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.accent, child: body)
          : body,
    );
  }
}

class _Course extends StatelessWidget {
  const _Course({
    required this.steps,
    required this.today,
    required this.currentKey,
  });

  final List<StepProgress> steps;
  final TodayView? today;
  final GlobalKey currentKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final levels = <String, List<StepProgress>>{};
    for (final step in steps) {
      (levels[step.levelCode] ??= <StepProgress>[]).add(step);
    }
    final topics = steps.fold(0, (sum, step) => sum + step.grammar);
    final learned = steps.fold(0, (sum, step) => sum + step.grammarLearned);

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        LearnHeader(steps: steps),
        Stack(
          children: <Widget>[
            // The path: a dotted line through every dot, from the first
            // band down.
            const Positioned(
              left: 29,
              top: 16,
              bottom: 0,
              width: 2,
              child: _Path(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final MapEntry(key: level, value: tiles)
                      in levels.entries) ...<Widget>[
                    LevelBand(code: level),
                    for (final step in tiles)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: StepTile(
                          key: step.active ? currentKey : null,
                          step: step,
                          badge: stepBadge(step),
                          today: step.active ? today : null,
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinkCard(
                icon: Icons.menu_book_outlined,
                title: l10n.learnGrammarLibrary,
                subtitle: l10n.learnGrammarLibraryLine(topics, learned),
                onTap: () => context.jumpToTab(const GrammarLibraryRoute()),
              ),
              const SizedBox(height: 8),
              LinkCard(
                icon: Icons.layers_outlined,
                title: l10n.learnCategories,
                subtitle: l10n.learnCategoriesLine,
                onTap: () => context.jumpToTab(const CategoriesRoute()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Your course": the words done and grammar topics learned across the
/// course, over a course-wide bar.
class LearnHeader extends StatelessWidget {
  const LearnHeader({required this.steps, super.key});

  final List<StepProgress> steps;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    int sum(int Function(StepProgress step) of) =>
        steps.fold(0, (total, step) => total + of(step));
    final done = sum((step) => step.done);
    // Glass tints a white panel, so the ink is the page's; Sun takes the
    // ink made for it, in dark mode too.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10 + MediaQuery.paddingOf(context).top,
        16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DpText(l10n.learnTitle, role: DpTextRole.headline, color: ink),
          const SizedBox(height: 8),
          DpText(
            l10n.learnCourseLine(
              done,
              sum((step) => step.words),
              sum((step) => step.grammarLearned),
              sum((step) => step.grammar),
            ),
            role: DpTextRole.label,
            color: ink,
          ),
          const SizedBox(height: 8),
          DpSegmentedBar(
            done: done,
            learning: sum((step) => step.learning),
            todo: sum((step) => step.todo),
            colours: (
              done: ink,
              learning: tokens.isGlass
                  ? ink.withValues(alpha: 0.5)
                  : tokens.color.onAccentMark,
              todo: ink.withValues(alpha: tokens.isGlass ? 0.16 : 0.18),
            ),
          ),
        ],
      ),
    );

    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.accent),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.accent, child: content);
  }
}

/// A level's band across the path: "A1 · ANFÄNGER" on its colour.
class LevelBand extends StatelessWidget {
  const LevelBand({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (fill, onFill) = CourseLevel.colours(tokens, code);
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DpText(
        CourseLevel.band(code).toUpperCase(),
        role: DpTextRole.caption,
        weight: 700,
        letterSpacing: 0.6,
        color: tokens.isGlass ? tokens.color.ink : onFill,
      ),
    );
    // A heading of its own, read before its two tiles rather than merged
    // with the other bands. The path runs on over it, as the artboard draws.
    return Semantics(
      container: true,
      header: true,
      child: Stack(
        // Passthrough: the band takes the path's full width, not its label's.
        fit: StackFit.passthrough,
        children: <Widget>[
          if (tokens.isGlass)
            DpSurface(kind: DpSurfaceKind.tint(fill), radius: 0, child: label)
          else
            ColoredBox(color: fill, child: label),
          const Positioned(
            left: 29,
            top: 0,
            bottom: 0,
            width: 2,
            child: _Path(),
          ),
        ],
      ),
    );
  }
}

/// One step on the path: its dot, and its tile — code, badge, bar and
/// counts. The current step's tile is expanded with [today].
class StepTile extends StatelessWidget {
  const StepTile({
    required this.step,
    required this.badge,
    super.key,
    this.today,
  });

  final StepProgress step;
  final StepBadge badge;

  /// The day, on the current tile: what is left and *Study*.
  final TodayView? today;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final current = badge == StepBadge.current;
    final locked = badge == StepBadge.locked;

    final Widget? mark = switch (badge) {
      StepBadge.passed => DpPill(
        label: l10n.learnPassed,
        fill: tokens.color.easy,
        icon: Icons.check,
      ),
      StepBadge.current => DpPill(
        label: l10n.learnCurrent,
        fill: tokens.color.accent,
      ),
      StepBadge.examsUnlocked => DpPill(
        label: l10n.learnExamsUnlocked,
        fill: tokens.color.primary,
        ink: tokens.color.onPrimary,
      ),
      StepBadge.locked => Icon(
        Icons.lock_outline,
        size: 18,
        color: tokens.color.textSecondary,
        semanticLabel: l10n.learnNotStarted,
      ),
      StepBadge.none => null,
    };

    final view = today;
    final blocks = view == null ? const <SessionBlock>[] : openBlocks(view);
    final left = blocks.fold(0, (sum, block) => sum + block.uids.length);

    final tile = DpSurface(
      kind: current ? DpSurfaceKind.card : DpSurfaceKind.bar,
      selected: current,
      glassOutline: tokens.color.accent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // FR-L1-03: every tile opens its step, a locked one included.
      onTap: () => context.jumpToTab(LearnStepRoute(code: step.code)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DpText(
                  step.code,
                  role: DpTextRole.title,
                  color: locked ? tokens.color.textSecondary : null,
                ),
              ),
              ?mark,
            ],
          ),
          const SizedBox(height: 8),
          DpSegmentedBar(
            done: step.done,
            learning: step.learning,
            todo: step.todo,
            height: 6,
          ),
          const SizedBox(height: 8),
          DpText(
            l10n.learnStepLine(step.words, step.grammar),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
          if (view != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              height: tokens.surface.outlineWidth,
              color: tokens.surface.outline,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DpText(
                    blocks.isEmpty
                        ? l10n.learnTodayDone
                        : l10n.learnTodayLeft(left),
                    role: DpTextRole.body,
                    weight: 600,
                  ),
                ),
                if (blocks.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 12),
                  // FR-L1-04: the session Today's button opens.
                  Builder(
                    builder: (button) => DpButton(
                      label: l10n.learnStudy,
                      compact: true,
                      expand: false,
                      onPressed: () => StudyRoute.open(
                        context,
                        SessionArgs(
                          blocks: blocks,
                          planDate: view.date,
                          origin: originOf(button),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Dot(badge: badge),
        const SizedBox(width: 12),
        Expanded(child: tile),
      ],
    );
  }
}

/// The step's dot on the path: a Lime tick once passed, Sun with an ink
/// centre for the current step, hollow otherwise.
class _Dot extends StatelessWidget {
  const _Dot({required this.badge});

  final StepBadge badge;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill = switch (badge) {
      StepBadge.passed => tokens.color.easy,
      StepBadge.current => tokens.color.accent,
      _ => null,
    };
    final mark = tokens.color.onAccent;
    if (fill == null) {
      // Paper on paper; frosted under glass, without a blur of its own.
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.isGlass ? tokens.surface.card : tokens.surface.paper,
          border: Border.all(color: tokens.surface.outline, width: 2),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: tokens.isGlass
            ? Border.all(color: tokens.surface.outline)
            : Border.all(color: tokens.color.ink, width: 2),
      ),
      alignment: Alignment.center,
      child: badge == StepBadge.passed
          ? Icon(Icons.check, size: 14, color: mark)
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: mark),
            ),
    );
  }
}

/// The dotted line the steps hang on.
class _Path extends StatelessWidget {
  const _Path();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotsPainter(context.tokens.color.ink));
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink;
    final r = size.width / 2;
    // 2 px dots, 2 px apart, as CSS draws a 2 px dotted border.
    for (var y = r; y < size.height; y += 4 * r) {
      canvas.drawCircle(Offset(r, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.ink != ink;
}

/// The Grammar library and Word categories cards under the path.
class LinkCard extends StatelessWidget {
  const LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: tokens.color.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(title, role: DpTextRole.body, weight: 600),
                    const SizedBox(height: 1),
                    DpText(
                      subtitle,
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
