/// Words a document never offers (BR-DOC-03), even when they're course
/// words: every learner meets them on day one, and offering them would bury
/// the words that matter. Written by the team (#1223).
library;

import 'package:sogda/domain/documents/lemmatiser.dart';

/// Articles, pronouns and their inflected forms, the commonest prepositions
/// and conjunctions, as written (lower case). Checked on the token, before
/// lemmatising: "meinen" here is the possessive, and the rare verb is lost
/// with it.
final Set<String> stopForms = <String>{
  // Articles.
  'der', 'die', 'das', 'den', 'dem', 'des',
  'ein', 'eine', 'einen', 'einem', 'einer', 'eines',
  'kein', 'keine', 'keinen', 'keinem', 'keiner', 'keines',
  // Personal and reflexive pronouns.
  'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr',
  'mich', 'dich', 'sich', 'uns', 'euch',
  'mir', 'dir', 'ihm', 'ihn', 'ihnen', 'man',
  // Possessives.
  for (final stem in <String>['mein', 'dein', 'sein', 'ihr', 'unser', 'euer'])
    for (final ending in <String>['', 'e', 'en', 'em', 'er', 'es'])
      '$stem$ending',
  'eure', 'euren', 'eurem', 'eurer', 'eures',
  // Demonstratives, relatives and question words.
  for (final stem in <String>['dies', 'jed', 'welch', 'einig', 'manch'])
    for (final ending in <String>['e', 'en', 'em', 'er', 'es']) '$stem$ending',
  'wer', 'wen', 'wem', 'wessen', 'was', 'wo', 'wie', 'wann', 'warum',
  'denen', 'deren', 'dessen', 'mehrere', 'mehreren',
  // Prepositions, and their contractions with an article.
  'an', 'auf', 'aus', 'bei', 'bis', 'durch', 'für', 'gegen', 'hinter', 'in',
  'mit', 'nach', 'neben', 'ohne', 'seit', 'über', 'um', 'unter', 'von', 'vor',
  'zu', 'zwischen', 'ab',
  'am', 'im', 'ins', 'vom', 'zum', 'zur', 'beim', 'ans', 'aufs', 'fürs', 'ums',
  // Conjunctions.
  'und', 'oder', 'aber', 'denn', 'sondern', 'dass', 'weil', 'wenn', 'ob',
  'als', 'da', 'damit', 'obwohl', 'bevor', 'nachdem', 'sowie', 'sowohl',
  'weder', 'noch',
};

/// Verbs whose every form is a stop word: their forms are many (bin, wäre,
/// wird, kann…), so they're checked on the lemma.
const Set<String> stopLemmas = <String>{
  'sein',
  'haben',
  'werden',
  'können',
  'müssen',
  'dürfen',
  'sollen',
  'wollen',
  'mögen',
  'möchten',
};

/// Whether [token], read as [lemmas], is a stop word.
bool isStopWord(String token, List<LemmaEntry> lemmas) =>
    stopForms.contains(token.toLowerCase()) ||
    (lemmas.isNotEmpty &&
        lemmas.every((e) => stopLemmas.contains(Lemmatiser.headOf(e))));
