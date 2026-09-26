import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/services/start_report.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 1 · Welcome. `OnboardingWelcome-android.html`.
///
/// Three promises and one button. The page writes no setting — it is the only
/// one of the five that does not, which is why it has no *Skip*: there is
/// nothing to default.
class OnboardingWelcomePage extends StatefulWidget {
  const OnboardingWelcomePage({super.key, this.onStart});

  final VoidCallback? onStart;

  @override
  State<OnboardingWelcomePage> createState() => _OnboardingWelcomePageState();
}

class _OnboardingWelcomePageState extends State<OnboardingWelcomePage> {
  @override
  void initState() {
    super.initState();
    // #462: a first run's cold start ends here, drawn with its first frame.
    StartReport.fullyDrawn();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingShell(
      page: OnboardingPage.welcome,
      headline: l10n.onboardingWelcomeHeadline,
      headerArt: const _RisingChart(),
      primaryLabel: l10n.onboardingWelcomeStart,
      onPrimary: widget.onStart,
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
          // The header's ink, so the line stays visible under glass-dark.
          line: OnboardingPage.welcome.headerInk(tokens),
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

  /// The artboard's milestones, in its 390 × 120 space. They sit near the
  /// wave rather than on it — the artboard places them by hand.
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

  /// The artboard's wave: `M28 96C50 60 70 110 92 92s40-40 64-16 40 30 64-10
  /// 44 20 64-10 50 0 84-26`, with each `s` written out as the `C` it
  /// abbreviates — its first control point is the previous second one,
  /// reflected through the join.
  static Path get _wave => Path()
    ..moveTo(28, 96)
    ..cubicTo(50, 60, 70, 110, 92, 92)
    ..cubicTo(114, 74, 132, 52, 156, 76)
    ..cubicTo(180, 100, 196, 106, 220, 66)
    ..cubicTo(244, 26, 264, 86, 284, 56)
    ..cubicTo(304, 26, 334, 56, 368, 30);

  @override
  void paint(Canvas canvas, Size size) {
    // Stretched across, not scaled: the block is 120 tall at every width, so
    // on a tablet the wave widens and the dots keep their size.
    final scale = size.width / _RisingChart.artboard.width;
    final stretch = Matrix4.diagonal3Values(scale, 1, 1).storage;
    Offset at(Offset point) => Offset(point.dx * scale, point.dy);

    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // `stroke-dasharray: 6 8`, measured along the stretched curve so the
    // dashes stay 6 dp long whatever the width. Flutter has no dashed stroke;
    // `PathMetric.extractPath` is the stock way to cut one.
    for (final metric in _wave.transform(stretch).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6 + 8) {
        canvas.drawPath(metric.extractPath(d, d + 6), stroke);
      }
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

    // The flag at the summit: `M352 22l14-6v22l-14 6z`, which puts it just
    // behind the last dot. Anchored to that dot rather than stretched, so it
    // stays a flag on a tablet instead of widening into a banner.
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

  @override
  bool shouldRepaint(_RisingChartPainter old) =>
      old.line != line || old.start != start || old.milestone != milestone;
}
