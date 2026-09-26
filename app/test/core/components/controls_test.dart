import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_rating_bar.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../text_clipping.dart';

/// Every size, radius and fill here is read off `Foundations.html`; these tests
/// hold the widgets to it. Where the artboard and a Material default disagree,
/// the artboard wins — that disagreement is why these are not Material widgets.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    Locale? locale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        locale: locale,
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

  group('SgButton', () {
    testWidgets('#517 a lone SgButton in a container with text is its own '
        'button node, not merged with the text around it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        Semantics(
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('12 words learned today'),
              SgButton(label: 'Done', onPressed: () {}),
            ],
          ),
        ),
      );
      final button = tester.getSemantics(find.byType(SgButton));
      expect(button.label, 'Done');
      expect(button.flagsCollection.isButton, isTrue);
      final around = tester.getSemantics(find.text('12 words learned today'));
      expect(around.label, isNot(contains('Done')));
      semantics.dispose();
    });

    testWidgets('the three kinds are 56, 48 and 48 dp tall on Android', (
      tester,
    ) async {
      // The artboard draws the text button at 44; on Android the hit area is
      // padded to 48, which is the platform minimum. On iOS 44 is already it.
      for (final (kind, height) in <(SgButtonKind, double)>[
        (SgButtonKind.primary, 56),
        (SgButtonKind.secondary, 48),
        (SgButtonKind.text, SgButton.minimumTapTarget),
      ]) {
        await pump(
          tester,
          SgButton(label: 'Start today', kind: kind, onPressed: () {}),
        );
        expect(
          tester.getSize(find.byType(SgButton)).height,
          height,
          reason: '$kind',
        );
      }
    });

    testWidgets('the compact primary is drawn at 40 and touched at 48', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        SgButton(
          label: 'Study',
          compact: true,
          expand: false,
          onPressed: () => taps++,
        ),
      );
      final drawn = find.descendant(
        of: find.byType(SgButton),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(drawn.first).height, SgButton.compactHeight);
      expect(
        tester.getSize(find.byType(SgButton)).height,
        SgButton.minimumTapTarget,
      );
      // Just outside the drawing, still inside the hit area.
      final box = tester.getRect(drawn.first);
      await tester.tapAt(Offset(box.center.dx, box.bottom + 3));
      expect(taps, 1);
    });

    testWidgets('a primary drawn at 48 where the artboard says so', (
      tester,
    ) async {
      await pump(
        tester,
        SgButton(
          label: 'Practise all due · 2',
          drawnHeight: 48,
          onPressed: () {},
        ),
      );
      expect(tester.getSize(find.byType(SgButton)).height, 48);
    });

    testWidgets('only the primary carries the hard offset shadow', (
      tester,
    ) async {
      await pump(tester, SgButton(label: 'Start today', onPressed: () {}));
      final primary = decorationIn(tester, SgButton);
      expect(primary.boxShadow, hasLength(1));
      expect(primary.boxShadow!.single.offset, const Offset(3, 3));
      expect(primary.boxShadow!.single.blurRadius, 0);
      expect(primary.color, SgPalette.light.primary);

      await pump(
        tester,
        SgButton(
          label: 'Review backlog',
          kind: SgButtonKind.secondary,
          onPressed: () {},
        ),
      );
      final secondary = decorationIn(tester, SgButton);
      expect(secondary.boxShadow, isEmpty);
      expect(secondary.color, SgSurfaceTokens.light.muted);
    });

    testWidgets('the border is 2 px ink, not the 1.5 px of a card', (
      tester,
    ) async {
      await pump(tester, SgButton(label: 'Start today', onPressed: () {}));
      final border = decorationIn(tester, SgButton).border! as Border;
      expect(border.top.width, 2);
      expect(border.top.color, SgPalette.light.ink);
    });

    testWidgets('a press collapses the shadow and restores it, and taps fire', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        SgButton(label: 'Start today', onPressed: () => taps++),
      );

      expect(decorationIn(tester, SgButton).boxShadow, hasLength(1));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SgButton)),
      );
      await tester.pump();
      expect(decorationIn(tester, SgButton).boxShadow, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(decorationIn(tester, SgButton).boxShadow, hasLength(1));
      expect(taps, 1);
    });

    testWidgets('a disabled button still renders and does not fire', (
      tester,
    ) async {
      // Today's all-done state is a disabled Lime primary, so disabling must
      // not remove the button.
      await pump(
        tester,
        const SgButton(label: 'All done — see you tomorrow', onPressed: null),
      );
      expect(find.byType(SgButton), findsOneWidget);

      await tester.tap(find.byType(SgButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('glass keeps the fill solid and drops the outline', (
      tester,
    ) async {
      // theming.md: "Buttons stay solid so calls to action never blur."
      await pump(
        tester,
        SgButton(label: 'Start today', onPressed: () {}),
        theme: AppTheme.glass(),
      );
      final decoration = decorationIn(tester, SgButton);
      expect(decoration.color, SgPalette.light.primary);
      expect(decoration.color!.a, 1.0, reason: 'a solid fill, not translucent');
      expect(decoration.border, isNull);
    });

    testWidgets('a long label wraps at 200 % instead of being clipped', (
      tester,
    ) async {
      // maxLines: 1 inside a fixed-height box clipped the label with no
      // exception — the same silent failure as the headword in #190.
      double heightAt(double scale) =>
          tester.getSize(find.byType(SgButton)).height;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: SgButton(
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
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: SgButton(
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
        SgButton(
          label: 'Done for now',
          kind: SgButtonKind.text,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSize(find.byType(SgButton)).height,
        greaterThanOrEqualTo(SgButton.minimumTapTarget),
      );
    });

    testWidgets('it is announced as a button with its label', (tester) async {
      await pump(tester, SgButton(label: 'Start today', onPressed: () {}));
      expect(find.bySemanticsLabel('Start today'), findsOneWidget);
    });
  });

  group('SgRatingBar', () {
    Map<SgRating, String> previews() => <SgRating, String>{
      SgRating.again: '1 d',
      SgRating.hard: '3 d',
      SgRating.good: '8 d',
      SgRating.easy: '21 d',
    };

    testWidgets('the four ratings render in BR-FSRS-02 order', (tester) async {
      await pump(tester, SgRatingBar(onRated: (_) {}, intervals: previews()));
      final labels = <String>['Again', 'Hard', 'Good', 'Easy'];
      var previousX = -1.0;
      for (final label in labels) {
        final x = tester.getCenter(find.text(label)).dx;
        expect(x, greaterThan(previousX), reason: '$label is out of order');
        previousX = x;
      }
    });

    test('the rating values are the ones written to review_log', () {
      expect(SgRating.again.value, 1);
      expect(SgRating.hard.value, 2);
      expect(SgRating.good.value, 3);
      expect(SgRating.easy.value, 4);
    });

    testWidgets('each button is 60 dp with a 2 px border in its own colour', (
      tester,
    ) async {
      await pump(tester, SgRatingBar(onRated: (_) {}, intervals: previews()));

      const palette = SgPalette.light;
      for (final (rating, colour) in <(SgRating, Color)>[
        (SgRating.again, palette.again),
        (SgRating.hard, palette.hard),
        (SgRating.good, palette.good),
        (SgRating.easy, palette.easy),
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
        tester.getSize(find.byType(SgRatingBar)).height,
        SgRatingBar.height,
      );
    });

    testWidgets('#580 in Bangla at 200 % the labels and intervals show whole: '
        'a word too wide shrinks rather than break, an interval of 1,234 days '
        'wraps, and the four buttons grow to one height', (tester) async {
      final bn = lookupAppLocalizations(const Locale('bn'));
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const AndroidTextScaler(2)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SgRatingBar(
                onRated: (_) {},
                intervals: <SgRating, String>{
                  SgRating.again: bn.studyIntervalDays(1),
                  SgRating.hard: bn.studyIntervalDays(3),
                  SgRating.good: bn.studyIntervalDays(8),
                  // FSRS allows up to 36,500; a 1,000+ day interval wraps.
                  SgRating.easy: bn.studyIntervalDays(1234),
                },
              ),
            ),
          ),
        ),
        locale: const Locale('bn'),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expectNothingClipped(tester, within: find.byType(SgRatingBar));
      expectAllLinesShown(tester, within: find.byType(SgRatingBar));
      expectNoWordBroken(tester, within: find.byType(SgRatingBar));
      final heights = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SgRatingBar),
              matching: find.byType(Container),
            ),
          )
          .map((container) => tester.getSize(find.byWidget(container)).height)
          .toSet();
      expect(heights, hasLength(1), reason: 'one height for the four');
      expect(heights.single, greaterThan(SgRatingBar.height));
      expect(
        tester.getSize(find.byType(SgRatingBar)).height,
        lessThan(SgRatingBar.height * 3),
        reason: "the tallest button's height, not the screen's",
      );
    });

    testWidgets('the interval preview shows under each label', (tester) async {
      await pump(tester, SgRatingBar(onRated: (_) {}, intervals: previews()));
      for (final interval in <String>['1 d', '3 d', '8 d', '21 d']) {
        expect(find.text(interval), findsOneWidget);
      }
    });

    testWidgets('tapping reports the rating', (tester) async {
      SgRating? rated;
      await pump(
        tester,
        SgRatingBar(onRated: (r) => rated = r, intervals: previews()),
      );
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();
      expect(rated, SgRating.good);
    });

    testWidgets('a screen reader hears the interval with the rating', (
      tester,
    ) async {
      // The interval is part of the decision, so it must not be a separate node
      // that could be read out of order.
      await pump(tester, SgRatingBar(onRated: (_) {}, intervals: previews()));
      expect(find.bySemanticsLabel('Good, 8 d'), findsOneWidget);
    });

    testWidgets('disabled, it does not report', (tester) async {
      var rated = false;
      await pump(
        tester,
        SgRatingBar(
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

  group('SgChip', () {
    testWidgets('each kind is the height the artboard draws', (tester) async {
      for (final (kind, height) in <(SgChipKind, double)>[
        (SgChipKind.step, 24),
        (SgChipKind.status, 24),
        (SgChipKind.streak, 28),
        (SgChipKind.filter, 32),
        (SgChipKind.webLink, 32),
      ]) {
        await pump(tester, SgChip(label: 'A2.1', kind: kind));
        expect(
          tester.getSize(find.byType(SgChip)).height,
          height,
          reason: '$kind',
        );
      }
    });

    testWidgets('a selected step chip fills Sun; an unselected one does not', (
      tester,
    ) async {
      await pump(tester, const SgChip(label: 'A2.1', selected: true));
      expect(
        (tester.widget<Container>(find.byType(Container).first).decoration!
                as BoxDecoration)
            .color,
        SgPalette.light.accent,
      );

      await pump(tester, const SgChip(label: 'A2.1'));
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
          SgChip(
            label: 'Learning',
            kind: SgChipKind.status,
            statusColour: SgPalette.light.learning,
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

    for (final chip in const <SgChip>[
      SgChip(label: '12', kind: SgChipKind.streak),
      SgChip(label: 'A2.1', selected: true),
    ]) {
      testWidgets('a ${chip.kind.name} chip on Sun keeps dark ink at night', (
        tester,
      ) async {
        // The dark artboard's streak pill and step chip are #15121F on Sun.
        // The page ink is light at night and would vanish into the fill.
        await pump(tester, chip, theme: AppTheme.dark());
        final label = tester.widget<Text>(
          find.descendant(of: find.byType(SgChip), matching: find.byType(Text)),
        );
        expect(label.style?.color, SgPalette.dark.onAccent);
        final icon = find.descendant(
          of: find.byType(SgChip),
          matching: find.byType(Icon),
        );
        if (chip.kind == SgChipKind.streak) {
          expect(tester.widget<Icon>(icon).color, SgPalette.dark.onAccent);
        }
      });
    }

    testWidgets('the streak pill is fully rounded', (tester) async {
      await pump(tester, const SgChip(label: '12', kind: SgChipKind.streak));
      final decoration =
          tester.widget<Container>(find.byType(Container).first).decoration!
              as BoxDecoration;
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        28 / 2,
        reason: 'a pill, not a rounded rectangle',
      );
    });

    testWidgets('each kind draws the icon the artboard gives it', (
      tester,
    ) async {
      // From the side-by-side with Foundations.html: the streak pill carries a
      // flame, a selected filter a tick, and a web link an external-link mark.
      for (final (chip, icon) in <(SgChip, IconData?)>[
        (
          const SgChip(label: '12', kind: SgChipKind.streak),
          Icons.local_fire_department,
        ),
        (
          const SgChip(label: 'All', kind: SgChipKind.filter, selected: true),
          Icons.check,
        ),
        (const SgChip(label: 'All', kind: SgChipKind.filter), null),
        (
          const SgChip(label: 'Duden', kind: SgChipKind.webLink),
          Icons.open_in_new,
        ),
        (const SgChip(label: 'A2.1'), null),
      ]) {
        await pump(tester, chip);
        if (icon == null) {
          expect(
            find.descendant(
              of: find.byType(SgChip),
              matching: find.byType(Icon),
            ),
            findsNothing,
            reason: '${chip.kind} should draw no icon',
          );
        } else {
          expect(find.byIcon(icon), findsOneWidget, reason: '${chip.kind}');
        }
      }
    });

    testWidgets(
      'the web-link mark trails its label, as the artboard draws it',
      (tester) async {
        await pump(
          tester,
          const SgChip(label: 'Duden', kind: SgChipKind.webLink),
        );
        expect(
          tester.getCenter(find.byIcon(Icons.open_in_new)).dx,
          greaterThan(tester.getCenter(find.text('Duden')).dx),
        );
      },
    );

    testWidgets('a tappable chip fires and an untappable one has no gesture', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        SgChip(label: 'Learning', kind: SgChipKind.filter, onTap: () => taps++),
      );
      await tester.tap(find.byType(SgChip));
      expect(taps, 1);

      await pump(tester, const SgChip(label: 'A2.1'));
      expect(
        find.descendant(
          of: find.byType(SgChip),
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
            SgButton(label: 'Start today', onPressed: () {}),
            SgRatingBar(
              onRated: (_) {},
              intervals: const <SgRating, String>{
                SgRating.again: '1 d',
                SgRating.hard: '3 d',
                SgRating.good: '8 d',
                SgRating.easy: '21 d',
              },
            ),
            const SgChip(label: 'A2.1'),
          ],
        ),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    }
  });

  // ONBOARDING §6: every tappable thing is a button in semantics, and a
  // screen reader can press it. These run the semantics action itself, not a
  // pointer tap, which is what TalkBack's double tap sends.
  testWidgets('#314 at 200 % text every chip kind grows with its label, and '
      'is the artboard height at 100 %', (tester) async {
    Widget chips() => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        const SgChip(label: 'A2.2'),
        SgChip(
          label: 'To do',
          kind: SgChipKind.status,
          statusColour: SgPalette.light.easy,
        ),
        SgChip(label: 'Relaxed · 5', kind: SgChipKind.filter, onTap: () {}),
        SgChip(label: '12', kind: SgChipKind.streak, onTap: () {}),
        SgChip(label: 'Duden', kind: SgChipKind.webLink, onTap: () {}),
      ],
    );
    await pump(tester, chips());
    final atOne = <double>[
      for (final chip in tester.widgetList(find.byType(SgChip)))
        tester.getSize(find.byWidget(chip)).height,
    ];
    expect(atOne, <double>[24, 24, 32, 28, 32]);

    textAt(tester, 2);
    await pump(tester, chips());
    expectNothingClipped(tester);
    final atTwo = <double>[
      for (final chip in tester.widgetList(find.byType(SgChip)))
        tester.getSize(find.byWidget(chip)).height,
    ];
    for (final (i, height) in atTwo.indexed) {
      expect(height, greaterThan(atOne[i]), reason: 'chip $i');
    }
  });

  group('#312 a screen reader can press them', () {
    testWidgets('an SgChip', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await pump(
        tester,
        SgChip(
          label: 'Relaxed · 5',
          kind: SgChipKind.filter,
          onTap: () => taps++,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Relaxed · 5'));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets("SgRatingBar's buttons", (tester) async {
      final semantics = tester.ensureSemantics();
      final rated = <SgRating>[];
      await pump(
        tester,
        SgRatingBar(
          onRated: rated.add,
          intervals: const <SgRating, String>{SgRating.good: '8 d'},
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Good')));
      expect(rated, <SgRating>[SgRating.good]);
      semantics.dispose();
    });

    testWidgets('a held SgRatingBar offers nothing to press', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        SgRatingBar(
          onRated: (_) {},
          intervals: const <SgRating, String>{SgRating.good: '8 d'},
          enabled: false,
        ),
      );
      expect(
        tester.getSemantics(find.text('Good')),
        isSemantics(isButton: true, hasEnabledState: true, hasTapAction: false),
      );
      semantics.dispose();
    });

    testWidgets('a disabled SgUmlautBar offers no tap or long press', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, SgUmlautBar(controller: controller, enabled: false));
      expect(
        tester.getSemantics(find.text('ä')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          hasTapAction: false,
          hasLongPressAction: false,
        ),
      );
      semantics.dispose();
    });

    testWidgets("SgUmlautBar's keys, tap and long press", (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, SgUmlautBar(controller: controller));
      final key = find.semantics.byLabel(RegExp('^ä'));
      tester.semantics.tap(key);
      tester.semantics.longPress(key);
      expect(controller.text, 'äÄ');
      semantics.dispose();
    });
  });
}

String _name(SgRating rating) => switch (rating) {
  SgRating.again => 'Again',
  SgRating.hard => 'Hard',
  SgRating.good => 'Good',
  SgRating.easy => 'Easy',
};
