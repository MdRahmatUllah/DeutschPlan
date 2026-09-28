import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_coach_mark.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_rating_bar.dart';
import 'package:sogda/core/components/sg_slider.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/components/sg_stepper.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

/// #745 · WCAG 2.1.1: what a finger presses, a keyboard or a D-pad presses
/// too. Tab reaches each custom control, and Enter, Space and the D-pad's
/// centre press it, as they do a Material button.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  final controls = <String, Widget Function(VoidCallback press)>{
    'SgButton': (press) => SgButton(label: 'Start', onPressed: press),
    'SgChip': (press) => SgChip(label: 'A2.1', onTap: press),
    'SgSurface': (press) => SgSurface(
      onTap: press,
      padding: const EdgeInsets.all(16),
      child: const SgText('Wohnen', role: SgTextRole.body),
    ),
    'SgSpeakerButton': (press) =>
        SgSpeakerButton(onPressed: press, semanticLabel: 'Pronounce'),
    'SgRatingBar': (press) => SgRatingBar(
      onRated: (_) => press(),
      intervals: <SgRating, String>{
        for (final rating in SgRating.values) rating: '1d',
      },
    ),
    'SgStepper': (press) => SgStepper(
      value: 5,
      min: 1,
      max: 10,
      onChanged: (_) => press(),
      decreaseLabel: 'Fewer',
      increaseLabel: 'More',
    ),
    'SgStepper on iOS': (press) => AdaptiveChromeScope(
      chrome: AdaptiveChrome.cupertino,
      child: SgStepper(
        value: 5,
        min: 1,
        max: 10,
        onChanged: (_) => press(),
        decreaseLabel: 'Fewer',
        increaseLabel: 'More',
      ),
    ),
    'SgCoachMark': (press) => SgCoachMark(
      message: 'Start here',
      visible: true,
      onDismissed: press,
      child: const SizedBox(width: 200, height: 48),
    ),
  };

  for (final MapEntry(key: name, value: build) in controls.entries) {
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.select,
    ]) {
      testWidgets(
        '#745 $name: Tab reaches it, ${key.debugName} presses it',
        // A D-pad is Android's; iOS maps no key to its centre.
        variant: key == LogicalKeyboardKey.select
            ? TargetPlatformVariant.only(TargetPlatform.android)
            : const TargetPlatformVariant(<TargetPlatform>{
                TargetPlatform.android,
                TargetPlatform.iOS,
              }),
        (tester) async {
          var pressed = 0;
          await pump(tester, build(() => pressed++));

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(key);
          await tester.pump();
          expect(pressed, 1);
        },
      );
    }
  }

  testWidgets('#1007 SgSlider: Tab reaches it, the arrows move it a step '
      'each way, and it holds at its ends with the focus kept; #698 each '
      'step is a whole gesture, ended as it moves', (tester) async {
    var value = 5;
    final ends = <int>[];
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 300,
          child: SgSlider(
            value: value,
            min: 4,
            max: 6,
            label: 'Pace',
            onChanged: (next) => setState(() => value = next),
            onChangeEnd: ends.add,
          ),
        ),
      ),
    );
    bool onSlider() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<SgSlider>() !=
        null;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.tab);
    expect(onSlider(), isTrue);
    await press(LogicalKeyboardKey.arrowRight);
    expect(value, 6);
    await press(LogicalKeyboardKey.arrowRight);
    expect(value, 6, reason: 'held at the top');
    expect(onSlider(), isTrue, reason: 'the arrow kept the focus');
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(value, 4, reason: 'held at the bottom');
    expect(onSlider(), isTrue);
    expect(ends, <int>[6, 5, 4], reason: 'a held arrow ends nothing');
  });

  testWidgets('#1011 ME-4 from a value outside its range, a step lands '
      'inside it, by key or by a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    late int value;
    Future<void> at45() async {
      value = 45;
      await pump(
        tester,
        StatefulBuilder(
          key: UniqueKey(),
          builder: (context, setState) => SizedBox(
            width: 300,
            child: SgSlider(
              value: value,
              min: 3,
              max: 30,
              label: 'Pace',
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      );
    }

    await at45();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 45, reason: 'no step up past the end');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 30, reason: 'one step, and inside');

    await at45();
    tester.semantics.performAction(
      find.semantics.byLabel('Pace'),
      SemanticsAction.decrease,
    );
    await tester.pump();
    expect(value, 30);
    handle.dispose();
  });

  testWidgets('#1007 a slider nobody can move is not a Tab stop', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 300,
        child: SgSlider(
          value: 5,
          min: 4,
          max: 6,
          label: 'Pace',
          onChanged: null,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
  });

  // #1039: a long press is a key's too, the context-menu key's or
  // Shift+F10's, as a desktop's context menu opens.
  final longPresses = <String, Widget Function(VoidCallback longPress)>{
    'SgTappable': (longPress) => SgTappable(
      onTap: () {},
      onLongPress: longPress,
      child: const SizedBox(width: 200, height: 48),
    ),
    'SgTappable with no tap': (longPress) => SgTappable(
      onTap: null,
      onLongPress: longPress,
      child: const SizedBox(width: 200, height: 48),
    ),
    'SgSpeakerButton': (longPress) => SgSpeakerButton(
      onPressed: () {},
      onLongPress: longPress,
      semanticLabel: 'Pronounce',
    ),
  };
  final longPressKeys = <String, Future<void> Function(WidgetTester)>{
    'the context-menu key': (tester) =>
        tester.sendKeyEvent(LogicalKeyboardKey.contextMenu),
    'Shift+F10': (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    },
  };
  for (final MapEntry(key: name, value: build) in longPresses.entries) {
    for (final MapEntry(key: keyName, value: send) in longPressKeys.entries) {
      testWidgets('#1039 $name: Tab reaches it, $keyName long-presses it', (
        tester,
      ) async {
        var longPressed = 0;
        await pump(tester, build(() => longPressed++));

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await send(tester);
        await tester.pump();
        expect(longPressed, 1);
      });
    }
  }

  testWidgets('#1039 an umlaut key: the context-menu key types its capital', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(tester, SgUmlautBar(controller: controller));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(controller.text, 'Ä');
  });

  testWidgets('#1039 F10 without Shift is no long press', (tester) async {
    var longPressed = 0;
    await pump(tester, longPresses['SgTappable']!(() => longPressed++));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pump();
    expect(longPressed, 0);
  });

  testWidgets('#745 an umlaut key: Tab reaches it, Enter types it', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(tester, SgUmlautBar(controller: controller));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, 'ä');
  });

  testWidgets('#745 a control nobody can press is not a Tab stop', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SgButton(label: 'Off', onPressed: null),
          SgChip(label: 'A2.1'),
        ],
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
  });

  for (final chrome in AdaptiveChrome.values) {
    testWidgets('#1049 a switch (${chrome.name}): Tab reaches it, the ring '
        'shows around it while keys are in use, and Space turns it', (
      tester,
    ) async {
      var on = false;
      await pump(
        tester,
        AdaptiveChromeScope(
          chrome: chrome,
          child: StatefulBuilder(
            builder: (context, setState) => AdaptiveSwitch(
              value: on,
              onChanged: (value) => setState(() => on = value),
              semanticLabel: 'Auto-advance',
            ),
          ),
        ),
      );
      CustomPaint ring() => tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(SgFocusable),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(ring().foregroundPainter, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring().foregroundPainter, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(on, isTrue);
    });
  }

  testWidgets("#1049 Material's own focus halo is off: one indicator", (
    tester,
  ) async {
    await pump(
      tester,
      AdaptiveSwitch(value: false, onChanged: (_) {}, semanticLabel: 'x'),
    );
    final overlay = tester.widget<Switch>(find.byType(Switch)).overlayColor!;
    expect(overlay.resolve(<WidgetState>{WidgetState.focused})!.a, 0);
  });

  testWidgets('#745 the ring shows only while keys are in use', (tester) async {
    await pump(tester, SgButton(label: 'Start', onPressed: () {}));
    CustomPaint ring() => tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(SgFocusable),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(ring().foregroundPainter, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring().foregroundPainter, isNotNull);

    // A touch hides it again: the highlight follows the input in use.
    await tester.tap(find.byType(SgButton));
    await tester.pump();
    expect(ring().foregroundPainter, isNull);
  });
}
