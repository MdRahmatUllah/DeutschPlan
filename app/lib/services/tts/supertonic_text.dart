import 'package:deutschplan/services/tts/nfkd_latin.dart';

/// Supertonic 3's text front end: German as the model reads it (`tts.md`).
///
/// A port of the reference SDK's `UnicodeProcessor` (supertonic 1.3.1,
/// `core.py`), step for step, so the model is given what Supertone's own code
/// would give it. The steps are NFKD, emoji out, symbols normalised,
/// decorative symbols out, abbreviations expanded, punctuation spacing,
/// duplicate quotes, whitespace, a closing period, and the `<de>…</de>`
/// language tag.
///
/// Two changes, both for German. „ ‚ ‹ › and ↔, which the indexer lacks, are
/// replaced as the SDK replaces its other quotes and arrows. A character the
/// indexer still lacks is dropped, where the SDK would send the model -1.
class SupertonicText {
  SupertonicText(this._indexer);

  /// `unicode_indexer.json`: the model's index for each UTF-16 code unit, and
  /// -1 where it has none.
  final List<int> _indexer;

  /// The model's ids for [text], German.
  List<int> ids(String text) => <int>[
    for (final unit in prepare(text).codeUnits)
      if (unit < _indexer.length && _indexer[unit] >= 0) _indexer[unit],
  ];

  /// [text] prepared as the SDK prepares it, with the language tag.
  static String prepare(String text) {
    final decomposed = StringBuffer();
    for (final rune in text.runes) {
      if (_isEmoji(rune)) continue;
      decomposed.write(nfkdLatin[rune] ?? String.fromCharCode(rune));
    }
    var out = decomposed.toString();
    _symbols.forEach((from, to) => out = out.replaceAll(from, to));
    out = out.replaceAll(RegExp(r'[♥☆♡©\\]'), '');
    _abbreviations.forEach((from, to) => out = out.replaceAll(from, to));
    for (final mark in const <String>[',', '.', '!', '?', ';', ':', "'"]) {
      out = out.replaceAll(' $mark', mark);
    }
    out = out
        .replaceAllMapped(RegExp(r'''(["'`])\1+'''), (m) => m[1]!)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (!RegExp(r'''[.!?;:,'"')\]}…。」』】〉》›»]$''').hasMatch(out)) {
      out = '$out.';
    }
    return '<de>$out</de>';
  }

  /// The SDK's `_SYMBOL_REPLACEMENTS`, then the app's five.
  static const Map<String, String> _symbols = <String, String>{
    '–': '-',
    '‑': '-',
    '—': '-',
    '¯': ' ',
    '_': ' ',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '´': "'",
    '`': "'",
    '[': ' ',
    ']': ' ',
    '|': ' ',
    '/': ' ',
    '#': ' ',
    '→': ' ',
    '←': ' ',
    '„': '"',
    '‚': "'",
    '‹': "'",
    '›': "'",
    '↔': ' ',
  };

  static const Map<String, String> _abbreviations = <String, String>{
    '@': ' at ',
    'e.g.,': 'for example, ',
    'i.e.,': 'that is, ',
  };

  /// The SDK's emoji ranges, which leave U+1F650–1F67F in.
  static bool _isEmoji(int rune) =>
      (rune >= 0x1f300 && rune <= 0x1f64f) ||
      (rune >= 0x1f680 && rune <= 0x1faff) ||
      (rune >= 0x2600 && rune <= 0x27bf) ||
      (rune >= 0x1f1e6 && rune <= 0x1f1ff);
}
