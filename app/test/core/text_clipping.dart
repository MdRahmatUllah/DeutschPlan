import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Fails when text under [within] is cut: laid out shorter than its own
/// lines, or faded at its edge.
///
/// A fixed-height box clips its text with no exception, so an overflow check
/// never sees it: the chip that showed half of "A2.2" at 200 % passed every
/// test (#314). An ellipsis is a choice, not a cut, and passes.
void expectNothingClipped(WidgetTester tester, {Finder? within}) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    within == null
        ? find.byType(RichText)
        : find.descendant(of: within, matching: find.byType(RichText)),
  );
  var checked = 0;
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    final lines = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(lines - 0.5),
      reason: '"$text" is cut: ${paragraph.size.height} of $lines tall',
    );
    expect(
      paragraph.debugHasOverflowShader,
      isFalse,
      reason: '"$text" is faded at its edge',
    );
    checked++;
  }
  expect(checked, greaterThan(0), reason: 'no text found to check');
}

/// Runs the rest of the test at [scale] times the system text size, as the
/// learner's font-size setting does.
void textAt(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
