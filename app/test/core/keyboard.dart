import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/sg_focusable.dart';

/// #1021: Tab, as a keyboard or a D-pad moves, until the focus is
/// [target]'s own: the [SgTappable] it finds, not a control inside it. Fails
/// when 60 presses never get there.
Future<void> tabTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 60; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    Element? owner;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      if (e.widget is! SgTappable) return true;
      owner = e;
      return false;
    });
    if (owner != null && target.evaluate().contains(owner)) return;
  }
  fail('Tab never reached $target');
}
