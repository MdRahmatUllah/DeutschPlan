import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/ocr.dart';

/// #1229 FR-D1-03: a photographed page, and when it's checked first.
void main() {
  OcrWord w(String text, [double? confidence]) =>
      (text: text, confidence: confidence);

  test('a page is its lines, a line a line, its words in order', () {
    final page = OcrPage(<List<OcrWord>>[
      <OcrWord>[w('Sehr', 0.9), w('geehrte', 0.9), w('Frau', 0.9)],
      <OcrWord>[],
      <OcrWord>[w('die', 0.9), w('Ver-', 0.8)],
      <OcrWord>[w('waltung', 0.8)],
    ]);
    expect(page.text, 'Sehr geehrte Frau\ndie Ver-\nwaltung');
  });

  test('FR-D1-03 the page reads at its words\' mean confidence; below 0.7 '
      'it is checked, and its unsure words are marked', () {
    final sharp = OcrPage(<List<OcrWord>>[
      <OcrWord>[w('Die', 0.95), w('Miete', 0.9)],
    ]);
    final blurred = OcrPage(<List<OcrWord>>[
      <OcrWord>[w('Die', 0.9), w('Mlete', 0.4), w('ist', 0.6)],
    ]);
    expect(sharp.confidence, closeTo(0.925, 1e-9));
    expect(blurred.confidence, closeTo(0.6333, 1e-3));
    expect(needsCheck(<OcrPage>[sharp]), isFalse);
    expect(needsCheck(<OcrPage>[sharp, blurred]), isTrue);
    expect(unsureWords(<OcrPage>[sharp, blurred]), <String>{'Mlete', 'ist'});
  });

  test('an engine that gives no confidence never asks for a check', () {
    final page = OcrPage(<List<OcrWord>>[
      <OcrWord>[w('Hallo'), w('Welt')],
    ]);
    expect(page.confidence, isNull);
    expect(needsCheck(<OcrPage>[page]), isFalse);
    expect(unsureWords(<OcrPage>[page]), isEmpty);
  });

  test('exactly at the line is not below it', () {
    final page = OcrPage(<List<OcrWord>>[
      <OcrWord>[w('genau', ocrCheckBelow)],
    ]);
    expect(needsCheck(<OcrPage>[page]), isFalse);
  });
}
