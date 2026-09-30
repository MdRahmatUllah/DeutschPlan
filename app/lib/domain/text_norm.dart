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
///
/// [stripArticle] is on by default, because PIPE-04 says so and because the
/// pipeline's keys must not move. Turn it off for text that is not German:
/// `die` is an ordinary English verb, and stripping it turns the meaning
/// "die out" into "out".
String searchKey(String text, {bool stripArticle = true}) =>
    _normalise(text, umlautExpansions, stripArticle: stripArticle);

/// The second key: umlauts folded to the bare vowel. "Tür" becomes `tur`.
String searchKeyAlt(String text, {bool stripArticle = true}) =>
    _normalise(text, umlautFolds, stripArticle: stripArticle);

String _normalise(
  String text,
  Map<String, String> table, {
  required bool stripArticle,
}) {
  // Composed first, or "u" + combining diaeresis never matches the ü in the
  // table below. Dart has no NFC, so [nfc] spells out the letters whose NFC
  // form changes a key; anything else is handled by the combining-mark strip
  // further down. No trim: the split below drops the ends, on Python's
  // whitespace rather than Dart's (#716).
  final lowered = nfc(text.toLowerCase());

  // Before the diacritic strip, or the decomposition below would take ä apart
  // into a + combining diaeresis and it would key as "a" rather than "ae".
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(table[char] ?? char);
  }

  final stripped = _stripLatinMarks(_dropPunctuation(buffer.toString()));
  final collapsed = stripped.split(_whitespace).where((p) => p.isNotEmpty);
  return stripArticle ? _stripArticle(collapsed.toList()) : collapsed.join(' ');
}

/// A meaning in the course's other languages as a learner may type it
/// (#1120, #1121): Polish ł as l, which has no decomposition, so the Latin
/// strip keeps it (ą ć ę ń ó ś ź ż it folds already); Russian ё as е, as
/// Russians write it; and without the combining acute a stress guide puts on
/// a vowel. Apart from [searchKey], whose keys match the pipeline's.
String foldMeaning(String text) => text
    .replaceAll('ł', 'l')
    .replaceAll('Ł', 'L')
    .replaceAll('ё', 'е')
    .replaceAll('Ё', 'Е')
    .replaceAll('\u0301', '');

/// A meaning in the course's other languages keyed for search (#1121):
/// [foldMeaning], then [searchKey] with no article strip, since `die` is no
/// article in Russian or Polish.
String meaningKey(String text) =>
    searchKey(foldMeaning(text), stripArticle: false);

/// The letters whose NFC form changes a key, spelled out: Dart has no
/// `String.normalize`, and `tools/pipeline_steps.py` applies NFC.
///
/// German's umlauts are composed: an unmapped decomposed letter still loses
/// its mark below, but a decomposed ü would lose its umlaut instead of
/// becoming "ue".
const Map<String, String> _composed = <String, String>{
  'ä': 'ä',
  'ö': 'ö',
  'ü': 'ü',
  // The other way for Bangla's three nukta letters, which NFC takes apart
  // (composition exclusions): content.db and the pipeline's keys hold the
  // letter + nukta, and a keyboard may type the one precomposed letter. Left
  // alone, a word typed with it is two edits from the course's and wrong
  // (#655).
  '\u09DC': '\u09A1\u09BC',
  '\u09DD': '\u09A2\u09BC',
  '\u09DF': '\u09AF\u09BC',
};

/// [text] with [_composed]'s letters as NFC writes them: the umlauts
/// composed, Bangla's nukta letters taken apart. Search's exact tier matches
/// `bangla` with it too, as content.db stores it (#716).
String nfc(String text) {
  var result = text;
  for (final MapEntry(key: from, value: to) in _composed.entries) {
    result = result.replaceAll(from, to);
  }
  return result;
}

/// Python's whitespace (`str.isspace`), which `str.split()` in
/// `tools/pipeline_steps.py` splits the stored keys on. Dart's `\s` and `trim`
/// add U+FEFF and leave out U+001C–U+001F and U+0085 (#716).
final RegExp _whitespace = RegExp(
  '[\t-\r\x1C-\x20\x85\xA0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
);

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
/// Dart has no NFD, so the decomposition is [_latinBases], every precomposed
/// letter of U+00C0–U+024F and U+1E00–U+1EFF that Python's NFD takes apart
/// (#716). A letter with no decomposition (ø, ł, đ, ŧ) is not in it: Python
/// keeps it, and so does this. `tools/test_vectors.json`'s `latin_ranges`
/// holds the two sides to it, letter by letter.
String _stripLatinMarks(String text) {
  final buffer = StringBuffer();
  var baseWasLatin = false;

  for (final rune in text.runes) {
    if (rune >= _combiningStart && rune <= _combiningEnd) {
      // The same rule as Python's NFD strip: drop the mark when it sits on a
      // Latin letter, keep it otherwise. Bangla vowel signs are outside this
      // block entirely, so they never reach here.
      if (!baseWasLatin) buffer.writeCharCode(rune);
      continue;
    }

    final char = String.fromCharCode(rune);
    final folded = _latinFolds[char];
    baseWasLatin = folded != null || _isLatinLetter(rune);
    buffer.write(folded ?? char);
  }
  return buffer.toString();
}

/// Combining Diacritical Marks: the block every mark of [_latinBases]'s
/// letters decomposes into, so the one Python's NFD would produce.
const int _combiningStart = 0x0300;
const int _combiningEnd = 0x036F;

/// Python's test is "LATIN" in the letter's name. Over the ranges
/// [_latinBases] covers, that is every code point but × and ÷.
bool _isLatinLetter(int rune) =>
    (rune >= 0x61 && rune <= 0x7A) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0xC0 && rune <= 0x24F && rune != 0xD7 && rune != 0xF7) ||
    (rune >= 0x1E00 && rune <= 0x1EFF);

/// Each base, and the lower-case letters Python's NFD strip folds to it
/// (`_strip_latin_marks`). The umlauts are not here: [umlautExpansions] and
/// [umlautFolds] map them first. Lower case only: `_normalise` lower-cases
/// before this runs.
const Map<String, String> _latinBases = <String, String>{
  'a': 'àáâãåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
  'b': 'ḃḅḇ',
  'c': 'çćĉċčḉ',
  'd': 'ďḋḍḏḑḓ',
  'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
  'f': 'ḟ',
  'g': 'ĝğġģǧǵḡ',
  'h': 'ĥȟḣḥḧḩḫẖ',
  'i': 'ìíîïĩīĭįǐȉȋḭḯỉị',
  'j': 'ĵǰ',
  'k': 'ķǩḱḳḵ',
  'l': 'ĺļľḷḹḻḽ',
  'm': 'ḿṁṃ',
  'n': 'ñńņňǹṅṇṉṋ',
  'o': 'òóôõōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
  'p': 'ṕṗ',
  'r': 'ŕŗřȑȓṙṛṝṟ',
  's': 'śŝşšșṡṣṥṧṩ',
  't': 'ţťțṫṭṯṱẗ',
  'u': 'ùúûũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
  'v': 'ṽṿ',
  'w': 'ŵẁẃẅẇẉẘ',
  'x': 'ẋẍ',
  'y': 'ýÿŷȳẏẙỳỵỷỹ',
  'z': 'źżžẑẓẕ',
  'æ': 'ǣǽ',
  'ø': 'ǿ',
  'ſ': 'ẛ',
  'ʒ': 'ǯ',
};

/// [_latinBases] the other way round: a letter to its base.
final Map<String, String> _latinFolds = <String, String>{
  for (final MapEntry(key: base, value: letters) in _latinBases.entries)
    for (final letter in letters.runes) String.fromCharCode(letter): base,
};
