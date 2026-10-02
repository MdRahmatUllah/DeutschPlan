/// #1224: a clean text's sentences and words (`03-domain/document-matcher.md`,
/// pipeline steps 3 and 4), each word with its offset into the text, so D2
/// can mark it where it stands.
library;

import 'dart:math' show min;

import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/stop_words.dart';

/// A word, or a clause mark («,», «;», «:») that the lemmatiser reads as the
/// end of a clause.
class DocToken {
  const DocToken(this.text, this.start);

  final String text;

  /// Its offset in the text.
  final int start;

  int get end => start + text.length;

  bool get isWord => text.length > 1 || _letter.hasMatch(text);

  @override
  String toString() => text;
}

class DocSentence {
  const DocSentence(this.start, this.end, this.tokens);

  /// Its span in the text: [start, end).
  final int start;
  final int end;
  final List<DocToken> tokens;

  List<String> get words => <String>[for (final t in tokens) t.text];
}

final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// Words (hyphenated ones whole: E-Mail, Online-Banking; gender forms too:
/// Kund:innen) and clause marks, but not a number's («245,80», «10:30»). A
/// lone letter («z. B.», the B of «B1») is no word.
final RegExp _token = RegExp(
  // Two letters or more, or one before a hyphen (E-Mail).
  r'\p{L}\p{M}*(?:(?:\p{L}\p{M}*)+(?:-\p{L}\p{M}*(?:\p{L}\p{M}*)*)*'
  r'|(?:-\p{L}\p{M}*(?:\p{L}\p{M}*)*)+)'
  '(?:$genderSuffix)?'
  r'|(?<!\d)[,;:]|[,;:](?!\d)',
  unicode: true,
);

/// What's never a word to learn: e-mail addresses, web addresses, IBANs.
/// Numbers, dates and amounts are digits, which no token takes.
final List<RegExp> _skipped = <RegExp>[
  RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'),
  // Not the sentence's mark after it: «www.sogda.de:».
  RegExp(r'(https?://|www\.)\S*[^\s.,;:!?)]', caseSensitive: false),
  RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b'),
];

/// Abbreviations whose full stop ends no sentence, lower case.
const Set<String> _abbreviations = <String>{
  'z',
  'b',
  'd',
  'h',
  'u',
  'a',
  'o',
  'ä',
  's',
  'v',
  'nr',
  'str',
  'bzw',
  'ca',
  'dr',
  'prof',
  'usw',
  'etc',
  'ggf',
  'evtl',
  'inkl',
  'exkl',
  'tel',
  'fr',
  'hr',
  'abs',
  'vgl',
  'bzgl',
  'zzgl',
  'gem',
  'lt',
  'feb',
  'mär',
  'apr',
  'jun',
  'jul',
  'aug',
  'sep',
  'sept',
  'okt',
  'nov',
  'dez',
  'geb',
  'verh',
  'zt',
  'allg',
  'bsp',
  'tsd',
  'mio',
  'mrd',
  // From letters (#1260's review): Jan., e. V., z. Hd., Std., MwSt., i. A.,
  // Az.
  'jan',
  'e',
  'i',
  'hd',
  'std',
  'mwst',
  'ust',
  'az',
  'ziff',
  'kap',
  'gez',
};

/// [text] (from `cleanPages`) as sentences of tokens.
///
/// A sentence ends at «.», «!» or «?» before a space (a closing quote or
/// bracket may come between: «…ab.“ Danach»), at a blank line, and at a
/// line that ends in a comma when the next one starts with a capital (a
/// letter's greeting: «Sehr geehrte Frau Okafor,↵Vielen Dank …»). Not
/// after an abbreviation («z. B.», «Nr.») or a day or month as digits («am
/// 14. Oktober», «15.11.»), unless a pronoun or an article follows («Raum
/// 2. Wir …»). A year ends one («im Jahr 2025.»), and so does the stop
/// after an IBAN or an address.
List<DocSentence> splitText(String text) {
  final skipped = <(int, int)>[
    for (final pattern in _skipped)
      for (final m in pattern.allMatches(text)) (m.start, m.end),
  ];
  bool inSkipped(int i) => skipped.any((s) => i >= s.$1 && i < s.$2);

  final ends = <int>[];
  for (final m in _end.allMatches(text)) {
    if (inSkipped(m.start)) continue;
    if (text[m.start] == '.' &&
        !skipped.any((s) => s.$2 == m.start) &&
        !_endsSentence(text, m.start)) {
      continue;
    }
    ends.add(m.end);
  }
  ends.add(text.length);

  final sentences = <DocSentence>[];
  var start = 0;
  for (final end in ends) {
    if (end <= start) continue;
    final tokens = <DocToken>[
      for (final m in _token.allMatches(text.substring(start, end)))
        if (!inSkipped(start + m.start)) DocToken(m[0]!, start + m.start),
    ];
    if (tokens.any((t) => t.isWord)) {
      sentences.add(DocSentence(start, end, tokens));
    }
    start = end;
  }
  return sentences;
}

/// The most of a document's text Sogda reads (FR-D1-02).
const int docMaxChars = 20000;

/// [text] (from `cleanPages`) cut to [limit] characters, if it's longer:
/// at the last sentence end before the limit, or at the last word end if no
/// sentence ends there (pipeline step 1, FR-D1-02). `cut` says whether
/// anything went, for D1's note.
({String text, bool cut}) limitText(String text, {int limit = docMaxChars}) {
  if (text.length <= limit) return (text: text, cut: false);
  // A little past the limit, so a sentence ending on it is seen to end.
  // ponytail: only the head is split, so a 1 MB paste costs what 20 kB does.
  final head = text.substring(0, min(text.length, limit + 200));
  var end = 0;
  for (final sentence in splitText(head)) {
    if (sentence.end <= limit && sentence.end < head.length) end = sentence.end;
  }
  if (end == 0) {
    final space = text.lastIndexOf(RegExp(r'\s'), limit);
    end = space > 0 ? space : limit;
    // Never half a surrogate pair.
    if (_highSurrogate(text.codeUnitAt(end - 1))) end--;
  }
  return (text: text.substring(0, end).trimRight(), cut: true);
}

bool _highSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

final RegExp _end = RegExp(
  r'[.!?]+["“”»«’)]*(?=\s)|\n[ \t]*\n|,[ \t]*\n(?=[ \t]*\p{Lu})',
  unicode: true,
);

/// Whether the full stop at [dot] ends a sentence.
bool _endsSentence(String text, int dot) {
  var i = dot;
  while (i > 0 && RegExp(r'[\p{L}\d]', unicode: true).hasMatch(text[i - 1])) {
    i--;
  }
  final before = text.substring(i, dot);
  if (before.isEmpty) return true;
  // A day or a month (1–2 digits) is an ordinal or a date, before a noun, a
  // month or the sentence going on («am 14. Oktober», «am 14.10. um 10
  // Uhr», «bis 31.12. den Betrag», «der 2. Weltkrieg»). Only a capitalised
  // pronoun or article starts a new one («Raum 2. Wir warten»). A year or
  // an amount ends one.
  if (RegExp(r'^\d+$').hasMatch(before)) {
    if (before.length > 2) return true;
    final next = RegExp(
      r'^\s+(\p{L}+)',
      unicode: true,
    ).firstMatch(text.substring(dot + 1))?[1];
    return next != null &&
        next[0] != next[0].toLowerCase() &&
        stopForms.contains(next.toLowerCase());
  }
  return !_abbreviations.contains(before.toLowerCase());
}

/// Whether [token], a word the lemmatiser found no course word for, is
/// likely a name rather than a word outside the course (step 4). A name
/// has a capital in the middle of a sentence, isn't a compound of course
/// words ([compound]) and doesn't end like a noun («-ung», «-heit»…). After
/// a title («Frau Okafor») it always is; after an article or a determiner
/// («Ihr Jobcenter», «die Handwerker») it isn't, nor after an adjective or
/// an ordinal with an ending ([previousEntries], the course's reading of
/// [previous]: «wichtiger Schritt», «am ersten Login»). A preposition is no
/// such sign: «aus Syrien», «nach Deutschland» (#1270). A country in -ien
/// («Syrien») ends like a plural (Familien), so it reads as a noun.
bool likelyName(
  String token, {
  required bool sentenceStart,
  required bool compound,
  String? previous,
  List<LemmaEntry> previousEntries = const <LemmaEntry>[],
}) {
  final before = previous?.toLowerCase();
  if (before != null && _titles.hasMatch(before)) return true;
  if (sentenceStart || compound) return false;
  final first = token[0];
  if (first == first.toLowerCase() || token == token.toUpperCase()) {
    return false;
  }
  if (before != null && _determiners.hasMatch(before)) return false;
  if (before != null &&
      _inflected.hasMatch(before) &&
      previousEntries.any((e) => e.pos == 'adj' || e.pos == 'num')) {
    return false;
  }
  return !_nounEnding.hasMatch(token.toLowerCase());
}

final RegExp _inflected = RegExp(r'e[mnrs]?$');

final RegExp _titles = RegExp(r'^(frau|herr|herrn|familie|dr|prof)$');

final RegExp _determiners = RegExp(
  r'^(der|die|das|den|dem|des|am|im|zum|zur|vom|beim|ein|kein|mein|dein|sein|'
  r'ihr|unser|euer|eur|dies|jed|welch|viel|all)(e|en|em|er|es)?$',
);

final RegExp _nounEnding = RegExp(
  r'(ung|heit|keit|schaft|tion|sion|tät|ment|nis|tum|ling|chen|lein|ismus|'
  r'enz|anz|ik|ie|age|ur|ei|eur|innen)(en|s|n)?$',
);

/// The share of [sentences]' words that are German to the lemmatiser: a
/// course word, a stop word or a compound of course words. Names and
/// all-capital words (REWE, SEPA) say nothing either way, so a bank
/// statement full of them still counts as German. Below a half, D1 warns
/// that the text doesn't look German (FR-D1-04).
double germanShare(List<DocSentence> sentences, Lemmatiser lemmatiser) {
  var words = 0;
  var german = 0;
  for (final sentence in sentences) {
    final lemmas = lemmatiser.sentence(sentence.words);
    final first = sentence.tokens.indexWhere((t) => t.isWord);
    var previous = -1;
    for (final (i, token) in sentence.tokens.indexed) {
      if (!token.isWord) continue;
      final before = previous;
      previous = i;
      if (lemmas[i].isNotEmpty ||
          stopForms.contains(token.text.toLowerCase())) {
        words++;
        german++;
        continue;
      }
      // Capitals only (Bangla has no case, so it isn't).
      if (token.text != token.text.toLowerCase() &&
          token.text == token.text.toUpperCase()) {
        continue;
      }
      final compound = lemmatiser.compoundParts(token.text) != null;
      if (likelyName(
        token.text,
        sentenceStart: i == first,
        compound: compound,
        previous: before < 0 ? null : sentence.tokens[before].text,
        previousEntries: before < 0 ? const <LemmaEntry>[] : lemmas[before],
      )) {
        continue;
      }
      words++;
      if (compound) german++;
    }
  }
  return words == 0 ? 0 : german / words;
}

/// FR-D1-04's line.
const double germanThreshold = 0.5;
