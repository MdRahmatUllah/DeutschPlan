import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// theming.md: "Every card, sheet, header and tab bar is drawn by one widget,
/// `DpSurface`... Because screens only use `DpSurface`, adding the glass mode
/// did not change a single screen file. Keep it that way."
///
/// These tests hold that promise: the same widget, unchanged, must produce the
/// solid treatment in light and dark and the frosted one under glass.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ThemeData theme, {
    DpSurfaceKind kind = DpSurfaceKind.card,
    bool pressed = false,
    bool selected = false,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: DpSurface(
              kind: kind,
              pressed: pressed,
              selected: selected,
              onTap: onTap,
              padding: const EdgeInsets.all(16),
              child: const Text('Revise'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    final boxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(DpSurface),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toList();
    return boxes.first.decoration as BoxDecoration;
  }

  group('solid modes (Paper & Ink, Night Ink)', () {
    for (final (name, theme, tokens) in <(String, ThemeData, DpTokens)>[
      ('light', AppTheme.light(), DpTokens.light()),
      ('dark', AppTheme.dark(), DpTokens.dark()),
    ]) {
      testWidgets('$name draws fill, outline and the hard offset shadow', (
        tester,
      ) async {
        await pump(tester, theme);
        final d = decorationOf(tester);

        expect(d.color, tokens.surface.card);
        expect(
          (d.border! as Border).top.width,
          tokens.surface.outlineWidth,
          reason: 'theming.md specifies a 1.5 px outline in the solid modes',
        );
        expect((d.border! as Border).top.color, tokens.surface.outline);

        expect(d.boxShadow, hasLength(1));
        expect(d.boxShadow!.single.offset, const Offset(3, 3));
        expect(
          d.boxShadow!.single.blurRadius,
          0,
          reason: 'the offset shadow is hard — no blur, no spread',
        );
        expect(d.boxShadow!.single.color, tokens.surface.shadow);
      });

      testWidgets('$name uses no BackdropFilter', (tester) async {
        await pump(tester, theme);
        expect(
          find.descendant(
            of: find.byType(DpSurface),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason: 'blur belongs to glass only — it is expensive and wrong here',
        );
      });

      testWidgets('$name pressed collapses the shadow and translates', (
        tester,
      ) async {
        await pump(tester, theme, pressed: true);
        expect(
          decorationOf(tester).boxShadow,
          isEmpty,
          reason: 'pressed collapses the offset shadow',
        );
        expect(
          tester
              .widgetList<Transform>(
                find.descendant(
                  of: find.byType(DpSurface),
                  matching: find.byType(Transform),
                ),
              )
              .isNotEmpty,
          isTrue,
          reason: 'the panel moves into the space the shadow occupied',
        );
      });
    }
  });

  group('glass', () {
    testWidgets('draws a BackdropFilter at the token blur', (tester) async {
      await pump(tester, AppTheme.glass());
      final filter = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byType(DpSurface),
          matching: find.byType(BackdropFilter),
        ),
      );
      // ImageFilter has no public sigma getter; its toString carries them.
      expect(filter.filter.toString(), contains('24'));
    });

    testWidgets('cardStrong blurs harder than card', (tester) async {
      await pump(tester, AppTheme.glass(), kind: DpSurfaceKind.cardStrong);
      final filter = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byType(DpSurface),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(filter.filter.toString(), contains('32'));
    });

    testWidgets('clips to the glass radius so the blur stays inside', (
      tester,
    ) async {
      await pump(tester, AppTheme.glass());
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(DpSurface),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        clip.borderRadius,
        BorderRadius.circular(DpShapeTokens.glass.card),
      );
    });

    testWidgets('the drop shadow is soft, and sits outside the clip', (
      tester,
    ) async {
      await pump(tester, AppTheme.glass());
      final outer = decorationOf(tester);

      expect(outer.boxShadow, hasLength(1));
      expect(outer.boxShadow!.single.offset, const Offset(0, 8));
      expect(outer.boxShadow!.single.blurRadius, 24);
      expect(
        outer.color,
        isNull,
        reason:
            'the outer box carries the shadow only; the fill is inside the '
            'clip, or the blur would spill past the rounded corners',
      );
    });

    testWidgets('the fill and the sheen are separate layers', (tester) async {
      // A single BoxDecoration with both `color` and `gradient` paints only the
      // gradient, so the 55 % fill would disappear and the panel would read as
      // a faint wash. The artboard stacks them; so must we.
      await pump(tester, AppTheme.glass());
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(DpSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration as BoxDecoration)
          .toList();

      final fill = boxes.firstWhere((d) => d.color != null);
      expect(fill.color, DpSurfaceTokens.glass.card);
      expect(
        fill.gradient,
        isNull,
        reason: 'a gradient on the fill layer would replace the fill entirely',
      );

      final sheen = boxes.firstWhere((d) => d.gradient != null);
      expect(sheen.color, isNull);
      expect(
        (sheen.gradient! as LinearGradient).colors.first,
        DpSurfaceTokens.glass.sheen,
      );
    });

    testWidgets('pressed does not translate — there is no offset to collapse', (
      tester,
    ) async {
      await pump(tester, AppTheme.glass(), pressed: true);
      expect(
        decorationOf(tester).boxShadow,
        hasLength(1),
        reason: 'the glass drop shadow is not a press affordance',
      );
    });
  });

  testWidgets('glass lays its content out as paper does', (tester) async {
    // The top highlight is a Stack over the content. With the default fit it
    // loosened the content's constraints, so a column centred on paper sat in
    // the top-left corner under glass.
    Future<Offset> textCentre(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: SizedBox(
              width: 200,
              height: 52,
              child: DpSurface(
                // Small, so that where it sits shows: a label that nearly
                // fills the panel is centred whatever the layout does.
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const <Widget>[
                    Text('A1.1', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // Settled, not pumped once: `MaterialApp` animates a theme change, and
      // one frame after swapping to glass it is still drawing light.
      await tester.pumpAndSettle();
      expect(
        find.byType(BackdropFilter),
        theme.extension<DpTokens>()!.isGlass ? findsOneWidget : findsNothing,
      );
      return tester.getCenter(find.text('A1.1')) -
          tester.getCenter(find.byType(DpSurface));
    }

    final paper = await textCentre(AppTheme.light());
    final glass = await textCentre(AppTheme.glass());

    expect(paper.dx, closeTo(0, 1), reason: 'centred on paper');
    expect(glass.dx, closeTo(paper.dx, 1));
    expect(glass.dy, closeTo(paper.dy, 1));
  });

  group('selected', () {
    // The S2 choice cards: a bar each, until one is picked. The artboards draw
    // the pick as a 2 px edge in ink (Lagoon under glass) with the shadow.
    Border borderOf(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(DpSurface),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => (box.decoration as BoxDecoration).border)
        .whereType<Border>()
        .first;

    for (final (name, theme, tokens) in <(String, ThemeData, DpTokens)>[
      ('light', AppTheme.light(), DpTokens.light()),
      ('dark', AppTheme.dark(), DpTokens.dark()),
    ]) {
      testWidgets('$name: a 2 px ink edge, and the shadow even on a bar', (
        tester,
      ) async {
        await pump(tester, theme, kind: DpSurfaceKind.bar, selected: true);

        expect(borderOf(tester).top.width, 2);
        expect(borderOf(tester).top.color, tokens.color.ink);
        expect(decorationOf(tester).boxShadow, hasLength(1));
      });
    }

    testWidgets('glass: a 2 px Lagoon edge, and the soft shadow', (
      tester,
    ) async {
      final tokens = DpTokens.glass();
      await pump(
        tester,
        AppTheme.glass(),
        kind: DpSurfaceKind.bar,
        selected: true,
      );

      expect(borderOf(tester).top.width, 2);
      expect(borderOf(tester).top.color, tokens.color.primary);
      expect(decorationOf(tester).boxShadow, hasLength(1));
    });

    testWidgets('unselected, a bar is still only the hairline', (tester) async {
      final tokens = DpTokens.light();
      await pump(tester, AppTheme.light(), kind: DpSurfaceKind.bar);

      expect(borderOf(tester).top.width, tokens.surface.outlineWidth);
      expect(borderOf(tester).top.color, tokens.surface.outline);
      expect(decorationOf(tester).boxShadow, isEmpty);
    });
  });

  group('kinds', () {
    testWidgets('bar carries no drop shadow — it sits flush to the edge', (
      tester,
    ) async {
      await pump(tester, AppTheme.light(), kind: DpSurfaceKind.bar);
      expect(decorationOf(tester).boxShadow, isEmpty);
    });

    testWidgets('tint fills with the given colour at its opacity', (
      tester,
    ) async {
      await pump(
        tester,
        AppTheme.light(),
        kind: DpSurfaceKind.tint(DpPalette.light.die),
      );
      final colour = decorationOf(tester).color!;
      expect((colour.r * 255).round(), (DpPalette.light.die.r * 255).round());
      expect((colour.g * 255).round(), (DpPalette.light.die.g * 255).round());
      expect(colour.a, closeTo(0.22, 0.01));
    });

    testWidgets('cardStrong uses the denser fill in every mode', (
      tester,
    ) async {
      for (final (theme, tokens) in <(ThemeData, DpTokens)>[
        (AppTheme.light(), DpTokens.light()),
        (AppTheme.dark(), DpTokens.dark()),
      ]) {
        await pump(tester, theme, kind: DpSurfaceKind.cardStrong);
        expect(decorationOf(tester).color, tokens.surface.cardStrong);
      }
    });
  });

  testWidgets('one widget renders all three modes without changing', (
    tester,
  ) async {
    // The point of DpSurface: the caller below is byte-identical across modes.
    for (final theme in [
      AppTheme.light(),
      AppTheme.dark(),
      AppTheme.glass(),
      AppTheme.glass(dark: true),
    ]) {
      await pump(tester, theme);
      expect(find.text('Revise'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('onTap fires', (tester) async {
    var taps = 0;
    await pump(tester, AppTheme.light(), onTap: () => taps++);
    await tester.tap(find.byType(DpSurface));
    expect(taps, 1);
  });

  testWidgets('a press round trip collapses, restores, and still fires onTap', (
    tester,
  ) async {
    // The affordance has to come from onTap alone — no caller should have to
    // own a bool for it. And the panel must come back up: an earlier attempt
    // added the Transform only while pressed, which changed the tree shape
    // under the GestureDetector, dropped the gesture mid-press and left the
    // panel stuck down with onTap never firing.
    var taps = 0;
    await pump(tester, AppTheme.light(), onTap: () => taps++);

    expect(decorationOf(tester).boxShadow, hasLength(1), reason: 'idle');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DpSurface)),
    );
    await tester.pump();
    expect(decorationOf(tester).boxShadow, isEmpty, reason: 'pressed');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(decorationOf(tester).boxShadow, hasLength(1), reason: 'released');
    expect(taps, 1);
  });

  testWidgets('a cancelled press restores the shadow', (tester) async {
    await pump(tester, AppTheme.light(), onTap: () {});
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DpSurface)),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(decorationOf(tester).boxShadow, hasLength(1));
  });
}
