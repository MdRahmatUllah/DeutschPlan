/// FR-T2-10: where a cloze card blanks its sentence
/// (`study-session-states.md`, Cloze rules).
///
/// Plain Dart: no Flutter, no drift.
library;

import 'package:deutschplan/domain/text_norm.dart';

/// A gap in a sentence, as offsets into it.
typedef ClozeGap = ({int start, int end});

/// The headword in [sentence], or its inflected form, compared by search
/// key, token by token (#325):
///
/// - one word: the first token whose key starts with the headword's —
///   `Rechnungen` for `Rechnung`. A verb ([pos] `verb`) loses its infinitive
///   ending first, so `arbeitet` counts for `arbeiten`, and a participle
///   counts (`gelohnt`, `aufgegeben`), as does a separable verb's stem with
///   its particle later on ("räume … auf": the gap is `räume`);
/// - a reflexive verb without its `sich`, which the sentence says as
///   `mich`, `uns`, …;
/// - several words: all of them in a row (`Wie geht es Ihnen`, without the
///   headword's `?`); else the first of its words found, nouns before
///   longer words before shorter ones, an infinitive as a verb —
///   `Verfügung` for *zur Verfügung stellen*.
///
/// Null when the sentence has none of these, and the card stays plain.
///
/// ponytail: prefixes, not a stemmer. A strong verb's other vowel (`wächst`
/// for `wachsen`, `sieht` for `sehen`) is not found; a real lemmatiser if
/// too many are.
ClozeGap? clozeGap(String sentence, String german, {String? pos}) {
  final tokens = [
    for (final match in _word.allMatches(sentence))
      (
        start: match.start,
        end: match.end,
        key: searchKey(match[0]!, stripArticle: false),
      ),
  ];
  final all = [for (final match in _word.allMatches(german)) match[0]!];
  final reflexive = all.length > 1 && all.first.toLowerCase() == 'sich';
  final words = reflexive ? all.sublist(1) : all;
  if (words.isEmpty) return null;
  final keys = [for (final w in words) searchKey(w, stripArticle: false)];
  if (keys.length == 1) return _find(tokens, keys.single, verb: pos == 'verb');

  for (var i = 0; i + keys.length <= tokens.length; i++) {
    var j = 0;
    while (j < keys.length && tokens[i + j].key == keys[j]) {
      j++;
    }
    if (j == keys.length) {
      return (start: tokens[i].start, end: tokens[i + j - 1].end);
    }
  }

  // Capitalised past the first word: a noun ("sich Sorgen machen" too). The
  // first word as well before an infinitive: *Spaß machen*.
  final nounVerb =
      words.length == 2 &&
      words.last == words.last.toLowerCase() &&
      keys.last.endsWith('n');
  bool noun(int i) =>
      (i > 0 || reflexive || nounVerb) && words[i] != words[i].toLowerCase();
  final order = [for (var i = 0; i < words.length; i++) i]
    ..sort((a, b) {
      if (noun(a) != noun(b)) return noun(a) ? -1 : 1;
      final longer = keys[b].length.compareTo(keys[a].length);
      return longer != 0 ? longer : a.compareTo(b);
    });
  for (final i in order) {
    // Never an article, a pronoun or a question word on its own: "die" for
    // *Der Zweck heiligt die Mittel* blanked "diesem".
    if (keys[i].length < minKey || _functionWords.contains(keys[i])) continue;
    final infinitive =
        !noun(i) && keys[i].length > minKey + 1 && keys[i].endsWith('n');
    final hit = _find(
      tokens,
      keys[i],
      verb: infinitive,
      whole: keys[i].length <= minKey,
    );
    if (hit != null) return hit;
  }
  return null;
}

typedef _Token = ({int start, int end, String key});

/// [whole]: the key only as itself, not as a prefix.
ClozeGap? _find(
  List<_Token> tokens,
  String key, {
  required bool verb,
  bool whole = false,
}) {
  final stem = verb && key.length > minKey + 1
      ? key.replaceFirst(_infinitive, '')
      : key;
  for (final t in tokens) {
    // A short key only as itself: "in" must not blank "ins", "Uhr" not
    // "Uhren" … which is also fine as itself.
    final hit = whole || stem.length < minKey
        ? t.key == stem
        : t.key.startsWith(stem) || (verb && t.key.startsWith('ge$stem'));
    if (hit) return (start: t.start, end: t.end);
  }
  if (!verb) return null;
  for (final particle in _particles) {
    if (!key.startsWith(particle)) continue;
    final rest = key.substring(particle.length).replaceFirst(_infinitive, '');
    if (rest.length < minKey) continue;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i].key;
      final split =
          t.startsWith(rest) &&
          tokens.skip(i + 1).any((later) => later.key == particle);
      if (split ||
          t.startsWith('${particle}ge$rest') ||
          t.startsWith('${particle}zu$rest')) {
        return (start: tokens[i].start, end: tokens[i].end);
      }
    }
  }
  return null;
}

/// Below this a key matches only whole words.
const int minKey = 3;

/// Words a phrase's fallback never blanks alone, as search keys.
const Set<String> _functionWords = <String>{
  // articles
  'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem',
  'einer', 'eines', 'kein', 'keine', 'keinen', 'keinem', 'keiner',
  // pronouns
  'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'mich', 'dich', 'sich',
  'uns', 'euch', 'mir', 'dir', 'ihm', 'ihn', 'ihnen', 'man',
  // question words
  'was', 'wer', 'wie', 'wo', 'wann', 'warum', 'wen', 'wem', 'wessen',
  'welche', 'welcher', 'welches', 'welchen', 'woher', 'wohin',
  // conjunctions
  'und', 'oder', 'aber', 'dass', 'ob', 'wenn', 'als', 'denn', 'sondern',
};

final RegExp _word = RegExp(r'\p{L}+', unicode: true);
final RegExp _infinitive = RegExp(r'e?n$');

/// Separable prefixes, as search keys, a longer one before any it starts
/// with (`zusammen` before `zu`).
const List<String> _particles = <String>[
  'zurueck',
  'zusammen',
  'weiter',
  'vorbei',
  'heraus',
  'herein',
  'hinaus',
  'kennen',
  'spazieren',
  'kaputt',
  'statt',
  'teil',
  'frei',
  'fern',
  'wohl',
  'fest',
  'fort',
  'hin',
  'her',
  'los',
  'weg',
  'nach',
  'mit',
  'vor',
  'aus',
  'auf',
  'ein',
  'bei',
  'dar',
  'ab',
  'an',
  'zu',
  'um',
];
