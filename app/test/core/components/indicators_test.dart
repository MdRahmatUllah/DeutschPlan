import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/components/sg_progress_ring.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/components/sg_stepper.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

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

  group('SgProgressRing', () {
    test('progress is the completed fraction, clamped', () {
      expect(const SgProgressRing(completed: 12, total: 20).progress, 0.6);
      expect(const SgProgressRing(completed: 0, total: 20).progress, 0);
      expect(const SgProgressRing(completed: 20, total: 20).progress, 1);
      expect(
        const SgProgressRing(completed: 25, total: 20).progress,
        1,
        reason: 'an over-full ring would draw past the circle',
      );
    });

    test('an empty plan is 0, not a divide by zero', () {
      // Rest days have no plan at all — TodayRest shows "Frei · no plan".
      expect(const SgProgressRing(completed: 0, total: 0).progress, 0);
      expect(const SgProgressRing(completed: 3, total: 0).progress, 0);
    });

    testWidgets('#437 the track is surface.track, under a Lagoon arc', (
      tester,
    ) async {
      await pump(tester, const SgProgressRing(completed: 12, total: 20));
      expect(
        tester.renderObject(
          find.descendant(
            of: find.byType(SgProgressRing),
            matching: find.byType(CustomPaint),
          ),
        ),
        paints
          ..circle(color: SgSurfaceTokens.light.track)
          ..arc(color: SgPalette.light.primary),
      );
    });

    testWidgets('it renders the count and the caption', (tester) async {
      await pump(
        tester,
        const SgProgressRing(completed: 12, total: 20, caption: '6 min left'),
      );
      expect(find.text('12 / 20'), findsOneWidget);
      expect(find.text('6 min left'), findsOneWidget);
    });

    testWidgets('a screen reader hears the count and the percentage', (
      tester,
    ) async {
      await pump(tester, const SgProgressRing(completed: 12, total: 20));
      expect(find.bySemanticsLabel('12 of 20'), findsOneWidget);
    });

    testWidgets('the box is square at the requested size', (tester) async {
      for (final size in <double>[120, 132]) {
        await pump(tester, SgProgressRing(completed: 1, total: 4, size: size));
        expect(tester.getSize(find.byType(SgProgressRing)), Size(size, size));
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
                child: SgProgressRing(
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
        tester.getSize(find.byType(SgProgressRing)),
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
          const SgProgressRing(completed: 12, total: 20),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('SgSegmentedBar', () {
    testWidgets('it is 8 dp tall by default', (tester) async {
      await pump(
        tester,
        const SgSegmentedBar(done: 184, learning: 60, todo: 296),
      );
      expect(tester.getSize(find.byType(SgSegmentedBar)).height, 8);
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
              SgSegmentedBar(done: 184, learning: 60, todo: 296, height: 6),
            ],
          ),
        ),
      );

      final segments = find.descendant(
        of: find.byType(SgSegmentedBar),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsNWidgets(3));
      for (final segment in segments.evaluate()) {
        final size = tester.getSize(find.byWidget(segment.widget));
        expect(size.height, 6);
        expect(size.width, greaterThan(0));
      }
      expect(tester.getSize(find.byType(SgSegmentedBar)).width, 300);
    });

    testWidgets('segments are weighted by count', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: SgSegmentedBar(done: 184, learning: 60, todo: 296),
        ),
      );

      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(SgSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(boxes, hasLength(3));
      expect(boxes[0].color, SgPalette.light.easy, reason: 'Done is Lime');
      expect(
        boxes[1].color,
        SgPalette.light.learning,
        reason: 'Learning is Sun',
      );
      expect(
        boxes[2].color,
        SgSurfaceTokens.light.track,
        reason: 'To do is the track, 3:1 on its card (#437)',
      );

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
          child: SgSegmentedBar(done: 1, learning: 0, todo: 540),
        ),
      );
      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(SgSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();

      expect(boxes, hasLength(2), reason: 'an empty segment is not drawn');
      expect(
        tester.getSize(find.byWidget(boxes[0])).width,
        greaterThanOrEqualTo(SgSegmentedBar.minimumSegment),
      );
    });

    testWidgets('an untouched step is all track, not an empty box', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: SgSegmentedBar(done: 0, learning: 0, todo: 0),
        ),
      );
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(SgSegmentedBar),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, SgSurfaceTokens.light.track);
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
            child: const SgSegmentedBar(done: 184, learning: 60, todo: 296),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at width $width');
      }
    });

    testWidgets('a screen reader hears all three counts', (tester) async {
      await pump(
        tester,
        const SgSegmentedBar(done: 184, learning: 60, todo: 296),
      );
      expect(
        find.bySemanticsLabel('184 done, 60 learning, 296 to do'),
        findsOneWidget,
      );
    });
  });

  group('SgSpeakerButton', () {
    testWidgets('it is 56 dp, circular, with the hard offset shadow', (
      tester,
    ) async {
      await pump(
        tester,
        SgSpeakerButton(onPressed: () {}, semanticLabel: 'Pronounce Rechnung'),
      );

      expect(tester.getSize(find.byType(SgSpeakerButton)), const Size(56, 56));

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(SgSpeakerButton),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, SgPalette.light.primary);
      expect((decoration.border! as Border).top.width, 2);
      expect(decoration.boxShadow!.single.offset, const Offset(3, 3));
    });

    testWidgets('playing swaps the horn for three bars', (tester) async {
      await pump(
        tester,
        SgSpeakerButton(
          onPressed: () {},
          semanticLabel: 'Pronounce',
          state: SgSpeakerState.playing,
        ),
      );
      expect(find.byIcon(Icons.volume_up), findsNothing);
      // Three bars plus the button's own container.
      expect(
        find.descendant(
          of: find.byType(SgSpeakerButton),
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
        SgSpeakerButton(
          onPressed: () {},
          semanticLabel: 'Pronounce',
          state: SgSpeakerState.loading,
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
        SgSpeakerButton(
          onPressed: () => taps++,
          semanticLabel: 'No German voice installed',
          state: SgSpeakerState.unavailable,
        ),
      );

      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(SgSpeakerButton),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.color, SgSurfaceTokens.light.muted);

      await tester.tap(find.byType(SgSpeakerButton));
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
        SgSpeakerButton(
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
          semanticLabel: 'Pronounce',
        ),
      );

      await tester.tap(find.byType(SgSpeakerButton));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(SgSpeakerButton));
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
            SgSpeakerButton(
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
        SgSpeakerButton(onPressed: () {}, semanticLabel: 'Pronounce Rechnung'),
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
          SgProgressRing(completed: 12, total: 20),
          SizedBox(
            width: 200,
            child: SgSegmentedBar(done: 184, learning: 60, todo: 296),
          ),
        ],
      ),
      locale: const Locale('bn'),
    );
    expect(find.bySemanticsLabel('২০টির মধ্যে ১২টি'), findsOneWidget);
    expect(
      find.bySemanticsLabel('১৮৪টি শেখা হয়েছে, ৬০টি শিখছি, ২৯৬টি শেখা বাকি'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'\d+ done, \d+ learning, \d+ to do|\b\d+ of \d+\b'),
      ),
      findsNothing,
    );
  });

  testWidgets("#425 a number a component writes is in the UI language's "
      'digits: the ring\'s centre, the stepper\'s value', (tester) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SgProgressRing(completed: 12, total: 20),
          SgStepper(
            value: 15,
            min: 5,
            max: 30,
            onChanged: (_) {},
            decreaseLabel: 'less',
            increaseLabel: 'more',
          ),
        ],
      ),
      locale: const Locale('bn'),
    );
    expect(find.text('১২ / ২০'), findsOneWidget);
    expect(find.text('১৫'), findsOneWidget);
  });
}
