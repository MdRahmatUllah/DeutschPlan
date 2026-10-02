/// #1229: a photographed page as on-device OCR read it (`doc-import.md`,
/// FR-D1-03), before `cleanPages` makes the document's text of it.
library;

/// One word as OCR read it, and how sure it was, 0 to 1. Null when the
/// engine doesn't say (ML Kit on iOS).
typedef OcrWord = ({String text, double? confidence});

/// A page: its lines, top to bottom, each its words in reading order.
class OcrPage {
  const OcrPage(this.lines);

  final List<List<OcrWord>> lines;

  /// The page's text, a line a line, for `cleanPages` (which joins a word
  /// broken across a line end).
  String get text => <String>[
    for (final line in lines)
      if (line.isNotEmpty) line.map((w) => w.text).join(' '),
  ].join('\n');

  /// FR-D1-03: the mean of the words' confidence. Null when no word says,
  /// and then nothing is offered to check.
  double? get confidence {
    final known = <double>[
      for (final line in lines)
        for (final word in line) ?word.confidence,
    ];
    if (known.isEmpty) return null;
    return known.reduce((a, b) => a + b) / known.length;
  }
}

/// FR-D1-03: a page whose mean word confidence is below this offers *Check
/// the text* before it's read.
// ponytail: the spec's 0.7; #1229 tunes it on the fixtures' blurred photo
// once the engine runs on the device.
const double ocrCheckBelow = 0.7;

/// Whether *Check the text* opens: any page read below [ocrCheckBelow].
bool needsCheck(List<OcrPage> pages) =>
    pages.any((page) => (page.confidence ?? 1) < ocrCheckBelow);

/// The words *Check the text* marks: each read below [ocrCheckBelow].
Set<String> unsureWords(List<OcrPage> pages) => <String>{
  for (final page in pages)
    for (final line in page.lines)
      for (final word in line)
        if ((word.confidence ?? 1) < ocrCheckBelow) word.text,
};
