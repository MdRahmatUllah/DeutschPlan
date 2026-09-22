import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 1 · Welcome. `OnboardingWelcome-android.html`.
///
/// Three promises and one button. The page writes no setting — it is the only
/// one of the five that does not, which is why it has no *Skip*: there is
/// nothing to default.
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key, this.onStart});

  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingShell(
      page: OnboardingPage.welcome,
      headline: l10n.onboardingWelcomeHeadline,
      headerArt: const _RisingChart(),
      primaryLabel: l10n.onboardingWelcomeStart,
      onPrimary: onStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 4),
          _Promise(
            icon: Icons.download_outlined,
            text: l10n.onboardingPromiseOffline,
          ),
          _Promise(
            icon: Icons.shield_outlined,
            text: l10n.onboardingPromiseSteps,
          ),
          _Promise(
            icon: Icons.lock_outline,
            text: l10n.onboardingPromisePrivate,
          ),
        ],
      ),
    );
  }
}

/// One promise: a Sun tile with an icon, and the sentence beside it.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});

  final IconData icon;
  final String text;

  static const double tile = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: tile,
            height: tile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.color.accent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.color.ink, width: 1.5),
            ),
            child: Icon(icon, size: 18, color: tokens.color.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(child: DpText(text, role: DpTextRole.body)),
        ],
      ),
    );
  }
}

/// The dotted rising line with its milestones and a flag at the end.
///
/// A painter rather than an asset: it is drawn in ink and Sun, so it has to
/// follow the theme into dark and glass, and an exported PNG could not.
class _RisingChart extends StatelessWidget {
  const _RisingChart();

  static const Size artboard = Size(390, 120);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return SizedBox(
      height: artboard.height,
      child: CustomPaint(
        painter: _RisingChartPainter(
          line: tokens.color.onPrimary,
          start: tokens.color.accent,
          milestone: tokens.surface.card,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RisingChartPainter extends CustomPainter {
  const _RisingChartPainter({
    required this.line,
    required this.start,
    required this.milestone,
  });

  final Color line;
  final Color start;
  final Color milestone;

  /// The artboard's own points, in its 390 × 120 space. Scaled to whatever
  /// width the phone actually has, so the curve keeps its shape on a tablet.
  static const List<Offset> _points = <Offset>[
    Offset(28, 96),
    Offset(60, 84),
    Offset(92, 92),
    Offset(124, 76),
    Offset(156, 84),
    Offset(188, 66),
    Offset(220, 74),
    Offset(252, 56),
    Offset(284, 62),
    Offset(312, 44),
    Offset(340, 50),
    Offset(366, 30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _RisingChart.artboard.width;
    Offset at(Offset point) => Offset(point.dx * scale, point.dy);

    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Dashed, as the artboard's `stroke-dasharray: 6 8`. Drawn segment by
    // segment because Flutter has no dash support on a path.
    for (var i = 1; i < _points.length; i++) {
      _dashed(canvas, at(_points[i - 1]), at(_points[i]), stroke);
    }

    for (final point in _points) {
      final centre = at(point);
      canvas
        ..drawCircle(
          centre,
          6,
          Paint()..color = point == _points.first ? start : milestone,
        )
        ..drawCircle(centre, 6, stroke);
    }

    // The flag at the summit — the reason the line is going anywhere.
    final tip = at(_points.last);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 14, tip.dy - 8)
        ..lineTo(tip.dx, tip.dy - 14)
        ..lineTo(tip.dx, tip.dy + 8)
        ..lineTo(tip.dx - 14, tip.dy + 14)
        ..close(),
      Paint()..color = start,
    );
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    const gap = 8.0;

    final total = (to - from).distance;
    if (total == 0) return;

    final step = (to - from) / total;
    for (var drawn = 0.0; drawn < total; drawn += dash + gap) {
      final end = (drawn + dash).clamp(0.0, total);
      canvas.drawLine(from + step * drawn, from + step * end, paint);
    }
  }

  @override
  bool shouldRepaint(_RisingChartPainter old) =>
      old.line != line || old.start != start || old.milestone != milestone;
}
