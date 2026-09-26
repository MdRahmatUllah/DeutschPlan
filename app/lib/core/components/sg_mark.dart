import 'dart:math' as math;

import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/typography/app_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// The Sogda mark: variant A of the brand kit (`docs/sogda-brand-kit/`, #602),
/// two letter tiles, the "a" the learner knows behind and the new language's
/// "Ä" in front.
///
/// Drawn rather than shipped as a picture: the app has no SVG renderer, and a
/// PNG is blurred at one size and wasted at another. The geometry is the
/// kit's `svg/icon-tiles-foreground.svg` on its 108 grid, framed as the kit's
/// lockups frame it (1.32× about (54, 56)), so the tiles fill a [size] square
/// the way they fill the lockup's Lagoon square. The colours are the kit's in
/// every mode ([SgBrand]): the kit never recolours the tiles.
///
/// Decorative: the name is always beside it, or the screen says what it is.
class SgMark extends StatelessWidget {
  /// The tiles alone, for a Lagoon ground: S1's field.
  const SgMark({required this.size, super.key}) : square = false;

  /// The app icon: the tiles on their Lagoon rounded square, the kit's form
  /// for any other ground.
  const SgMark.appIcon({required this.size, super.key}) : square = true;

  /// The square's edge, in logical pixels.
  final double size;

  /// Whether the Lagoon square is drawn under the tiles.
  final bool square;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _TilesPainter(square: square),
    ),
  );
}

/// "Sogda" as the kit sets it: Inter ExtraBold at optical size 32, tracked
/// −2 %.
///
/// Painted, not a text widget: it is artwork, so it keeps its size at any text
/// scale, and its box runs from the cap height to the "g"'s descender, the
/// lines the kit's lockups measure their spacing from.
class SgWordmark extends StatelessWidget {
  const SgWordmark({required this.fontSize, required this.colour, super.key});

  /// The product's name. Not in the ARB: translating it would rename the app.
  static const String name = 'Sogda';

  /// Inter's cap height and the "g"'s descender, in ems (1490 and 432 of its
  /// 2048 units).
  static const double capHeight = 1490 / 2048;
  static const double descender = 432 / 2048;

  /// The wordmark's advance with its tracking, in ems: the kit's 247.8 at 84.
  static const double width = 2.95;

  /// The box's height, in ems.
  static const double height = capHeight + descender;

  final double fontSize;
  final Color colour;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width * fontSize, height * fontSize),
    painter: _WordmarkPainter(fontSize: fontSize, colour: colour),
  );
}

/// The two tiles, on the kit's 108 grid.
class _TilesPainter extends CustomPainter {
  const _TilesPainter({required this.square});

  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 108);
    if (square) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, 108, 108, const Radius.circular(22)),
        Paint()..color = SgBrand.lagoon,
      );
    }
    canvas
      ..translate(54, 56)
      ..scale(1.32)
      ..translate(-54, -56);
    // The letters are Inter at the kit's glyph heights, on its baselines.
    _tile(
      canvas,
      centre: const Offset(44.5, 49.5),
      degrees: -10,
      fill: SgBrand.paper,
      letter: 'a',
      fontSize: 28,
      baseline: 7.24,
    );
    _tile(
      canvas,
      centre: const Offset(62.5, 59.5),
      degrees: 7,
      fill: SgBrand.sun,
      letter: 'Ä',
      fontSize: 20.6,
      baseline: 10.25,
    );
  }

  /// One tile: 28 square, corners 5.5, a 2.6 ink edge with round joins, and
  /// the hard ink shadow 2.4 down and right in the tile's own frame.
  void _tile(
    Canvas canvas, {
    required Offset centre,
    required double degrees,
    required Color fill,
    required String letter,
    required double fontSize,
    required double baseline,
  }) {
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(degrees * math.pi / 180);
    final tile = RRect.fromLTRBR(-14, -14, 14, 14, const Radius.circular(5.5));
    final shadow = tile.shift(const Offset(2.4, 2.4));
    final edge = Paint()
      ..color = SgBrand.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawRRect(shadow, Paint()..color = SgBrand.ink)
      ..drawRRect(shadow, edge)
      ..drawRRect(tile, Paint()..color = fill)
      ..drawRRect(tile, edge);
    _paintText(
      canvas,
      letter,
      fontSize: fontSize,
      colour: SgBrand.ink,
      centreX: 0,
      baseline: baseline,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TilesPainter oldDelegate) => oldDelegate.square != square;
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter({required this.fontSize, required this.colour});

  final double fontSize;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) => _paintText(
    canvas,
    SgWordmark.name,
    fontSize: fontSize,
    colour: colour,
    centreX: size.width / 2,
    baseline: SgWordmark.capHeight * fontSize,
    letterSpacing: -0.02 * fontSize,
  );

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      oldDelegate.fontSize != fontSize || oldDelegate.colour != colour;
}

/// Paints [text] in Inter ExtraBold at optical size 32, centred on [centreX]
/// with its baseline on [baseline]. Never scaled with the text size: the
/// painter's own scaler is none.
void _paintText(
  Canvas canvas,
  String text, {
  required double fontSize,
  required Color colour,
  required double centreX,
  required double baseline,
  double letterSpacing = 0,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppFonts.latin,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
        color: colour,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 800),
          FontVariation('opsz', 32),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final top =
      baseline -
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter
    ..paint(canvas, Offset(centreX - painter.width / 2, top))
    ..dispose();
}
