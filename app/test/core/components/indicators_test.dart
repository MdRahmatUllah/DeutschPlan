import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Geometry from the Foundations artboard: the ring is a 120 unit box with
/// radius 54 and stroke 12; the segmented bar is 8 dp with 2 dp gaps; the
/// speaker is 56 dp with the hard offset shadow.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    // A spinner animates forever, so pumpAndSettle would time out on it.
    bool settle = true,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('DpProgressRing', () {
    test('progress is the completed fraction, clamped', () {
      expect(const DpProgressRing(completed: 12, total: 20).progress, 0.6);
      expect(const DpProgressRing(completed: 0, total: 20).progress, 0);
      expect(const DpProgressRing(completed: 20, total: 20).progress, 1);
      expect(
        const DpProgressRing(completed: 25, total: 20).progress,
        1,
        reason: 'an over-full ring would draw past the circle',
      );
    });

    test('an empty plan is 0, not a divide by zero', () {
      // Rest days have no plan at all — TodayRest shows "Frei · no plan".
      expect(const DpProgressRing(completed: 0, total: 0).progress, 0);
      expect(const DpProgressRing(completed: 3, total: 0).progress, 0);
    });

    testWidgets('it renders the count and the caption', (tester) async {
      await pump(
        tester,
        const DpProgressRing(completed: 12, total: 20, caption: '6 min left'),
      );
      expect(find.text('12 / 20'), findsOneWidget);
      expect(find.text('6 min left'), findsOneWidget);
    });

    testWidgets('a screen reader hears the count and the percentage', (
      tester,
    ) async {
      await pump(tester, const DpProgressRing(completed: 12, total: 20));
      expect(find.bySemanticsLabel('12 of 20'), findsOneWidget);
    });

    testWidgets('the box is square at the requested size', (tester) async {
      for (final size in <double>[120, 132]) {
        await pump(tester, DpProgressRing(completed: 1, total: 4, size: size));
        expect(tester.getSize(find.byType(DpProgressRing)), Size(size, size));
      }
    });

    testWidgets('the centre shrinks rather than overflowing at 200 %', (
      tester,
    ) async {
      // The ring's diameter is fixed on Today, so the numbers give way. Without
      // this the Column overflowed the circle by 132 px at 2x.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Center(
                child: DpProgressRing(
                  completed: 12,
                  total: 20,
                  caption: '6 min left',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(DpProgressRing)),
        const Size(120, 120),
        reason: 'the ring keeps its diameter; the centre is what gives way',
      );
    });

    testWidgets('it renders in all three modes', (tester) async {
      for (final theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
        AppTheme.glass(),
      ]) {
        await pump(
          tester,
          const DpProgressRing(completed: 12, total: 20),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('DpSegmentedBar', () {
    testWidgets('it is 8 dp tall by default', (tester) async {
      await pump(
        tester,
        const DpSegmentedBar(done: 184, learning: 60, todo: 296),
      );
      expect(tester.getSize(find.byType(DpSegmentedBar)).height, 8);
    });

    testWidgets('every segment fills the bar, even in a start-aligned column', (
      tester,
    ) async {
      // A childless ColoredBox takes the smallest size it may. Under a row's
      // loose height that was zero, and the bar drew no segments at all —
      // which widths alone never showed. Today's ring card is such a column.
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DpSegmentedBar(done: 184, learning: 60, todo: 296, height: 6),
            ],
          ),
        ),
      );

      final segments = find.descendant(
        of: find.byType(DpSegmentedBar),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsNWidgets(3));
      for (final segment in segments.evaluate()) {
        final size = tester.getSize(find.byWidget(segment.widget));
        expect(size.height, 6);
        expect(size.width, greaterThan(0));
      }
      expect(tester.getSize(find.byType(DpSegmentedBar)).width, 300);
    });

    testWidgets('segments are weighted by count', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: DpSegmentedBar(done: 184, learning: 60, todo: 296),
        ),
      );

      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(DpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(boxes, hasLength(3));
      expect(boxes[0].color, DpPalette.light.easy, reason: 'Done is Lime');
      expect(
        boxes[1].color,
        DpPalette.light.learning,
        reason: 'Learning is Sun',
      );
      expect(boxes[2].color, DpSurfaceTokens.light.muted, reason: 'To do Oat');

      final done = tester.getSize(find.byWidget(boxes[0])).width;
      final todo = tester.getSize(find.byWidget(boxes[2])).width;
      expect(
        todo,
        greaterThan(done),
        reason: '296 to do should out-measure 184 done',
      );
    });

    testWidgets('a single learned word still gets a visible sliver', (
      tester,
    ) async {
      // The whole point of the bar is showing that progress exists.
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: DpSegmentedBar(done: 1, learning: 0, todo: 540),
        ),
      );
      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(DpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();

      expect(boxes, hasLength(2), reason: 'an empty segment is not drawn');
      expect(
        tester.getSize(find.byWidget(boxes[0])).width,
        greaterThanOrEqualTo(DpSegmentedBar.minimumSegment),
      );
    });

    testWidgets('an untouched step is all Oat, not an empty box', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: DpSegmentedBar(done: 0, learning: 0, todo: 0),
        ),
      );
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(DpSegmentedBar),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, DpSurfaceTokens.light.muted);
    });

    testWidgets('a bar too narrow for the floor still does not overflow', (
      tester,
    ) async {
      // Step tiles and Me cards are not fixed width; a tablet pane or a long
      // label can squeeze this. Honouring the 2 dp floor is not worth an
      // overflow at a width where nothing is legible anyway.
      for (final width in <double>[300, 20, 5]) {
        await pump(
          tester,
          SizedBox(
            width: width,
            child: const DpSegmentedBar(done: 184, learning: 60, todo: 296),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at width $width');
      }
    });

    testWidgets('a screen reader hears all three counts', (tester) async {
      await pump(
        tester,
        const DpSegmentedBar(done: 184, learning: 60, todo: 296),
      );
      expect(
        find.bySemanticsLabel('184 done, 60 learning, 296 to do'),
        findsOneWidget,
      );
    });
  });

  group('DpSpeakerButton', () {
    testWidgets('it is 56 dp, circular, with the hard offset shadow', (
      tester,
    ) async {
      await pump(
        tester,
        DpSpeakerButton(onPressed: () {}, semanticLabel: 'Pronounce Rechnung'),
      );

      expect(tester.getSize(find.byType(DpSpeakerButton)), const Size(56, 56));

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(DpSpeakerButton),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, DpPalette.light.primary);
      expect((decoration.border! as Border).top.width, 2);
      expect(decoration.boxShadow!.single.offset, const Offset(3, 3));
    });

    testWidgets('playing swaps the horn for three bars', (tester) async {
      await pump(
        tester,
        DpSpeakerButton(
          onPressed: () {},
          semanticLabel: 'Pronounce',
          state: DpSpeakerState.playing,
        ),
      );
      expect(find.byIcon(Icons.volume_up), findsNothing);
      // Three bars plus the button's own container.
      expect(
        find.descendant(
          of: find.byType(DpSpeakerButton),
          matching: find.byType(Container),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('loading shows a spinner, not the bars', (tester) async {
      // tts.md only shows this past 150 ms, so it means "thinking", which is a
      // different thing from "sound is coming out".
      await pump(
        tester,
        DpSpeakerButton(
          onPressed: () {},
          semanticLabel: 'Pronounce',
          state: DpSpeakerState.loading,
        ),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('unavailable is slashed and muted, but still responds', (
      tester,
    ) async {
      // accessibility-performance.md: "No German system voice → Speaker shows a
      // slashed icon; tap explains how to install one." An inert button is the
      // one moment the app most needs to say why.
      var taps = 0;
      await pump(
        tester,
        DpSpeakerButton(
          onPressed: () => taps++,
          semanticLabel: 'No German voice installed',
          state: DpSpeakerState.unavailable,
        ),
      );

      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(DpSpeakerButton),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.color, DpSurfaceTokens.light.muted);

      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'the tap has to reach the caller so it can explain',
      );
    });

    testWidgets('long-press is separate from tap, for the 0.75x playback', (
      tester,
    ) async {
      var taps = 0;
      var longPresses = 0;
      await pump(
        tester,
        DpSpeakerButton(
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
          semanticLabel: 'Pronounce',
        ),
      );

      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(longPresses, 1);
    });

    testWidgets('a screen reader can play it, and slowly, as its own '
        'button', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      var longPresses = 0;
      await pump(
        tester,
        Row(
          children: <Widget>[
            // A headword beside it, as on W1 and T2: it must not merge in.
            const Text('die Rechnung'),
            DpSpeakerButton(
              onPressed: () => taps++,
              onLongPress: () => longPresses++,
              semanticLabel: 'Pronounce Rechnung',
            ),
          ],
        ),
      );
      // By its own label: merged into the headword, the label would be
      // "die Rechnung / Pronounce Rechnung" and this would find nothing.
      final speaker = find.semantics.byLabel('Pronounce Rechnung');
      tester.semantics.tap(speaker);
      tester.semantics.longPress(speaker);
      expect((taps, longPresses), (1, 1));
      semantics.dispose();
    });

    testWidgets('it is announced with its label', (tester) async {
      await pump(
        tester,
        DpSpeakerButton(onPressed: () {}, semanticLabel: 'Pronounce Rechnung'),
      );
      expect(find.bySemanticsLabel('Pronounce Rechnung'), findsOneWidget);
    });
  });

  testWidgets('#425 with no label of its own, a screen reader hears the ring '
      'and the bar in the UI language', (tester) async {
    await pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DpProgressRing(completed: 12, total: 20),
          SizedBox(
            width: 200,
            child: DpSegmentedBar(done: 184, learning: 60, todo: 296),
          ),
        ],
      ),
      locale: const Locale('bn'),
    );
    expect(find.bySemanticsLabel('20টির মধ্যে 12টি'), findsOneWidget);
    expect(
      find.bySemanticsLabel('184টি শেখা হয়েছে, 60টি শিখছি, 296টি বাকি'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'\d+ done, \d+ learning, \d+ to do|\b\d+ of \d+\b'),
      ),
      findsNothing,
    );
  });
}
