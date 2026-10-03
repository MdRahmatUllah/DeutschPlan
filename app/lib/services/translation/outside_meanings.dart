import 'package:sogda/data/repositories/translation_repository.dart';

/// One of Hy-MT2's answers for a word outside the course (#1233): the bare
/// word's [meaning], or the word as it reads in its sentence ([here]).
typedef MeaningSuggestion = ({String meaning, bool here});

/// The meaning of a word the course doesn't have, from Hy-MT2
/// (`document-matcher.md`, #1233): a suggestion, never a meaning by itself
/// (the lead's call on #1278). R2 offers it, labelled, and the learner picks
/// it or types their own (BR-DOC-07).
class OutsideMeanings {
  const OutsideMeanings(this._translations);

  final TranslationRepository _translations;

  /// Hy-MT2's suggestions for [word], into each of [languages] in turn (the
  /// learner's first meaning language, then the second). First the bare
  /// word's meaning, the headword's and in its base form, more often right
  /// (#1278's spot check). Then the word as it reads in [sentence], when that
  /// differs: the sense there, though often in the sentence's form. An
  /// in-sentence answer that isn't the word's (the sentence translated) is
  /// left out. The map grows as each language lands, so D2's card shows the
  /// first while the second runs, and with no model, or translation off, it
  /// ends empty. Cached (`translation_cache`).
  Stream<Map<String, List<MeaningSuggestion>>> of(
    String word,
    String sentence,
    List<String> languages, {
    Future<void>? abandoned,
  }) async* {
    final found = <String, List<MeaningSuggestion>>{};
    for (final lang in languages) {
      final suggestions = <MeaningSuggestion>[];
      Map<String, List<MeaningSuggestion>> grown(MeaningSuggestion one) {
        suggestions.add(one);
        found[lang] = List<MeaningSuggestion>.unmodifiable(suggestions);
        return Map<String, List<MeaningSuggestion>>.unmodifiable(found);
      }

      // The bare word's first, and shown at once: D2's card waits for it
      // alone, not for the sentence's run too.
      final bare = (await _translations.translate(
        word,
        from: 'de',
        to: lang,
        abandoned: abandoned,
      ))?.trim();
      // A compound's meaning may run longer (5 words: «কফি পাত্র গরম করার
      // যন্ত্র»); an explanation in place of a word doesn't pass.
      if (isTheWords(bare, most: 6)) yield grown((meaning: bare!, here: false));
      final here = (await _translations.translate(
        word,
        from: 'de',
        to: lang,
        context: sentence,
        abandoned: abandoned,
      ))?.trim();
      if (isTheWords(here) &&
          !suggestions.any(
            (s) => s.meaning.toLowerCase() == here!.toLowerCase(),
          )) {
        yield grown((meaning: here!, here: true));
      }
    }
    if (found.isEmpty) yield const <String, List<MeaningSuggestion>>{};
  }

  /// Whether [answer], asked for a word in its sentence, is that word's
  /// meaning rather than the sentence translated.
  /// ponytail: its shape, from #1233's spot check of 50 corpus words in
  /// Polish and Bangla. A word's meaning came back in 1 to 4 words («মাসের
  /// পর মাস ধরে»), and every answer of 5 or more, or one that ends as a
  /// sentence ends, was the sentence, however short the translation ran. A
  /// sentence answered in 4 words passes it. The bare word's answer is
  /// allowed [most] words more loosely: it risks an explanation, not the
  /// sentence.
  static bool isTheWords(String? answer, {int most = 4}) {
    final text = answer?.trim() ?? '';
    if (text.isEmpty || _sentenceEnd.hasMatch(text)) return false;
    return text.split(RegExp(r'\s+')).length <= most;
  }

  static final RegExp _sentenceEnd = RegExp(r'[.!?।]$');
}
