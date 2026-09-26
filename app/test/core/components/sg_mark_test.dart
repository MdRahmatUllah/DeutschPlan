import 'package:sogda/core/components/sg_mark.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Sogda mark (#602): the brand kit's tiles, drawn in Flutter. The goldens
/// of S1, About and the reminder's preview show it; this is what they can't
/// say plainly: the order of the tiles, the kit's fixed colours in every
/// theme, and that a screen reader passes over it.
void main() {
  /// One tile, in order: its shadow filled and edged in ink, its face and ink
  /// edge, then its letter in ink. `paints` checks each drawRRect in turn, so
  /// every one is listed. The letter is the kit's outline in its font's units,
  /// where [inked] points are ink and [clear] points are not.
  PaintPattern tile(
    PaintPattern pattern,
    Color face, {
    required List<Offset> inked,
    required List<Offset> clear,
  }) => pattern
    ..rrect(color: SgBrand.ink, style: PaintingStyle.fill)
    ..rrect(color: SgBrand.ink, style: PaintingStyle.stroke)
    ..rrect(color: face, style: PaintingStyle.fill)
    ..rrect(color: SgBrand.ink, style: PaintingStyle.stroke)
    ..path(color: SgBrand.ink, includes: inked, excludes: clear);

  /// The Paper "a" behind the Sun "Ä", over whatever [pattern] has drawn.
  PaintPattern tiles(PaintPattern pattern) => tile(
    tile(
      pattern,
      SgBrand.paper,
      // The "a"'s stem and bowl, not its counter nor where an umlaut would be.
      inked: const <Offset>[Offset(480, 150), Offset(120, 165)],
      clear: const <Offset>[Offset(290, 180), Offset(241, 853)],
    ),
    SgBrand.sun,
    // Both dots and a leg; not the A's counter nor the gap between the dots.
    inked: const <Offset>[Offset(241, 853), Offset(466, 853), Offset(120, 100)],
    clear: const <Offset>[Offset(354, 360), Offset(354, 853)],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget mark, {
    ThemeData? theme,
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Center(child: mark),
      ),
    ),
  );

  testWidgets('#602 the tiles: the Paper "a" behind the Sun "Ä", each over '
      'its ink shadow, the kit’s letters, and no square', (tester) async {
    await pump(tester, const SgMark(size: 108));

    expect(find.byType(SgMark), tiles(paints));
    expect(find.byType(SgMark), isNot(paints..rrect(color: SgBrand.lagoon)));
  });

  testWidgets('#602 the app icon puts them on the Lagoon square', (
    tester,
  ) async {
    await pump(tester, const SgMark.appIcon(size: 60));

    expect(find.byType(SgMark), tiles(paints..rrect(color: SgBrand.lagoon)));
  });

  testWidgets('#602 the kit never recolours the tiles: dark and '
      'glass draw the same', (tester) async {
    for (final theme in <ThemeData>[AppTheme.dark(), AppTheme.glass()]) {
      await pump(tester, const SgMark.appIcon(size: 60), theme: theme);

      expect(find.byType(SgMark), tiles(paints..rrect(color: SgBrand.lagoon)));
    }
  });

  testWidgets('#602 the mark is decorative: a reader passes over it, '
      'in both forms', (tester) async {
    for (final mark in const <SgMark>[
      SgMark(size: 60),
      SgMark.appIcon(size: 60),
    ]) {
      await pump(tester, mark);

      final exclude = tester.widget<ExcludeSemantics>(
        find.descendant(
          of: find.byType(SgMark),
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(exclude.excluding, isTrue);
    }
  });

  testWidgets('#602 it keeps its size at 200 % text: it is the logo', (
    tester,
  ) async {
    await pump(tester, const SgMark.appIcon(size: 36), textScale: 2);

    expect(tester.getSize(find.byType(SgMark)), const Size.square(36));
  });

  group('#602 the kit’s path data', () {
    test('an M, lines, an H and a V make a square', () {
      final square = SgMark.pathFromSvg('M0 0L10 0V10H0Z');

      expect(square.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
      expect(square.contains(const Offset(5, 5)), isTrue);
    });

    test('pairs after an M are lines', () {
      final triangle = SgMark.pathFromSvg('M0 0 10 0 10 10Z');

      expect(triangle.contains(const Offset(8, 2)), isTrue);
      expect(triangle.contains(const Offset(2, 8)), isFalse);
    });

    test('a Q curves through its control point, and repeats', () {
      final arch = SgMark.pathFromSvg('M0 0Q10 10 20 0Q30 -10 40 0Z');

      expect(arch.contains(const Offset(10, 4)), isTrue);
      expect(arch.contains(const Offset(10, 6)), isFalse);
      expect(arch.contains(const Offset(30, -4)), isTrue);
    });

    test('the kit’s "a" spans its outline', () {
      final a = SgMark.pathFromSvg(
        'M326 559Q429 559 485.5 509.0Q542 459 542 363V0H425L392 74H388Q353 29 '
        '314.0 9.5Q275 -10 206 -10Q134 -10 86.0 33.0Q38 76 38 165Q38 252 100.0 '
        '295.0Q162 338 282 343L373 346V359Q373 402 353.0 420.0Q333 438 297 '
        '438Q262 438 222.5 426.0Q183 414 144 397L95 510Q140 534 198.0 546.5Q256 '
        '559 326 559ZM323 248Q260 245 235.0 226.5Q210 208 210 173Q210 141 228.0 '
        '126.5Q246 112 275 112Q316 112 345.0 137.0Q374 162 374 206V250Z',
      );

      expect(a.getBounds(), const Rect.fromLTRB(38, -10, 542, 559));
    });

    test('a command the kit does not use is refused', () {
      expect(
        () => SgMark.pathFromSvg('M0 0C1 1 2 2 3 3Z'),
        throwsFormatException,
      );
    });
  });
}
