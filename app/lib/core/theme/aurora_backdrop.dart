import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/sg_tokens.dart';

/// One drifting colour blob.
///
/// Positions, radii and stops are read off the Aurora Glass artboards, which
/// draw the same four on every screen:
///
/// ```css
/// radial-gradient(circle 340px at 16% 12%, rgba(0,194,178,0.55) 0%,
///                 …0.396 32%, …0.154 58%, transparent 78%)
/// ```
@immutable
class AuroraBlob {
  const AuroraBlob({
    required this.radius,
    required this.centre,
    required this.role,
  });

  /// CSS `circle <n>px` is a radius, so the drawn diameters are 680, 540, 620
  /// and 500 — the 400–700 dp range `theming.md` describes.
  final double radius;

  /// Fractional position within the backdrop.
  final Alignment centre;

  /// Which palette colour this blob takes.
  final AuroraRole role;

  /// The four the artboards draw, in their painting order.
  static const List<AuroraBlob> defaults = <AuroraBlob>[
    AuroraBlob(
      radius: 340,
      centre: Alignment(-0.68, -0.76),
      role: AuroraRole.lagoon,
    ),
    AuroraBlob(
      radius: 270,
      centre: Alignment(0.8, -0.32),
      role: AuroraRole.sun,
    ),
    AuroraBlob(
      radius: 310,
      centre: Alignment(0.56, 0.8),
      role: AuroraRole.raspberry,
    ),
    AuroraBlob(
      radius: 250,
      centre: Alignment(-0.88, 0.44),
      role: AuroraRole.cobalt,
    ),
  ];
}

/// The palette slot a blob takes. Named by role rather than by colour so the
/// dark variant substitutes automatically.
enum AuroraRole { lagoon, sun, raspberry, cobalt }

extension AuroraRoleColour on AuroraRole {
  Color from(SgPalette palette) => switch (this) {
    AuroraRole.lagoon => palette.primary,
    AuroraRole.sun => palette.accent,
    AuroraRole.raspberry => palette.die,
    AuroraRole.cobalt => palette.der,
  };
}

/// The drifting colour backdrop the glass theme sits on.
///
/// `docs/01-architecture/theming.md`: "3–4 radial blobs (400–700 dp) in Lagoon,
/// Sun, Raspberry, Cobalt, rendered once to an image and translated on 18–24 s
/// loops (≈ 20 dp travel). The leading blob takes the current tab's colour…
/// Drift pauses under reduced motion, when backgrounded, and in fallback mode."
///
/// Each blob is painted inside its own `RepaintBoundary` whose painter never
/// invalidates, so the gradients are rasterised once and only a transform
/// changes per frame. That is what makes four large radial gradients affordable
/// under a scrolling list.
///
/// #709: every drift step makes each glass panel on screen blur again, so the
/// drift steps [stepsPerSecond] times a second, not at 60 fps; a step is under
/// half a dp, too little to see. The screen sits in a `RepaintBoundary` of its
/// own, so a step repaints the blobs and not the screen. Its panels in a list
/// draw over the blobs with no blur of their own (`SgSurface`).
class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({
    required this.child,
    super.key,
    this.leading,
    this.blobs = AuroraBlob.defaults,
  });

  final Widget child;

  /// Tints the first blob. `theming.md` gives each tab its colour — Today
  /// Lagoon, Learn Sun, Search Raspberry, Me Cobalt — and a study session
  /// shifts it toward the current noun's gender colour.
  final Color? leading;

  final List<AuroraBlob> blobs;

  /// Roughly 20 dp of travel, as the spec describes.
  static const double travel = 20;

  /// The loop range. Each blob takes a different period so they never line up
  /// into a single visible pulse.
  static const Duration minimumPeriod = Duration(seconds: 18);
  static const Duration maximumPeriod = Duration(seconds: 24);

  /// How often the drift moves while it runs (#709).
  static const int stepsPerSecond = 15;

  /// The time between two steps.
  static const Duration step = Duration(
    microseconds: Duration.microsecondsPerSecond ~/ stepsPerSecond,
  );

  static Duration periodFor(int index, int count) {
    if (count <= 1) return minimumPeriod;
    final span = maximumPeriod.inMilliseconds - minimumPeriod.inMilliseconds;
    return Duration(
      milliseconds:
          minimumPeriod.inMilliseconds + (span * index ~/ (count - 1)),
    );
  }

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with WidgetsBindingObserver {
  /// How far the drift has run. A step at a time, and kept through a pause,
  /// so the blobs go on from where they stopped.
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );

  /// Steps the drift while it runs. A timer, not a ticker: a ticker asks for
  /// a frame every vsync whether anything moved or not (#709).
  Timer? _drift;

  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nothing is visible when the app is backgrounded, so the drift is pure
    // battery cost.
    final backgrounded = state != AppLifecycleState.resumed;
    if (backgrounded == _backgrounded) return;
    setState(() => _backgrounded = backgrounded);
    _syncDrift();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drift?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  /// Every reason the aurora holds still.
  bool get _still =>
      _backgrounded ||
      MediaQuery.disableAnimationsOf(context) ||
      !GlassCapabilityScope.blurAllowed(context);

  /// True only when there is something moving to look at. Outside glass the
  /// widget paints nothing, so a running drift would be frames scheduled for
  /// an invisible animation — battery for nothing in the two modes most
  /// people use. A screen under another one (a tab in the background, a page
  /// pushed over it) is muted as a ticker would be.
  bool get _shouldDrift =>
      context.tokens.isGlass && !_still && TickerMode.valuesOf(context).enabled;

  /// Driven from the lifecycle hooks rather than from `build`: starting and
  /// stopping a timer is a side-effect, and `build` runs for reasons that have
  /// nothing to do with the aurora.
  void _syncDrift() {
    if (!_shouldDrift) {
      _drift?.cancel();
      _drift = null;
    } else {
      _drift ??= Timer.periodic(
        AuroraBackdrop.step,
        (_) => _elapsed.value += AuroraBackdrop.step,
      );
    }
  }

  @override
  void didChangeDependencies() {
    // The theme, the MediaQuery, the ticker mode and the capability scope all
    // arrive here.
    super.didChangeDependencies();
    _syncDrift();
  }

  @override
  void didUpdateWidget(AuroraBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDrift();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Outside glass there is no aurora at all — the solid modes have paper.
    if (!tokens.isGlass) return widget.child;

    final count = widget.blobs.length;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: tokens.surface.paper),
        for (final (index, blob) in widget.blobs.indexed)
          _DriftingBlob(
            blob: blob,
            elapsed: _elapsed,
            period: AuroraBackdrop.periodFor(index, count),
            still: _still,
            colour: index == 0 && widget.leading != null
                ? widget.leading!
                : blob.role.from(tokens.color),
            peak: tokens.surface.auroraOpacity,
          ),
        RepaintBoundary(child: widget.child),
      ],
    );
  }
}

class _DriftingBlob extends StatelessWidget {
  const _DriftingBlob({
    required this.blob,
    required this.elapsed,
    required this.period,
    required this.still,
    required this.colour,
    required this.peak,
  });

  final AuroraBlob blob;
  final ValueNotifier<Duration> elapsed;

  /// One loop of this blob's circle.
  final Duration period;
  final bool still;
  final Color colour;
  final double peak;

  @override
  Widget build(BuildContext context) {
    // The painted layer is built once; only the offset below changes per step,
    // so the gradient is rasterised once and reused.
    final painted = RepaintBoundary(
      child: CustomPaint(
        painter: _BlobPainter(blob: blob, colour: colour, peak: peak),
        size: Size.infinite,
      ),
    );

    if (still) return painted;

    return AnimatedBuilder(
      animation: elapsed,
      builder: (context, child) {
        final angle =
            elapsed.value.inMicroseconds / period.inMicroseconds * 2 * math.pi;
        return Transform.translate(
          offset: Offset(
            math.cos(angle) * AuroraBackdrop.travel,
            math.sin(angle) * AuroraBackdrop.travel,
          ),
          child: child,
        );
      },
      child: painted,
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter({
    required this.blob,
    required this.colour,
    required this.peak,
  });

  final AuroraBlob blob;
  final Color colour;
  final double peak;

  /// The artboard's stops: full, 72 % of peak, 28 % of peak, transparent —
  /// at 0 %, 32 %, 58 % and 78 % of the radius.
  static const List<double> _stops = <double>[0, 0.32, 0.58, 0.78];
  static const List<double> _opacityRatios = <double>[1, 0.72, 0.28, 0];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = blob.centre.alongSize(size);
    final rect = Rect.fromCircle(center: centre, radius: blob.radius);

    final paint = Paint()
      ..shader = RadialGradient(
        stops: _stops,
        colors: <Color>[
          for (final ratio in _opacityRatios)
            colour.withValues(alpha: peak * ratio),
        ],
      ).createShader(rect);

    // Only where the blob can actually contribute. Painting the full screen
    // four times is four full-screen blends under every BackdropFilter, and
    // "glass list scroll: 60 fps" is the tightest budget in
    // accessibility-performance.md. #167 owns measuring it.
    canvas.drawRect(rect.intersect(Offset.zero & size), paint);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.colour != colour || old.peak != peak || old.blob != blob;
}
