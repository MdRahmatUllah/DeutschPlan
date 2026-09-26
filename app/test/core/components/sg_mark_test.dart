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
  /// One tile's four rounded rects, in order: its shadow filled and edged in
  /// ink, then its face and its ink edge. `paints` checks each drawRRect in
  /// turn, so every one is listed.
  PaintPattern tile(PaintPattern pattern, Color face) => pattern
    ..rrect(color: SgBrand.ink, style: PaintingStyle.fill)
    ..rrect(color: SgBrand.ink, style: PaintingStyle.stroke)
    ..rrect(color: face, style: PaintingStyle.fill)
    ..rrect(color: SgBrand.ink, style: PaintingStyle.stroke)
    ..paragraph();

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

  testWidgets('FR-S1-01 #602 the tiles: the Paper "a" behind the Sun "Ä", '
      'each over its ink shadow, and no square', (tester) async {
    await pump(tester, const SgMark(size: 108));

    expect(find.byType(SgMark), tile(tile(paints, SgBrand.paper), SgBrand.sun));
    expect(find.byType(SgMark), isNot(paints..rrect(color: SgBrand.lagoon)));
  });

  testWidgets('FR-M9-01 #602 the app icon puts them on the Lagoon square', (
    tester,
  ) async {
    await pump(tester, const SgMark.appIcon(size: 60));

    expect(
      find.byType(SgMark),
      tile(
        tile(paints..rrect(color: SgBrand.lagoon), SgBrand.paper),
        SgBrand.sun,
      ),
    );
  });

  testWidgets('FR-S1-01 #602 the kit never recolours the tiles: dark and '
      'glass draw the same', (tester) async {
    for (final theme in <ThemeData>[AppTheme.dark(), AppTheme.glass()]) {
      await pump(tester, const SgMark.appIcon(size: 60), theme: theme);

      expect(
        find.byType(SgMark),
        tile(
          tile(paints..rrect(color: SgBrand.lagoon), SgBrand.paper),
          SgBrand.sun,
        ),
      );
    }
  });

  testWidgets('FR-S1-01 #602 the mark is decorative: a reader passes over it, '
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
}
