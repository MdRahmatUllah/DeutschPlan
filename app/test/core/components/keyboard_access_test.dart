import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
      'each way, and it holds at its ends with the focus kept', (tester) async {
    var value = 5;
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
