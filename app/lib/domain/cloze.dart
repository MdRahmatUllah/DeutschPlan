/// FR-T2-10: where a cloze card blanks its sentence
/// (`study-session-states.md`, Cloze rules).
///
/// Plain Dart: no Flutter, no drift.
library;

import 'package:deutschplan/domain/text_norm.dart';

/// A gap in a sentence, as offsets into it.
typedef ClozeGap = ({int start, int end});

/// The headword in [sentence], or its inflected form: the first word whose
/// search key starts with the headword's — `Rechnungen` for `Rechnung`. A
/// verb's key loses its infinitive ending first, so `arbeitet` counts for
/// `arbeiten`; a phrase is matched whole. Null when the sentence has none of
/// these, and the card stays plain.
///
/// ponytail: a prefix, not a stemmer. A separable verb split across the
/// sentence ("stehe … auf") is not found and falls back to the plain card;
/// a real lemmatiser if too many do.
ClozeGap? clozeGap(String sentence, String german, {String? pos}) {
  final headword = german.trim();
  if (headword.contains(' ')) {
    final at = sentence.toLowerCase().indexOf(headword.toLowerCase());
    return at < 0 ? null : (start: at, end: at + headword.length);
  }

  var key = searchKey(headword, stripArticle: false);
  if (pos == 'verb' && key.length > minKey + 1) {
    key = key.replaceFirst(_infinitive, '');
  }
  for (final match in _word.allMatches(sentence)) {
    final token = searchKey(match[0]!, stripArticle: false);
    // A short key only as itself: "in" must not blank "ins", "Uhr" not "Uhren"
    // … which is also fine as itself.
    final hit = key.length < minKey ? token == key : token.startsWith(key);
    if (hit) return (start: match.start, end: match.end);
  }
  return null;
}

/// Below this a key matches only whole words.
const int minKey = 3;

final RegExp _word = RegExp(r'\p{L}+', unicode: true);
final RegExp _infinitive = RegExp(r'e?n$');
