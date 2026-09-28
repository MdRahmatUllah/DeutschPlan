import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/typography/app_fonts.dart';

/// The Sogda mark: variant A of the brand kit (`docs/sogda-brand-kit/`, #602),
/// two letter tiles, the "a" the learner knows behind and the new language's
/// "Ä" in front.
///
/// Drawn rather than shipped as a picture: the app has no SVG renderer, and a
/// PNG is blurred at one size and wasted at another. The geometry is the
/// kit's `svg/icon-tiles-foreground.svg` on its 108 grid, letters included:
/// they are the kit's own outlines, not a font, so the logo has one
/// letterform on the launcher, the native splash and here. It is framed as
/// the kit's lockups frame it (1.32× about (54, 56)), so the tiles fill a
/// [size] square the way they fill the lockup's Lagoon square. The colours
/// are the kit's in every mode ([SgBrand]): the kit never recolours the tiles.
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

  /// SVG path data as a [Path]: the absolute M, L, H, V, Q and Z the kit's
  /// letters use, with a command's numbers repeating it (pairs after an M
  /// are lines). Anything else is not the kit's, and throws.
  @visibleForTesting
  static Path pathFromSvg(String data) {
    final tokens = RegExp(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)')
        .allMatches(data)
        .map((match) => match[0]!)
        .toList();
    final path = Path();
    var at = 0;
    String? command;
    var x = 0.0;
    var y = 0.0;
    double next() => double.parse(tokens[at++]);

    while (at < tokens.length) {
      if (RegExp('[A-Za-z]').hasMatch(tokens[at])) {
        command = tokens[at++];
        if (command == 'Z') {
          path.close();
          continue;
        }
      }
      switch (command) {
        case 'M':
          path.moveTo(x = next(), y = next());
          command = 'L';
        case 'L':
          path.lineTo(x = next(), y = next());
        case 'H':
          path.lineTo(x = next(), y);
        case 'V':
          path.lineTo(x, y = next());
        case 'Q':
          final cx = next();
          final cy = next();
          path.quadraticBezierTo(cx, cy, x = next(), y = next());
        default:
          throw FormatException('an SVG command the kit does not use', data);
      }
    }
    return path;
  }

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

  /// The kit's letters, in their font's units (y up): parsed once.
  static final Path _a = SgMark.pathFromSvg(
    'M326 559Q429 559 485.5 509.0Q542 459 542 363V0H425L392 74H388Q353 29 '
    '314.0 9.5Q275 -10 206 -10Q134 -10 86.0 33.0Q38 76 38 165Q38 252 100.0 '
    '295.0Q162 338 282 343L373 346V359Q373 402 353.0 420.0Q333 438 297 '
    '438Q262 438 222.5 426.0Q183 414 144 397L95 510Q140 534 198.0 546.5Q256 '
    '559 326 559ZM323 248Q260 245 235.0 226.5Q210 208 210 173Q210 141 228.0 '
    '126.5Q246 112 275 112Q316 112 345.0 137.0Q374 162 374 206V250Z',
  );
  static final Path _aUmlaut = SgMark.pathFromSvg(
    'M521 0 476 152H233L187 0H0L243 717H463L708 0ZM397 432Q392 448 383.5 '
    '481.0Q375 514 366.5 548.0Q358 582 354 604Q349 581 341.5 548.5Q334 516 '
    '326.0 484.5Q318 453 312 432L271 294H438ZM165 853Q165 890 187.0 907.0Q209 '
    '924 241 924Q271 924 294.0 907.0Q317 890 317 853Q317 817 294.0 800.0Q271 '
    '783 241 783Q209 783 187.0 800.0Q165 817 165 853ZM390 853Q390 890 411.5 '
    '907.0Q433 924 466 924Q496 924 519.0 907.0Q542 890 542 853Q542 817 519.0 '
    '800.0Q496 783 466 783Q433 783 411.5 800.0Q390 817 390 853Z',
  );

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
    // Each letter as the SVG places it: translate, then scale with y flipped.
    _tile(
      canvas,
      centre: const Offset(44.5, 49.5),
      degrees: -10,
      fill: SgBrand.paper,
      letter: _a,
      origin: const Offset(-7.64, 7.24),
      scale: 0.0264,
    );
    _tile(
      canvas,
      centre: const Offset(62.5, 59.5),
      degrees: 7,
      fill: SgBrand.sun,
      letter: _aUmlaut,
      origin: const Offset(-7.47, 10.25),
      scale: 0.0211,
    );
  }

  /// One tile: 28 square, corners 5.5, a 2.6 ink edge with round joins, the
  /// hard ink shadow 2.4 down and right in the tile's own frame, and its
  /// letter.
  void _tile(
    Canvas canvas, {
    required Offset centre,
    required double degrees,
    required Color fill,
    required Path letter,
    required Offset origin,
    required double scale,
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
      ..drawRRect(tile, edge)
      ..translate(origin.dx, origin.dy)
      ..scale(scale, -scale)
      ..drawPath(letter, Paint()..color = SgBrand.ink)
      ..restore();
  }

  @override
  bool shouldRepaint(_TilesPainter oldDelegate) => oldDelegate.square != square;
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter({required this.fontSize, required this.colour});

  final double fontSize;
  final Color colour;

  /// Centred, its baseline on the cap height. The painter's scaler is none,
  /// so the learner's text size never reaches it.
  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: SgWordmark.name,
        style: TextStyle(
          fontFamily: AppFonts.latin,
          fontSize: fontSize,
          letterSpacing: -0.02 * fontSize,
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
        SgWordmark.capHeight * fontSize -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter
      ..paint(canvas, Offset((size.width - painter.width) / 2, top))
      ..dispose();
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      oldDelegate.fontSize != fontSize || oldDelegate.colour != colour;
}
