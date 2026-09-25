import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'day_complete_screen.g.dart';

/// FR-T6-01: whether this is the day's first T6. Claiming it marks
/// `daily_stats.completed_shown`, so a second arrival the same day is told
/// no and leaves at once.
@riverpod
Future<bool> dayCompleteFirst(Ref ref, String day) =>
    ref.watch(planRepositoryProvider).claimDayComplete(day);

/// T6 · Day complete (`day-complete.md`): a short, genuine reward. The ring
/// completes and an ink check draws itself, twenty paper-cut pieces fall
/// once, "Tag geschafft!", the day's words and minutes, the streak, and
/// tomorrow — then back to Today on a tap or after four seconds. No share
/// prompts, ads or upsells (FR-T6-03).
class DayCompleteScreen extends ConsumerStatefulWidget {
  const DayCompleteScreen({super.key});

  /// How long the reward stays before Today comes back by itself.
  static const Duration stay = Duration(seconds: 4);

  @override
  ConsumerState<DayCompleteScreen> createState() => _DayCompleteScreenState();
}

class _DayCompleteScreenState extends ConsumerState<DayCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(vsync: this);
  Timer? _back;
  bool _left = false;

  @override
  void dispose() {
    _back?.cancel();
    _play.dispose();
    super.dispose();
  }

  /// To Today's root, once.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    _back?.cancel();
    context.jumpToTab(const TodayRoute());
  }

  void _start() {
    if (_back != null) return;
    final still = MediaQuery.disableAnimationsOf(context);
    _play
      ..duration = context.tokens.motion.celebrate
      ..value = still ? 1 : 0;
    if (!still) unawaited(_play.forward());
    _back = Timer(DayCompleteScreen.stay, _leave);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final today = ref.watch(todayProvider);
    final first = ref.watch(dayCompleteFirstProvider(today));
    final view = ref.watch(todayViewProvider).value;

    // Already celebrated today: straight on to Today.
    if (first.value == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    }
    final ready = first.value ?? false;
    if (ready && view != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
    final still = MediaQuery.disableAnimationsOf(context);

    final content = !ready || view == null
        ? const SizedBox.expand()
        : _Reward(view: view, play: _play, still: still, onBack: _leave);

    final page = GestureDetector(
      // Tap anywhere: back to Today.
      behavior: HitTestBehavior.opaque,
      onTap: ready ? _leave : null,
      child: Stack(
        children: <Widget>[
          if (ready && view != null && !still)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _play,
                  builder: (context, _) => CustomPaint(
                    painter: ConfettiPainter(
                      progress: _play.value,
                      colours: <Color>[
                        tokens.color.primary,
                        tokens.color.accent,
                        tokens.color.die,
                        tokens.color.der,
                      ],
                      ink: tokens.color.onAccent,
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(child: content),
        ],
      ),
    );

    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.color.easy,
      body: tokens.isGlass
          ? AuroraBackdrop(
              leading: tokens.color.easy,
              child: DpSurface(
                kind: DpSurfaceKind.tint(tokens.color.easy, opacity: 0.35),
                radius: 0,
                child: page,
              ),
            )
          : page,
    );
  }
}

class _Reward extends StatelessWidget {
  const _Reward({
    required this.view,
    required this.play,
    required this.still,
    required this.onBack,
  });

  final TodayView view;
  final Animation<double> play;
  final bool still;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final ink = tokens.color.onAccent;
    final words = view.revise.done + view.newToday.done;
    final tomorrow = view.tomorrow;

    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DpSurface(
                  radius: 84,
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        const DpProgressRing(
                          completed: 1,
                          total: 1,
                          size: 140,
                          showCount: false,
                        ),
                        // The ink check draws itself once the ring is full.
                        AnimatedBuilder(
                          animation: play,
                          builder: (context, _) => CustomPaint(
                            size: const Size(56, 56),
                            painter: CheckPainter(
                              progress: still
                                  ? 1
                                  : Curves.easeOut.transform(
                                      ((play.value - 0.35) / 0.5).clamp(0, 1),
                                    ),
                              ink: tokens.color.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                DpText(
                  l10n.dayCompleteTitle,
                  role: DpTextRole.display,
                  weight: 700,
                  color: ink,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                DpText(
                  l10n.dayCompleteStats(words, view.minutes),
                  role: DpTextRole.bodyLarge,
                  color: ink,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The streak bumps as it arrives.
                    AnimatedBuilder(
                      animation: play,
                      builder: (context, chip) => Transform.scale(
                        scale:
                            1 +
                            0.2 * math.sin(math.pi * play.value.clamp(0, 1)),
                        child: chip,
                      ),
                      child: DpChip(
                        label: AppLocalizations.of(context).digits(view.streak),
                        kind: DpChipKind.streak,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DpText(
                      l10n.dayCompleteStreak(view.streak),
                      role: DpTextRole.body,
                      weight: 600,
                      color: ink,
                    ),
                  ],
                ),
                if (tomorrow != null) ...<Widget>[
                  const SizedBox(height: 16),
                  DpText(
                    tomorrow.restDay
                        ? l10n.dayCompleteTomorrowRest
                        : l10n.dayCompleteTomorrow(
                            tomorrow.revise,
                            tomorrow.newWords,
                          ),
                    role: DpTextRole.body,
                    color: ink,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          child: DpButton(
            label: l10n.dayCompleteBack,
            colour: tokens.surface.cardStrong,
            onColour: tokens.color.ink,
            onPressed: onBack,
          ),
        ),
      ],
    );
  }
}

/// The ink check on a 24 × 24 grid, drawn along its length as [progress]
/// runs from 0 to 1.
class CheckPainter extends CustomPainter {
  const CheckPainter({required this.progress, required this.ink});

  final double progress;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(4, 12)
      ..lineTo(9, 17)
      ..lineTo(20, 6);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(CheckPainter old) =>
      old.progress != progress || old.ink != ink;
}

/// The artboard's twenty paper-cut pieces — Lagoon, Sun, Raspberry and
/// Cobalt, each with an ink edge — falling once into place as [progress]
/// runs from 0 to 1 (1.2 s, `motion.celebrate`). A painter, not a package
/// (#111).
class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({
    required this.progress,
    required this.colours,
    required this.ink,
  });

  final double progress;
  final List<Color> colours;
  final Color ink;

  /// (x, y, width, height, turn in degrees, colour index) on the artboard's
  /// 390-wide frame, where each piece comes to rest.
  static const List<(double, double, double, double, double, int)> pieces =
      <(double, double, double, double, double, int)>[
        (28, 120, 14, 8, 18, 0),
        (84, 70, 10, 10, -30, 1),
        (150, 150, 16, 8, 40, 2),
        (210, 60, 8, 14, 12, 3),
        (270, 130, 12, 12, -20, 0),
        (330, 90, 14, 6, 60, 1),
        (350, 200, 8, 8, -45, 2),
        (40, 230, 12, 6, 30, 3),
        (110, 260, 10, 10, -12, 1),
        (300, 250, 8, 14, 22, 0),
        (60, 330, 12, 8, 70, 2),
        (200, 330, 8, 8, -35, 1),
        (340, 340, 14, 8, 15, 3),
        (20, 420, 10, 10, -50, 0),
        (120, 470, 8, 12, 25, 2),
        (250, 440, 12, 12, -15, 1),
        (360, 460, 8, 8, 45, 0),
        (70, 540, 10, 6, 10, 3),
        (300, 560, 12, 8, -60, 2),
        (180, 600, 8, 14, 35, 0),
      ];

  /// How far above its resting place a piece starts.
  static const double drop = 260;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 390;
    final t = Curves.easeOutCubic.transform(progress.clamp(0, 1));
    final edge = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final (i, (x, y, w, h, turn, colour)) in pieces.indexed) {
      // A little stagger, so they do not land as one sheet.
      final lag = (i % 5) * 0.04;
      final fall = ((t - lag) / (1 - lag)).clamp(0.0, 1.0);
      canvas
        ..save()
        ..translate(
          (x + w / 2) * scale,
          (y + h / 2 - drop * (1 - fall)) * scale,
        )
        ..rotate((turn + 90 * (1 - fall)) * math.pi / 180);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: w * scale,
          height: h * scale,
        ),
        const Radius.circular(2),
      );
      final fill = Paint()
        ..color = colours[colour].withValues(alpha: fall == 0 ? 0 : 1);
      canvas
        ..drawRRect(rect, fill)
        ..drawRRect(
          rect,
          edge..color = ink.withValues(alpha: fall == 0 ? 0 : 1),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress;
}
