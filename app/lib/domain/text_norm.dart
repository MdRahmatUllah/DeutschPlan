/// PIPE-04: the two search keys, byte-identical to the Python pipeline.
///
/// `tools/pipeline_steps.py` builds these into `content.db` at build time;
/// this builds them from whatever the learner types. They have to agree
/// exactly, because a mismatch is invisible on Search — the word is in the
/// database, the query looks right, and nothing comes back.
///
/// `tools/test_vectors.json` is what holds both sides to it, and
/// `test/domain/text_norm_test.dart` loads that file rather than restating it.
///
/// Plain Dart: no Flutter, no drift. `answer_check.dart` builds on it.
library;

/// Stripped from the front of a German headword before keying.
///
/// Nouns are authored with their article in its own column, but the German
/// column carries one often enough — and a learner typing "Haus" has to find
/// "das Haus".
const Set<String> germanArticles = <String>{
  'der',
  'die',
  'das',
  'den',
  'dem',
  'des',
};

/// Umlaut to the spelling a learner without a German keyboard types.
///
/// This is the German convention, not a diacritic strip: ä is `ae`, never `a`.
const Map<String, String> umlautExpansions = <String, String>{
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
  'ß': 'ss',
};

/// The same letters folded rather than expanded, for [searchKeyAlt].
///
/// Someone who types "Tur" for "Tür" is served by this one.
const Map<String, String> umlautFolds = <String, String>{
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'ß': 'ss',
};

/// The first key: umlauts expanded the German way. "Tür" becomes `tuer`.
String searchKey(String text) => _normalise(text, umlautExpansions);

/// The second key: umlauts folded to the bare vowel. "Tür" becomes `tur`.
String searchKeyAlt(String text) => _normalise(text, umlautFolds);

String _normalise(String text, Map<String, String> table) {
  final lowered = text.trim().toLowerCase();

  // Before the diacritic strip, or the decomposition below would take ä apart
  // into a + combining diaeresis and it would key as "a" rather than "ae".
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(table[char] ?? char);
  }

  final stripped = _stripLatinMarks(_dropPunctuation(buffer.toString()));
  final collapsed = stripped.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return _stripArticle(collapsed.toList());
}

String _stripArticle(List<String> parts) {
  // A whole word, so "Diebstahl" keeps its "die" and "der Tisch" loses its
  // "der". The article alone is a word in its own right and stays.
  if (parts.length >= 2 && germanArticles.contains(parts.first)) {
    return parts.sublist(1).join(' ');
  }
  return parts.join(' ');
}

/// Punctuation becomes a space, so "Guten Tag!" and "guten tag" key alike.
String _dropPunctuation(String text) => text.replaceAll(_punctuation, ' ');

/// The punctuation dropped before keying, as one class on one line.
///
/// It is written out rather than tested by Unicode category, because Dart has
/// no category lookup and because one category member matters: `search.md`
/// matches `bangla = raw`, so a danda inside a Bangla meaning has to survive.
/// `tools/pipeline_steps.py` carries the same characters as a frozenset, and
/// `tools/test_vectors.json` is what proves the two lists agree.
///
/// Kept on a single line: the formatter splits adjacent string literals, and a
/// character class broken across two of them closes early at the `]`.
final RegExp _punctuation = RegExp(r'[!-#%-*,-/:;?@\[-\]_{}¡§«¶·»¿‐-‧‰-⁞]');

/// Removes combining marks from Latin letters, and leaves other scripts alone.
///
/// Dropping every combining mark would mangle Bangla: its vowel signs are
/// combining characters too, and `search.md` matches `bangla = raw`, so a
/// Bangla meaning has to come back unchanged.
///
/// Dart has no NFD, so the decomposition is a table of the precomposed Latin
/// letters that actually turn up in German and in loan words. Anything not in
/// it passes through — which is the safe direction: an unmapped letter keys as
/// itself on both sides, while a wrong mapping keys differently from Python.
String _stripLatinMarks(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_latinFolds[char] ?? char);
  }
  return buffer.toString();
}

/// Precomposed Latin letters folded to their base.
///
/// Lower case only: `_normalise` lower-cases before this runs.
const Map<String, String> _latinFolds = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'ď': 'd',
  'đ': 'd',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'ø': 'o',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ţ': 't',
  'ť': 't',
  'ŧ': 't',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ý': 'y',
  'ÿ': 'y',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};
