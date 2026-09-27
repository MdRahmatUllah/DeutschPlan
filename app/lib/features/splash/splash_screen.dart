import 'dart:async';

import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_mark.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// S1 · Splash. `docs/04-screens/splash.md`, artboards `Splash-android*.html`,
/// with the brand kit's mark (#602).
///
/// The composition the native launch screen also draws, so the hand-off from
/// the platform splash to Flutter's first frame shows no jump: the Lagoon
/// field and the tiles at the size and place Android 12 draws them, then the
/// wordmark and the caption under them.
///
/// The field is the palette's `primary`, Lagoon in light and lifted in dark,
/// as `colors.xml` paints the native window. The tiles and the wordmark are
/// the kit's own colours in every mode ([SgMark]): the kit sets Ink on Lagoon.
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

    final caption = Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      child: SgText(
        l10n.splashPreparing,
        role: SgTextRole.caption,
        textAlign: TextAlign.center,
        // Ink on the solid field, secondary on glass — the artboards
        // differ here because the glass paper is much lighter.
        // #605: on the solid field, `onPrimary`, the token for what sits on
        // the Lagoon (Ink, as the wordmark), in both modes: the dark page's
        // light ink was about 1.4:1 on the lifted one.
        color: tokens.isGlass
            ? tokens.color.textSecondary
            : tokens.color.onPrimary,
      ),
    );

    // The mark at the screen's centre, where the platform's splash drew it.
    // The scaffold keeps the body above the navigation bar, so the top gives
    // back as much; and the caption's invisible twin over the lockup balances
    // the caption under it (Opacity 0 also keeps it from a screen reader).
    // So the centre is the screen's, and the lockup, scaled down on a screen
    // too short for it, never reaches the caption.
    final body = Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Opacity(opacity: 0, child: caption),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SplashLockup(showProgress: showProgress),
              ),
            ),
          ),
          caption,
        ],
      ),
    );

    // Glass replaces the Lagoon field with the aurora paper, and the mark
    // takes its Lagoon square, the kit's form for any other ground.
    // A scaffold, not a bare ColoredBox: the screen's text needs a Material
    // ancestor or Flutter paints the missing-material debug underline.
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

/// S1's centred column: the mark, the wordmark, the gap under it, and the
/// progress line's slot — with as much empty space above the mark as hangs
/// under it, so the mark is the column's centre.
///
/// Public because the iOS launch image is this widget, rendered (#238). The
/// slot is empty until [showProgress], so the image carries the same space
/// under the mark, and the storyboard centres the mark where S1 does.
class SplashLockup extends StatelessWidget {
  const SplashLockup({super.key, this.showProgress = false});

  final bool showProgress;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const SizedBox(height: _SplashMetrics.underMark),
      // The mark is decorative. A reader that announced "Sogda" would say
      // nothing about the wait; the caption is the screen's announcement.
      const ExcludeSemantics(child: SplashMark()),
      const SizedBox(height: _SplashMetrics.ruleGap),
      // The line holds its space whether or not it is drawn, so the mark does
      // not jump 3 px when bootstrap crosses the threshold.
      SizedBox(
        height: _SplashMetrics.ruleHeight,
        // Its own layer: the indeterminate bar animates every frame, and
        // would otherwise repaint the mark and the wordmark with it.
        child: showProgress
            ? const RepaintBoundary(child: _ProgressRule())
            : null,
      ),
    ],
  );
}

/// The measurements, in one place.
///
/// Named rather than inline because the native launch screens have to match
/// them — `splash_icon.xml` and `splash_mark.xml` cannot read Dart, so the
/// numbers they copy need somewhere to be copied *from*.
abstract final class _SplashMetrics {
  /// The mark's square. Android 12 draws its splash icon's 108 grid on 288 dp;
  /// the kit's lockup framing (1.32×) reaches that scale in this square, so
  /// the tiles here are the platform's, dp for dp.
  static const double markSize = 288 / 1.32;

  /// The kit's stacked lockup (`svg/lockup-stacked-tiles-light.svg`) sets the
  /// wordmark at 84 under a 200 square, its cap height 18.7 below it.
  static const double _kit = markSize / 200;
  static const double wordmarkSize = 84 * _kit;
  static const double wordmarkGap = 18.7 * _kit;

  static const double ruleGap = 40;
  static const double ruleWidth = 120;
  static const double ruleHeight = 3;

  /// All that hangs under the mark, repeated over it to centre it.
  static const double underMark =
      wordmarkGap + SgWordmark.height * wordmarkSize + ruleGap + ruleHeight;

  /// How far bootstrap has to run before the line is worth showing.
  static const Duration progressAfter = Duration(milliseconds: 600);
}

/// The kit's stacked lockup: the tiles over the wordmark.
///
/// On the Lagoon field the square is the field itself, so only the tiles are
/// drawn; on glass the aurora is the ground, and the mark takes its square.
///
/// Public because S1's error state (#86) draws the same mark: the learner is
/// looking at the splash when bootstrap fails, and keeping the mark is what
/// stops the failure reading as a crash into a different app.
class SplashMark extends StatelessWidget {
  const SplashMark({super.key, this.scale = 1});

  /// S1's size times this. The error state draws it smaller, so the message
  /// and its actions reach above the fold on a small phone.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final size = _SplashMetrics.markSize * scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (tokens.isGlass) SgMark.appIcon(size: size) else SgMark(size: size),
        SizedBox(height: _SplashMetrics.wordmarkGap * scale),
        SgWordmark(
          fontSize: _SplashMetrics.wordmarkSize * scale,
          colour: tokens.isGlass ? tokens.color.ink : SgBrand.ink,
        ),
      ],
    );
  }
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
    // #605: on the solid field, `onPrimary` over the light track (Ink at
    // 47 %), in both modes, as the caption: the field is always a Lagoon.
    // Under glass, the page's own.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onPrimary;
    final track = tokens.isGlass
        ? tokens.surface.track
        : SgSurfaceTokens.light.track;

    return SizedBox(
      width: _SplashMetrics.ruleWidth,
      height: _SplashMetrics.ruleHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: still ? restingValue : null,
          // What is not done yet reaches 3:1 on the paper (#437, #449).
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation<Color>(ink),
          minHeight: _SplashMetrics.ruleHeight,
        ),
      ),
    );
  }
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
