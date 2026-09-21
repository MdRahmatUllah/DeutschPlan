import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Every size, radius and fill here is read off `Foundations.html`; these tests
/// hold the widgets to it. Where the artboard and a Material default disagree,
/// the artboard wins — that disagreement is why these are not Material widgets.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration decorationIn(WidgetTester tester, Type ancestor) =>
      tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(ancestor),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .first
              .decoration
          as BoxDecoration;

  group('DpButton', () {
    testWidgets('the three kinds are 56, 48 and 48 dp tall on Android', (
      tester,
    ) async {
      // The artboard draws the text button at 44; on Android the hit area is
      // padded to 48, which is the platform minimum. On iOS 44 is already it.
      for (final (kind, height) in <(DpButtonKind, double)>[
        (DpButtonKind.primary, 56),
        (DpButtonKind.secondary, 48),
        (DpButtonKind.text, DpButton.minimumTapTarget),
      ]) {
        await pump(
          tester,
          DpButton(label: 'Start today', kind: kind, onPressed: () {}),
        );
        expect(
          tester.getSize(find.byType(DpButton)).height,
          height,
          reason: '$kind',
        );
      }
    });

    testWidgets('only the primary carries the hard offset shadow', (
      tester,
    ) async {
      await pump(tester, DpButton(label: 'Start today', onPressed: () {}));
      final primary = decorationIn(tester, DpButton);
      expect(primary.boxShadow, hasLength(1));
      expect(primary.boxShadow!.single.offset, const Offset(3, 3));
      expect(primary.boxShadow!.single.blurRadius, 0);
      expect(primary.color, DpPalette.light.primary);

      await pump(
        tester,
        DpButton(
          label: 'Review backlog',
          kind: DpButtonKind.secondary,
          onPressed: () {},
        ),
      );
      final secondary = decorationIn(tester, DpButton);
      expect(secondary.boxShadow, isEmpty);
      expect(secondary.color, DpSurfaceTokens.light.muted);
    });

    testWidgets('the border is 2 px ink, not the 1.5 px of a card', (
      tester,
    ) async {
      await pump(tester, DpButton(label: 'Start today', onPressed: () {}));
      final border = decorationIn(tester, DpButton).border! as Border;
      expect(border.top.width, 2);
      expect(border.top.color, DpPalette.light.ink);
    });

    testWidgets('a press collapses the shadow and restores it, and taps fire', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        DpButton(label: 'Start today', onPressed: () => taps++),
      );

      expect(decorationIn(tester, DpButton).boxShadow, hasLength(1));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DpButton)),
      );
      await tester.pump();
      expect(decorationIn(tester, DpButton).boxShadow, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(decorationIn(tester, DpButton).boxShadow, hasLength(1));
      expect(taps, 1);
    });

    testWidgets('a disabled button still renders and does not fire', (
      tester,
    ) async {
      // Today's all-done state is a disabled Lime primary, so disabling must
      // not remove the button.
      await pump(
        tester,
        const DpButton(label: 'All done — see you tomorrow', onPressed: null),
      );
      expect(find.byType(DpButton), findsOneWidget);

      await tester.tap(find.byType(DpButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('glass keeps the fill solid and drops the outline', (
      tester,
    ) async {
      // theming.md: "Buttons stay solid so calls to action never blur."
      await pump(
        tester,
        DpButton(label: 'Start today', onPressed: () {}),
        theme: AppTheme.glass(),
      );
      final decoration = decorationIn(tester, DpButton);
      expect(decoration.color, DpPalette.light.primary);
      expect(decoration.color!.a, 1.0, reason: 'a solid fill, not translucent');
      expect(decoration.border, isNull);
    });

    testWidgets('a long label wraps at 200 % instead of being clipped', (
      tester,
    ) async {
      // maxLines: 1 inside a fixed-height box clipped the label with no
      // exception — the same silent failure as the headword in #190.
      double heightAt(double scale) =>
          tester.getSize(find.byType(DpButton)).height;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: DpButton(
                    label: 'All done — see you tomorrow',
                    onPressed: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final atOne = heightAt(1);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: DpButton(
                    label: 'All done — see you tomorrow',
                    onPressed: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        heightAt(2),
        greaterThan(atOne),
        reason: 'the button must grow for the label, not clip it',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a text button still clears 48 dp on Android', (tester) async {
      // 44 is the iOS minimum; accessibility-performance.md wants 48 dp on
      // Android, and the artboard's 44 is a visual measurement.
      await pump(
        tester,
        DpButton(
          label: 'Done for now',
          kind: DpButtonKind.text,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSize(find.byType(DpButton)).height,
        greaterThanOrEqualTo(DpButton.minimumTapTarget),
      );
    });

    testWidgets('it is announced as a button with its label', (tester) async {
      await pump(tester, DpButton(label: 'Start today', onPressed: () {}));
      expect(find.bySemanticsLabel('Start today'), findsOneWidget);
    });
  });

  group('DpRatingBar', () {
    Map<DpRating, String> previews() => <DpRating, String>{
      DpRating.again: '1 d',
      DpRating.hard: '3 d',
      DpRating.good: '8 d',
      DpRating.easy: '21 d',
    };

    testWidgets('the four ratings render in BR-FSRS-02 order', (tester) async {
      await pump(tester, DpRatingBar(onRated: (_) {}, intervals: previews()));
      final labels = <String>['Again', 'Hard', 'Good', 'Easy'];
      var previousX = -1.0;
      for (final label in labels) {
        final x = tester.getCenter(find.text(label)).dx;
        expect(x, greaterThan(previousX), reason: '$label is out of order');
        previousX = x;
      }
    });

    test('the rating values are the ones written to review_log', () {
      expect(DpRating.again.value, 1);
      expect(DpRating.hard.value, 2);
      expect(DpRating.good.value, 3);
      expect(DpRating.easy.value, 4);
    });

    testWidgets('each button is 60 dp with a 2 px border in its own colour', (
      tester,
    ) async {
      await pump(tester, DpRatingBar(onRated: (_) {}, intervals: previews()));

      const palette = DpPalette.light;
      for (final (rating, colour) in <(DpRating, Color)>[
        (DpRating.again, palette.again),
        (DpRating.hard, palette.hard),
        (DpRating.good, palette.good),
        (DpRating.easy, palette.easy),
      ]) {
        final container = tester.widget<Container>(
          find
              .ancestor(
                of: find.text(_name(rating)),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;

        expect((decoration.border! as Border).top.color, colour);
        expect((decoration.border! as Border).top.width, 2);
        expect(decoration.color!.a, closeTo(rating.fillOpacity, 0.01));
      }

      expect(
        tester.getSize(find.byType(DpRatingBar)).height,
        DpRatingBar.height,
      );
    });

    testWidgets('the interval preview shows under each label', (tester) async {
      await pump(tester, DpRatingBar(onRated: (_) {}, intervals: previews()));
      for (final interval in <String>['1 d', '3 d', '8 d', '21 d']) {
        expect(find.text(interval), findsOneWidget);
      }
    });

    testWidgets('tapping reports the rating', (tester) async {
      DpRating? rated;
      await pump(
        tester,
        DpRatingBar(onRated: (r) => rated = r, intervals: previews()),
      );
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();
      expect(rated, DpRating.good);
    });

    testWidgets('a screen reader hears the interval with the rating', (
      tester,
    ) async {
      // The interval is part of the decision, so it must not be a separate node
      // that could be read out of order.
      await pump(tester, DpRatingBar(onRated: (_) {}, intervals: previews()));
      expect(find.bySemanticsLabel('Good, 8 d'), findsOneWidget);
    });

    testWidgets('disabled, it does not report', (tester) async {
      var rated = false;
      await pump(
        tester,
        DpRatingBar(
          onRated: (_) => rated = true,
          intervals: previews(),
          enabled: false,
        ),
      );
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();
      expect(rated, isFalse);
    });
  });

  group('DpChip', () {
    testWidgets('each kind is the height the artboard draws', (tester) async {
      for (final (kind, height) in <(DpChipKind, double)>[
        (DpChipKind.step, 24),
        (DpChipKind.status, 24),
        (DpChipKind.streak, 28),
        (DpChipKind.filter, 32),
        (DpChipKind.webLink, 32),
      ]) {
        await pump(tester, DpChip(label: 'A2.1', kind: kind));
        expect(
          tester.getSize(find.byType(DpChip)).height,
          height,
          reason: '$kind',
        );
      }
    });

    testWidgets('a selected step chip fills Sun; an unselected one does not', (
      tester,
    ) async {
      await pump(tester, const DpChip(label: 'A2.1', selected: true));
      expect(
        (tester.widget<Container>(find.byType(Container).first).decoration!
                as BoxDecoration)
            .color,
        DpPalette.light.accent,
      );

      await pump(tester, const DpChip(label: 'A2.1'));
      expect(
        (tester.widget<Container>(find.byType(Container).first).decoration!
                as BoxDecoration)
            .color,
        isNull,
      );
    });

    testWidgets(
      'a status chip carries its dot, so status is not colour alone',
      (tester) async {
        await pump(
          tester,
          DpChip(
            label: 'Learning',
            kind: DpChipKind.status,
            statusColour: DpPalette.light.learning,
          ),
        );
        // The label is present as well as the dot.
        expect(find.text('Learning'), findsOneWidget);
        final dots = tester.widgetList<Container>(find.byType(Container)).where(
          (c) {
            final decoration = c.decoration;
            return decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle;
          },
        );
        expect(dots, hasLength(1));
      },
    );

    testWidgets('the streak pill is fully rounded', (tester) async {
      await pump(tester, const DpChip(label: '12', kind: DpChipKind.streak));
      final decoration =
          tester.widget<Container>(find.byType(Container).first).decoration!
              as BoxDecoration;
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        28 / 2,
        reason: 'a pill, not a rounded rectangle',
      );
    });

    testWidgets('a tappable chip fires and an untappable one has no gesture', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        DpChip(label: 'Learning', kind: DpChipKind.filter, onTap: () => taps++),
      );
      await tester.tap(find.byType(DpChip));
      expect(taps, 1);

      await pump(tester, const DpChip(label: 'A2.1'));
      expect(
        find.descendant(
          of: find.byType(DpChip),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('every control renders in all three modes', (tester) async {
    for (final theme in <ThemeData>[
      AppTheme.light(),
      AppTheme.dark(),
      AppTheme.glass(),
      AppTheme.glass(dark: true),
    ]) {
      await pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DpButton(label: 'Start today', onPressed: () {}),
            DpRatingBar(
              onRated: (_) {},
              intervals: const <DpRating, String>{
                DpRating.again: '1 d',
                DpRating.hard: '3 d',
                DpRating.good: '8 d',
                DpRating.easy: '21 d',
              },
            ),
            const DpChip(label: 'A2.1'),
          ],
        ),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

String _name(DpRating rating) => switch (rating) {
  DpRating.again => 'Again',
  DpRating.hard => 'Hard',
  DpRating.good => 'Good',
  DpRating.easy => 'Easy',
};
