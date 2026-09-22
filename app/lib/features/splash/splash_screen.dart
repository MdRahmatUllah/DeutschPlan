import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// S1 · Splash. `docs/04-screens/splash.md`, artboards `Splash-android*.html`.
///
/// The composition the native launch screen also draws, so the hand-off from
/// the platform splash to Flutter's first frame shows no jump: Lagoon field,
/// the "D" mark in a Sun speech bubble, the wordmark, and the caption.
///
/// Every colour is a token. The artboards' light and dark values *are* the
/// palette — background `primary`, mark `accent`, rule and text `ink`, the
/// offset `shadow` — which is why this needs no mode switch: reading the
/// tokens produces both artboards.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.showProgress = false});

  /// FR-S1: the progress line appears only once bootstrap has run long enough
  /// to be worth mentioning. [SplashProgressGate] owns the timing; this takes
  /// the answer so the screen itself stays a pure function of its inputs and
  /// can be golden-tested in both states.
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    final body = Column(
      // Stretch, because `Scaffold.body` passes loose horizontal constraints:
      // without it the column shrinks to its widest child and sits against the
      // left edge, and the caption's `TextAlign.center` has no width to centre
      // within. The artboard is centred on the full screen.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // The mark is decorative. A reader that announced "D,
              // DeutschPlan" would say nothing about the wait; the caption
              // below is the screen's actual announcement.
              const ExcludeSemantics(child: _Mark()),
              const SizedBox(height: 40),
              // The line holds its space whether or not it is drawn, so the
              // mark does not jump 3 px when bootstrap crosses the threshold.
              SizedBox(
                height: _SplashMetrics.ruleHeight,
                child: showProgress ? const _ProgressRule() : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          child: DpText(
            l10n.splashPreparing,
            role: DpTextRole.caption,
            textAlign: TextAlign.center,
            // Ink on the solid field, secondary on glass — the artboards
            // differ here because the glass paper is much lighter.
            color: tokens.isGlass ? tokens.color.textSecondary : null,
          ),
        ),
      ],
    );

    // Glass replaces the Lagoon field with the aurora paper, and the mark sits
    // on a blurred panel rather than directly on the colour.
    // A scaffold, not a bare ColoredBox: text needs a Material ancestor or
    // Flutter paints the missing-material debug underline across the wordmark.
    //
    // The field is `primary` directly rather than the theme's paper, because
    // the artboard fills the screen with the Lagoon brand colour. Under glass
    // the aurora is the paper, so the scaffold gets out of its way — the
    // backdrop's own transparent tone rather than a raw `Colors.transparent`,
    // which the theme could not follow.
    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.color.primary,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.primary, child: body)
          : body,
    );
  }
}

/// The measurements the artboards give, in one place.
///
/// Named rather than inline because the native launch screens have to match
/// them exactly — `splash_mark.xml` is a separate file that cannot read Dart,
/// so the numbers it copies need somewhere to be copied *from*.
abstract final class _SplashMetrics {
  static const double bubbleWidth = 120;
  static const double bubbleHeight = 92;
  static const double bubbleRadius = 28;
  static const double markHeight = 104;

  /// The tail sits under the bubble, left of centre.
  static const double tailLeft = 22;
  static const double tailWidth = 24;
  static const double tailHeight = 20;

  static const double letterSize = 60;
  static const double wordmarkSize = 28;
  static const double borderWidth = 3;
  static const double shadowOffset = 3;

  static const double ruleWidth = 120;
  static const double ruleHeight = 3;

  /// How far bootstrap has to run before the line is worth showing.
  static const Duration progressAfter = Duration(milliseconds: 600);
}

/// The "D" in its speech bubble, plus the wordmark.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final mark = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: _SplashMetrics.bubbleWidth,
          height: _SplashMetrics.markHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: _SplashMetrics.tailLeft,
                top: _SplashMetrics.bubbleHeight - _SplashMetrics.borderWidth,
                child: CustomPaint(
                  size: const Size(
                    _SplashMetrics.tailWidth,
                    _SplashMetrics.tailHeight,
                  ),
                  painter: _TailPainter(
                    // On the solid field the tail is drawn in ink, continuing
                    // the bubble's border. On glass there is no border, so it
                    // continues the bubble's fill instead.
                    colour: tokens.isGlass
                        ? tokens.color.accent
                        : tokens.color.ink,
                  ),
                ),
              ),
              Container(
                width: _SplashMetrics.bubbleWidth,
                height: _SplashMetrics.bubbleHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.color.accent,
                  borderRadius: BorderRadius.circular(
                    _SplashMetrics.bubbleRadius,
                  ),
                  border: tokens.isGlass
                      ? null
                      : Border.all(
                          color: tokens.color.ink,
                          width: _SplashMetrics.borderWidth,
                        ),
                  boxShadow: <BoxShadow>[
                    if (tokens.isGlass)
                      BoxShadow(
                        color: tokens.surface.shadow,
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      )
                    else
                      BoxShadow(
                        color: tokens.surface.shadow,
                        offset: const Offset(
                          _SplashMetrics.shadowOffset,
                          _SplashMetrics.shadowOffset,
                        ),
                      ),
                  ],
                ),
                child: _Lockup(
                  'D',
                  size: _SplashMetrics.letterSize,
                  colour: tokens.color.onAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Lockup(
          'DeutschPlan',
          size: _SplashMetrics.wordmarkSize,
          colour: tokens.color.ink,
          letterSpacing: -0.5,
        ),
      ],
    );

    // The wordmark is the product's name, not course content, so it is not in
    // the ARB — translating it would be renaming the app.
    return tokens.isGlass
        ? DpSurface(
            padding: const EdgeInsets.fromLTRB(44, 36, 44, 32),
            radius: _SplashMetrics.bubbleRadius,
            child: mark,
          )
        : mark;
  }
}

/// A piece of the brand lockup.
///
/// `Text` rather than [DpText], and on purpose: the scale is for content, and
/// these two sizes — 60 for the glyph, 28 for the wordmark — are artwork fixed
/// by the artboards. Bending them to the nearest role would move the mark, and
/// the native launch screens have to match it pixel for pixel.
///
/// The Bangla fallback [DpText] exists to enforce does not apply: "D" and
/// "DeutschPlan" are the product's name, in Latin, in every locale.
class _Lockup extends StatelessWidget {
  const _Lockup(
    this.data, {
    required this.size,
    required this.colour,
    this.letterSpacing,
  });

  final String data;
  final double size;
  final Color colour;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) => Text(
    data,
    style: TextStyle(
      fontFamily: AppFonts.latin,
      fontSize: size,
      height: 1,
      letterSpacing: letterSpacing,
      color: colour,
      fontVariations: AppFonts.weight(700),
    ),
  );
}

/// The thin Lagoon rule under the mark.
///
/// Indeterminate: bootstrap cannot say how far through it is — it is opening a
/// database and maybe copying a file — so a percentage would be invented. The
/// artboard shows it part-filled because a still image has to show something.
class _ProgressRule extends StatelessWidget {
  const _ProgressRule();

  /// What the artboard draws: a little under two thirds.
  ///
  /// Used as the *still* value under reduce-motion. A still bar has to show
  /// some progress or it reads as a broken one, and this is the figure the
  /// design already chose.
  static const double restingValue = 0.62;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Indeterminate normally — bootstrap is opening a database and maybe
    // copying a file, and cannot say how far through it is, so a percentage
    // would be invented.
    //
    // Still under reduce-motion (#Y03), which `AuroraBackdrop` already honours
    // and the golden harness relies on. It is also what stops an indefinite
    // animation hanging any `pumpAndSettle` that lands on this screen.
    final still = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      width: _SplashMetrics.ruleWidth,
      height: _SplashMetrics.ruleHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: still ? restingValue : null,
          backgroundColor: tokens.color.ink.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(tokens.color.ink),
          minHeight: _SplashMetrics.ruleHeight,
        ),
      ),
    );
  }
}

/// The speech-bubble tail: a downward triangle.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.colour != colour;
}

/// Shows [SplashScreen] bare, then with its progress line once bootstrap has
/// been running for [_SplashMetrics.progressAfter].
///
/// Separate from the screen so the screen stays a pure function of its inputs:
/// a golden of the progress state should not have to wait 600 ms of real time.
class SplashProgressGate extends StatefulWidget {
  const SplashProgressGate({
    super.key,
    this.after = _SplashMetrics.progressAfter,
  });

  final Duration after;

  @override
  State<SplashProgressGate> createState() => _SplashProgressGateState();
}

class _SplashProgressGateState extends State<SplashProgressGate> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A cancellable timer, not `Future.delayed`. Bootstrap usually wins the
    // race, so this screen is normally gone before the threshold — and a
    // delayed future cannot be cancelled, so it outlives the widget. Guarding
    // with `mounted` stops the setState but leaves the timer pending, which
    // leaks on every fast start and fails any test that checks for it.
    _timer = Timer(widget.after, () => setState(() => _slow = true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SplashScreen(showProgress: _slow);
}
