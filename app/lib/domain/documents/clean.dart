/// #1224: a document's pages as one clean text (`03-domain/document-matcher.md`,
/// pipeline step 2). What D2 shows and the tokens' offsets point into.
library;

import 'package:sogda/domain/text_norm.dart';

/// [pages] as one text: spaces and ligatures normalised, words hyphenated
/// across a line end joined («Ver-↵waltung» → Verwaltung, «E-↵Mail» →
/// E-Mail), and page numbers and the headers and footers repeated on most
/// pages dropped. Pages are separated by a blank line.
String cleanPages(List<String> pages) {
  final lines = <List<String>>[
    for (final page in pages) _normalise(page).split('\n'),
  ];
  final repeated = pages.length < 2 ? const <String>{} : _repeated(lines);
  final kept = <String>[
    for (final page in lines)
      page
          .where(
            (l) => !_pageNumber.hasMatch(l) && !repeated.contains(_shape(l)),
          )
          .join('\n')
          .trim(),
  ];
  return _joinHyphens(kept.where((p) => p.isNotEmpty).join('\n\n'));
}

const Map<String, String> _replacements = <String, String>{
  '\r\n': '\n',
  '\r': '\n',
  '­': '', // a soft hyphen
  ' ': ' ',
  ' ': ' ',
  ' ': ' ',
  ' ': ' ',
  '\t': ' ',
  'ﬁ': 'fi', // ligatures a PDF's text layer keeps
  'ﬂ': 'fl',
  'ﬀ': 'ff',
  'ﬃ': 'ffi',
  'ﬄ': 'ffl',
};

String _normalise(String page) {
  var text = page;
  for (final MapEntry(key: from, value: to) in _replacements.entries) {
    text = text.replaceAll(from, to);
  }
  return nfc(text)
      .split('\n')
      .map((l) => l.replaceAll(RegExp(' {2,}'), ' ').trim())
      .join('\n');
}

/// «7», «- 7 -», «Seite 2 von 3», «2/3».
final RegExp _pageNumber = RegExp(
  r'^(-\s*)?(Seite\s+)?\d{1,3}(\s*(von|/)\s*\d{1,3})?(\s*-)?$',
);

/// A line with its digits blurred, so «Seite 1» and «Seite 2» are one
/// footer.
String _shape(String line) => line.replaceAll(RegExp(r'\d+'), '#');

/// Lines among the first or last two of a page that appear so on at least
/// half the pages (and two): a letterhead, a footer with the address.
Set<String> _repeated(List<List<String>> pages) {
  final counts = <String, int>{};
  for (final page in pages) {
    final lines = page.where((l) => l.isNotEmpty).toList();
    final edges = <String>{
      ...lines.take(2),
      ...lines.skip(lines.length < 2 ? 0 : lines.length - 2),
    };
    for (final line in edges) {
      counts.update(_shape(line), (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final needed = (pages.length / 2).ceil().clamp(2, pages.length);
  return <String>{
    for (final MapEntry(key: shape, value: n) in counts.entries)
      if (n >= needed) shape,
  };
}

/// A word broken at a line end: lower case goes on as one word, a capital
/// starts a hyphenated compound's next part.
String _joinHyphens(String text) => text
    // A suspended hyphen stays one: «Haus-↵und Gartenpflege».
    .replaceAllMapped(
      RegExp(r'(\p{L})-\n((?:und|oder|bis|sowie)\b)', unicode: true),
      (m) => '${m[1]}- ${m[2]}',
    )
    .replaceAllMapped(
      RegExp(r'(\p{L})-\n(\p{Ll})', unicode: true),
      (m) => '${m[1]}${m[2]}',
    )
    .replaceAllMapped(
      RegExp(r'(\p{L})-\n(\p{Lu})', unicode: true),
      (m) => '${m[1]}-${m[2]}',
    );

/// A document's title by default (`doc-words.md`): its first line with a
/// letter in it, past a letter's salutation («Sehr geehrte Damen und
/// Herren,» says who it's to, not what it's about), without a trailing
/// comma or colon, cut at a word end to [max] characters. Null for a text
/// with none, where D1 names it by its day.
String? documentTitle(String body, {int max = 60}) {
  final lines = <String>[
    for (final l in body.split('\n'))
      if (_letter.hasMatch(l)) l.trim(),
  ];
  if (lines.isEmpty) return null;
  final line = lines
      .firstWhere((l) => !salutationLine.hasMatch(l), orElse: () => lines.first)
      .replaceAll(RegExp(r'[,;:]+$'), '');
  if (line.length <= max) return line;
  final space = line.lastIndexOf(' ', max);
  return '${line.substring(0, space > 0 ? space : max).trimRight()}…';
}

final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// A line that is a salutation alone: «Liebe Eltern,», «Sehr geehrte Frau
/// Okafor,», «Guten Tag,». No part of the title, nor of the first sentence
/// (`splitText`, #1297).
final RegExp salutationLine = RegExp(
  r'^(liebe[rs]?|sehr geehrte[rs]?|hallo|guten (tag|morgen|abend))\b.*,$',
  caseSensitive: false,
);
