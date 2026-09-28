import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// #1021: Tab, as a keyboard's learner would, until the control with the
/// focus holds [target]; fails if it never does within [max] presses.
Future<void> tabTo(WidgetTester tester, Finder target, {int max = 60}) async {
  for (var i = 0; i < max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) continue;
    final holding = find.descendant(
      of: find.byElementPredicate((element) => element == focused),
      matching: target,
    );
    if (holding.evaluate().isNotEmpty) return;
  }
  fail('$max Tabs never reached $target');
}

/// Enter on the focused control, and the frames after it.
Future<void> enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}
