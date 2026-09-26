import 'dart:math' as math;

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

/// Fails when text under [within] has more lines than its `maxLines` lets
/// it show: ended in "…", or cut at a word with none, so "birth" reads as
/// the whole of "birth certificate" (#550). [expectNothingClipped] lets
/// both pass; this is for text that must be read whole.
///
/// [within] null checks the whole screen, as the golden audit does (#551).
/// [hintsCut] lets a field's hint be cut, as every platform cuts a one-line
/// field's; the field's label, helper, error and counter still must show
/// whole.
void expectAllLinesShown(
  WidgetTester tester, {
  Finder? within,
  bool hintsCut = false,
}) {
  final texts = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  final elements = texts.evaluate().toList();
  expect(elements, isNotEmpty, reason: 'no text found to check');
  final cut = <String>[];
  for (final element in elements) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.didExceedMaxLines) continue;
    final text = paragraph.text.toPlainText();
    final field = hintsCut
        ? element.findAncestorWidgetOfExactType<InputDecorator>()
        : null;
    if (field != null && field.decoration.hintText == text) continue;
    cut.add('"$text"');
  }
  expect(cut, isEmpty, reason: 'cut to its maxLines: ${cut.join('; ')}');
}

/// Fails when a word in text under [within] breaks across two lines other
/// than at a soft hyphen: L2's "Stand / ard" at 200 % (#165). A cut word
/// reads as two; a long compound may break at its syllables
/// (`DpText.allowBreaks`), and text may wrap at a space, a dash, a slash or
/// a dot (a file name's).
void expectNoWordBroken(
  WidgetTester tester, {
  Finder? within,
  bool syllables = true,
}) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    within == null
        ? find.byType(RichText)
        : find.descendant(of: within, matching: find.byType(RichText)),
  );
  final offered = RegExp('[^\\s\u00AD​/.·–—-]{2,}');
  final whole = RegExp('[^\\s​/.·–—-]{2,}');
  final broken = <String>[];
  for (final paragraph in paragraphs) {
    // The text as laid out: a span's screen-reader label (its soft hyphens
    // dropped, #162) would shift every offset.
    final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
    // A soft hyphen is a break the text offers, unless [syllables] is off:
    // then a word must not break even there (#419 draws no hyphen yet).
    for (final word in (syllables ? offered : whole).allMatches(text)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      );
      if (boxes.isEmpty) continue;
      // On two lines when two of its boxes don't overlap vertically. Not by
      // their tops: Bangla digits beside a Latin "%" come from two fonts,
      // whose boxes on one line start at different heights.
      final lowestTop = boxes.map((box) => box.top).reduce(math.max);
      final highestBottom = boxes.map((box) => box.bottom).reduce(math.min);
      if (lowestTop >= highestBottom - 1) {
        broken.add('"${word[0]}" in "$text"');
      }
    }
  }
  expect(broken, isEmpty, reason: 'broken mid-word: ${broken.join('; ')}');
}

/// Android 14+'s text scaling, which is nonlinear: small text grows by the
/// whole factor, large text by less, and 100 sp not at all (#165). At 200 %,
/// measured on the emulator (API 36): 14 → 28, 24 → 40, 30 → 48, 100 → 100,
/// so a box sized `scale(96)` stays about 97. Flutter's test scaler is
/// linear, which hid that; the golden audit takes this one.
/// ponytail: four measured points, interpolated, and other factors take the
/// same curve in proportion; Android's own tables if it ever matters.
class AndroidTextScaler extends TextScaler {
  const AndroidTextScaler(this.factor);

  final double factor;

  static const List<(double, double)> _at200 = <(double, double)>[
    (0, 0),
    (14, 28),
    (24, 40),
    (30, 48),
    (100, 100),
  ];

  @override
  double scale(double fontSize) {
    for (var i = 1; i < _at200.length; i++) {
      final (x0, y0) = _at200[i - 1];
      final (x1, y1) = _at200[i];
      if (fontSize <= x1) {
        final doubled = y0 + (y1 - y0) * (fontSize - x0) / (x1 - x0);
        return fontSize + (doubled - fontSize) * (factor - 1);
      }
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => AndroidTextScaler(factor.clamp(minScaleFactor, maxScaleFactor));

  @override
  bool operator ==(Object other) =>
      other is AndroidTextScaler && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;
}

/// Runs the rest of the test at [scale] times the system text size, as the
/// learner's font-size setting does.
void textAt(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
