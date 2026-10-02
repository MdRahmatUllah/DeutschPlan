import 'dart:isolate';

import 'package:flutter/foundation.dart' show immutable;
import 'package:sogda/data/db/app_database.dart' show Word;
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/domain/answer_check.dart' show meaningAnswers;
import 'package:sogda/domain/edit_distance.dart';
import 'package:sogda/domain/text_norm.dart';

/// The four tiers of `search.md`, in the order BR-SEARCH-01 puts them.
enum SearchTier {
  /// The word, spelled any of the ways it can be spelled.
  exact,

  /// The query is the start of the word, the meaning or the Bangla.
  startsWith,

  /// Close enough to be a typo (BR-SEARCH-03).
  similar,

  /// Not the headword — a sentence that uses it.
  inSentences,
}

/// One word in the result list.
@immutable
class WordHit {
  const WordHit({required this.word, required this.tier, required this.rank});

  final Word word;
  final SearchTier tier;

  /// Where it sits inside its tier. Lower first.
  final double rank;

  String get uid => word.uid;
}

/// One sentence in the "In sentences" group.
@immutable
class SentenceHit {
  const SentenceHit({
    required this.wordUid,
    required this.german,
    required this.translation,
    required this.head,
    required this.article,
    required this.step,
    this.runs = const <(String, bool)>[],
    this.translationRuns = const <(String, bool)>[],
  });

  final String wordUid;
  final String german;

  /// In the first meaning language, or English where it has none (#1188).
  final String? translation;

  /// The headword the sentence belongs to, shown above it.
  final String head;
  final String? article;

  /// Its step, shown after it: "die Straße · A1.1".
  final String step;

  /// [german] in runs, each marked when it is a word the query matched.
  final List<(String, bool)> runs;

  /// [translation] in runs, the words the query matched marked, when the
  /// sentence was found by its translation (#1193); empty when it wasn't.
  final List<(String, bool)> translationRuns;
}

/// FTS5's `highlight()` output — matches between  and  — as runs of
/// text, each marked or not.
List<(String, bool)> markedRuns(String marked) {
  final runs = <(String, bool)>[];
  var inside = false;
  final text = StringBuffer();
  void flush() {
    if (text.isNotEmpty) runs.add((text.toString(), inside));
    text.clear();
  }

  for (final unit in marked.runes) {
    if (unit == 1 || unit == 2) {
      flush();
      inside = unit == 1;
    } else {
      text.writeCharCode(unit);
    }
  }
  flush();
  return runs;
}

/// What one query answers with.
@immutable
class SearchResults {
  const SearchResults({required this.words, required this.sentences});

  const SearchResults.empty()
    : words = const <WordHit>[],
      sentences = const <SentenceHit>[];

  final List<WordHit> words;
  final List<SentenceHit> sentences;

  bool get isEmpty => words.isEmpty && sentences.isEmpty;

  /// The tiers that have something in them, in BR-SEARCH-01 order. The screen
  /// draws a heading per group and skips the empty ones.
  List<SearchTier> get tiers => <SearchTier>[
    for (final tier in SearchTier.values)
      if (tier == SearchTier.inSentences
          ? sentences.isNotEmpty
          : words.any((hit) => hit.tier == tier))
        tier,
  ];

  List<WordHit> inTier(SearchTier tier) =>
      words.where((hit) => hit.tier == tier).toList();
}

/// Search over the course.
///
/// Every query goes through [ContentDao], which is attached to the database —
/// and the database runs on a background isolate (`AppDatabase.open`), so the
/// work is off the UI isolate by construction rather than by this class
/// remembering to move it. The ranking that happens here is over at most
/// [_trigramCandidateLimit] rows of short strings; `search_repository_test`
/// measures it at course scale.
class SearchRepository {
  SearchRepository(this._content);

  final ContentDao _content;

  /// The caps `search.md` asks for: under 40 rows plus 10 sentences. Split
  /// across the tiers rather than applied to the total, so a query with three
  /// hundred prefix matches cannot push the similar words off the end.
  static const int exactLimit = 10;
  static const int startsWithLimit = 20;
  static const int similarLimit = 10;
  static const int sentenceLimit = 10;

  /// How many prefix rows to fetch. Wider than [startsWithLimit] because the
  /// exact-meaning pass reads the same list, and a word whose meaning *is* the
  /// query is worth finding even when eighty others start with it.
  static const int _prefixLimit = 200;

  /// Tier 3 asks the trigram index for candidates and ranks them here.
  static const int _trigramCandidateLimit = 400;

  /// The trigram tokenizer indexes three-character runs, so a shorter query
  /// has nothing to match and tier 3 is skipped rather than run empty.
  static const int _minimumTrigramLength = 3;

  /// Tier 4 needs two characters (#736). One letter prefix-matches most of
  /// the course's sentences, and bm25 ranked them all: the slowest search
  /// there was, for sentences that share only a first letter with the query.
  static const int _minimumSentenceLength = 2;

  /// BR-SEARCH-03: a longer query earns a longer leash, because a typo in a
  /// compound is further from the word than a typo in "Haus".
  static const int _longQueryLength = 5;

  /// The longest query searched, in characters (#691 EX-13): a pasted page
  /// built an OR of thousands of trigrams and ranked 400 rows against it.
  /// The course's longest headword is 61 and its longest meaning 70, so any
  /// of them can still be typed whole. R1's field and R2's German stop here
  /// too, so what is searched is what shows.
  static const int maxQueryLength = 80;

  /// How many words the course has (`meta.word_count`): R1's "5,433 words,
  /// none spelled like this" (#139). Null when the course doesn't say.
  Future<int?> courseWords() async => int.tryParse(
    await _content.contentMeta('word_count').getSingleOrNull() ?? '',
  );

  /// [step] keeps every tier to one step (L2's search icon), in each query,
  /// so the caps count that step's rows only.
  ///
  /// [meanings] adds the learner's meaning languages beyond English and
  /// Bangla (#1121), whose words are found by their meaning there, after the
  /// German, English and Bangla ones in each tier.
  Future<SearchResults> search(
    String query, {
    String? step,
    Meanings? meanings,
  }) async {
    // NFC's nukta letters, as `bangla` is stored: the exact tier matches the
    // column as typed, and a keyboard may type ড় as its one letter (#716).
    final trimmed = query.trim();
    final raw = nfc(
      trimmed.runes.length > maxQueryLength
          ? String.fromCharCodes(trimmed.runes.take(maxQueryLength))
          : trimmed,
    );
    if (raw.isEmpty) return const SearchResults.empty();

    final key = searchKey(raw);
    final alt = searchKeyAlt(raw);

    final seen = <String>{};
    final words = <WordHit>[];

    void take(Iterable<WordHit> hits, int limit) {
      var taken = 0;
      for (final hit in hits) {
        // De-duplicated by uid across tiers, and marked even past the cap: a
        // word this tier found and had no room for still belongs to this
        // tier. Letting it fall through would file a word that starts with
        // the query under *Similar words*.
        if (!seen.add(hit.uid)) continue;
        if (taken == limit) continue;
        words.add(hit);
        taken++;
      }
    }

    // One prefix query for two tiers. It is the widest scan of the four, and
    // the exact-meaning pass needs the same rows: running it twice both cost
    // twice and gave the meaning pass a shorter list to look through than the
    // one it was meant to search.
    final prefixed = key.isEmpty
        ? const <PrefixMatchesResult>[]
        : await _content
              .prefixMatches(_prefixQuery(key), step, _prefixLimit)
              .get();

    final other = await _inOtherLanguages(raw, step, meanings);
    take(<WordHit>[
      ...await _exact(raw, key, alt, step, prefixed),
      ...other.exact,
    ], exactLimit);
    take(<WordHit>[
      ..._startsWith(prefixed),
      ...other.startsWith,
    ], startsWithLimit);
    take(await _similar(key, alt, step), similarLimit);

    return SearchResults(
      words: words,
      sentences: await _sentences(
        raw,
        key,
        alt,
        step,
        meanings?.choice.primary ?? 'en',
      ),
    );
  }

  /// Tier 1. The three spellings a word answers to, plus its meanings.
  ///
  /// `bangla` is matched raw: a Bangla query is not what [searchKey]
  /// normalises, so it has to hit the column as typed.
  Future<List<WordHit>> _exact(
    String raw,
    String key,
    String alt,
    String? step,
    List<PrefixMatchesResult> prefixed,
  ) async {
    final rows = await _content.exactMatches(key, alt, raw, step).get();
    final hits = <String, WordHit>{
      for (final row in rows)
        row.uid: WordHit(word: row, tier: SearchTier.exact, rank: -_freq(row)),
    };

    // An English query is a meaning, not a headword: "street" has to find
    // "die Straße". The prefix index is the cheapest way to get the candidate
    // rows; whether it is really an exact meaning is decided here, because
    // `english` holds a synonym list and FTS would match any one word of it.
    for (final row in prefixed) {
      final word = row.w;
      if (hits.containsKey(word.uid)) continue;
      if (_meanings(word.english).contains(key)) {
        hits[word.uid] = WordHit(
          word: word,
          tier: SearchTier.exact,
          rank: -_freq(word),
        );
      }
    }

    // BR-SEARCH-01: higher frequency first inside a tier. But the spelling as
    // typed first (#734): a word reached only through the umlaut fold
    // (`search_key_alt`: "schön" folds to `schon`) goes after every word
    // keyed as the query is, or "schön" would open schon and "Bär" bar.
    final folded = <String>{
      for (final row in rows)
        if (row.searchKey != key && row.bangla != raw) row.uid,
    };
    final sorted = hits.values.toList()..sort(_byRank);
    return <WordHit>[
      ...sorted.where((hit) => !folded.contains(hit.uid)),
      ...sorted.where((hit) => folded.contains(hit.uid)),
    ];
  }

  /// Tiers 1 and 2 in the learner's languages beyond English and Bangla
  /// (#1121): [CourseMeanings.find] in each, the words in [step] only, the
  /// most frequent first.
  Future<({List<WordHit> exact, List<WordHit> startsWith})> _inOtherLanguages(
    String raw,
    String? step,
    Meanings? meanings,
  ) async {
    const none = (exact: <WordHit>[], startsWith: <WordHit>[]);
    if (meanings == null) return none;
    final key = meaningKey(raw);
    final exact = <String>{};
    final startsWith = <String>{};
    for (final lang in meanings.choice.languages) {
      if (lang == 'en' || lang == 'bn') continue;
      final found = await meanings.course.find(lang, key);
      exact.addAll(found.exact);
      startsWith.addAll(found.startsWith);
    }
    startsWith.removeAll(exact);
    if (exact.isEmpty && startsWith.isEmpty) return none;
    // Each tier's rows apart, each capped as the German prefix tier is.
    Future<Map<String, Word>> read(Set<String> uids) async => <String, Word>{
      if (uids.isNotEmpty)
        for (final row
            in await _content
                .wordsByUids(uids.toList(), step, _prefixLimit)
                .get())
          row.uid: row,
    };
    final rows = <String, Word>{
      ...await read(exact),
      ...await read(startsWith),
    };
    List<WordHit> hits(Set<String> uids, SearchTier tier) => <WordHit>[
      for (final uid in uids)
        if (rows[uid] case final word?)
          WordHit(word: word, tier: tier, rank: -_freq(word)),
    ]..sort(_byRank);
    return (
      exact: hits(exact, SearchTier.exact),
      startsWith: hits(startsWith, SearchTier.startsWith),
    );
  }

  /// Tier 2. FTS ranks these; frequency breaks the ties BR-SEARCH-01 cares
  /// about, scaled small enough that it cannot reorder two different ranks.
  List<WordHit> _startsWith(List<PrefixMatchesResult> rows) {
    return <WordHit>[
      for (final row in rows)
        WordHit(
          word: row.w,
          tier: SearchTier.startsWith,
          // `rank` is FTS5's bm25, negative and smaller when better. A row
          // with no rank sorts last rather than first.
          rank: (row.rank ?? 0) + _frequencyBonus(row.w),
        ),
    ]..sort(_byRank);
  }

  /// Tier 3. Trigram candidates, kept if they are within BR-SEARCH-03's
  /// distance, ranked by distance first and frequency second.
  Future<List<WordHit>> _similar(String key, String alt, String? step) async {
    if (key.length < _minimumTrigramLength) return const <WordHit>[];

    final budget = key.length > _longQueryLength ? 3 : 2;
    final rows = await _content
        .trigramCandidates(_trigramQuery(key), step, _trigramCandidateLimit)
        .get();

    final hits = <WordHit>[];
    for (final row in rows) {
      // Both keys, because the word was indexed under both and the learner
      // typed one of them: "Tur" is 0 from `tur` and 1 from `tuer`.
      final distance = _closest(row, key, alt, budget);
      if (distance > budget) continue;
      hits.add(
        WordHit(
          word: row,
          tier: SearchTier.similar,
          // Distance dominates; a prefix match and then frequency break ties.
          rank:
              distance * 10 -
              (row.searchKey.startsWith(key) ? 1 : 0) +
              _frequencyBonus(row),
        ),
      );
    }

    return hits..sort(_byRank);
  }

  /// Tier 4. The sentence and the headword it belongs to.
  ///
  /// `examples_fts` folds umlauts but keeps ß: "Tür" is indexed as `tur`,
  /// "Straße" as `straße`. The key alone (`tuer`, `strasse`) matched neither,
  /// so the query asks for every form the German can take: the folded key,
  /// the text as typed, and the key respelled (`tuer` → `tur`, `strasse` →
  /// `straße`). Those go to the German column only: `tur`* in the English
  /// is "Turn on the light". The key itself searches both, so "house" still
  /// finds the sentences that mean it. Each comes with its translation into
  /// [lang], the first meaning language (#1188).
  Future<List<SentenceHit>> _sentences(
    String raw,
    String key,
    String alt,
    String? step,
    String lang,
  ) async {
    if (key.length < _minimumSentenceLength) return const <SentenceHit>[];
    final german = <String>{alt, raw.toLowerCase(), _respelled(key)}
      ..remove(key);
    String any(Iterable<String> forms) =>
        forms.map((form) => _prefixQuery(form, columns: false)).join(' OR ');
    final rows = await _content
        .sentenceMatches(
          lang,
          german.isEmpty
              ? any(<String>[key])
              : '${any(<String>[key])} OR german : (${any(german)})',
          step,
          sentenceLimit,
        )
        .get();
    final hits = <SentenceHit>[
      for (final row in rows)
        SentenceHit(
          wordUid: row.wordUid,
          german: row.german,
          translation: row.translation,
          head: row.head,
          article: row.article,
          step: row.step,
          runs: markedRuns(row.marked ?? row.german),
        ),
    ];
    // English is in `examples_fts`, and Bangla has no lines (#598).
    if (lang == 'en' || lang == 'bn') return hits;
    // #1193: a Polish or Russian learner never sees the English a hit may
    // have matched ("dom" in "domestic"): the hits whose German is marked
    // come first, then those whose translation has the query, marked there,
    // and the ones that show no match last.
    final meaning = meaningKey(raw);
    final all = <SentenceHit>[
      for (final hit in hits) _markedInTranslation(hit, meaning),
      ...await _byTranslation(raw, lang, step, hits),
    ];
    int rank(SentenceHit hit) => hit.runs.any((run) => run.$2)
        ? 0
        : hit.translationRuns.isNotEmpty
        ? 1
        : 2;
    return <SentenceHit>[
      for (var tier = 0; tier < 3; tier++)
        ...all.where((hit) => rank(hit) == tier),
    ].take(sentenceLimit).toList();
  }

  /// [hit] with [key]'s words marked in its translation, when its German has
  /// nothing marked (FTS matched its English) and the translation has them.
  static SentenceHit _markedInTranslation(SentenceHit hit, String key) {
    final translation = hit.translation;
    if (translation == null || hit.runs.any((run) => run.$2)) return hit;
    final runs = markedWords(translation, key);
    if (!runs.any((run) => run.$2)) return hit;
    return SentenceHit(
      wordUid: hit.wordUid,
      german: hit.german,
      translation: translation,
      head: hit.head,
      article: hit.article,
      step: hit.step,
      runs: hit.runs,
      translationRuns: runs,
    );
  }

  /// #1193: tier 4's sentences found by their translation into [lang] (a
  /// Polish or Russian learner's), at most [sentenceLimit], none [found]
  /// already. A line is found as #1121 finds a word by its
  /// meaning: a word of it starts with the query, [meaningKey]ed, so ł and ё
  /// may be typed as l and е. Lines that start with it come first, then the
  /// most frequent words'. Its German has nothing to mark, so the matched
  /// words are marked in its translation.
  Future<List<SentenceHit>> _byTranslation(
    String raw,
    String lang,
    String? step,
    List<SentenceHit> found,
  ) async {
    final key = meaningKey(raw);
    if (key.length < _minimumSentenceLength) return const <SentenceHit>[];
    final starts = <_KeyedLine>[];
    final within = <_KeyedLine>[];
    for (final line in await _keyedLines(_content, lang)) {
      if (step != null && line.step != step) continue;
      if (line.key.startsWith(key)) {
        starts.add(line);
      } else if (line.key.contains(' $key')) {
        within.add(line);
      }
    }
    int byFreq(_KeyedLine a, _KeyedLine b) => b.freq.compareTo(a.freq);
    // A line FTS found already may come back: room for those, then dropped.
    final wanted = <_KeyedLine>[
      ...starts..sort(byFreq),
      ...within..sort(byFreq),
    ].take(sentenceLimit).toList();
    if (wanted.isEmpty) return const <SentenceHit>[];
    final rows = <(String, int), ExamplesWithTranslationResult>{
      for (final row
          in await _content
              .examplesWithTranslation(
                lang,
                <String>{for (final line in wanted) line.uid}.toList(),
              )
              .get())
        (row.wordUid, row.ord): row,
    };
    final seen = <(String, String)>{
      for (final hit in found) (hit.wordUid, hit.german),
    };
    return <SentenceHit>[
      for (final line in wanted)
        if (rows[(line.uid, line.ord)] case final row?
            when seen.add((row.wordUid, row.german)))
          SentenceHit(
            wordUid: row.wordUid,
            german: row.german,
            translation: row.translation,
            head: row.head,
            article: row.article,
            step: row.step,
            runs: <(String, bool)>[(row.german, false)],
            translationRuns: markedWords(row.translation, key),
          ),
    ];
  }

  /// The key as the German may be spelled: ae/oe/ue folded to the bare
  /// vowel, as `examples_fts` indexes an umlaut, and ss as ß, which it keeps.
  /// Over-generating ("neue" → `neu`) only widens an OR.
  static String _respelled(String key) => key
      .replaceAllMapped(RegExp('ae|oe|ue'), (match) => match[0]![0])
      .replaceAll('ss', 'ß');

  int _closest(Word row, String key, String alt, int budget) {
    final first = editDistance(row.searchKey, key, limit: budget);
    if (first == 0) return 0;
    final second = editDistance(row.searchKeyAlt, alt, limit: budget);
    return second < first ? second : first;
  }

  /// A fraction of a rank step, so frequency orders words FTS scored the same
  /// without ever moving one past a word FTS scored better.
  double _frequencyBonus(Word word) => -_freq(word) / 1000;

  /// `freq` is nullable in the course: a word the workbook left blank is not
  /// a zero-frequency word, but it has to sort somewhere, and last is the
  /// honest place.
  static double _freq(Word word) => (word.freq ?? 0).toDouble();

  static int _byRank(WordHit a, WordHit b) {
    final byRank = a.rank.compareTo(b.rank);
    // Frequency and rank can still tie, and an unstable order would make the
    // list jump between identical queries.
    return byRank != 0 ? byRank : a.uid.compareTo(b.uid);
  }

  /// The meanings in an `english` cell, normalised the same way the query is:
  /// `checkMeaning`'s own rule ([meaningAnswers], #645). "bank (river)"
  /// answers to "bank" and to "bank river"; "stop (bus/tram)" never to "tram".
  static Set<String> _meanings(String english) =>
      <String>{for (final form in meaningAnswers(english)) searchKey(form)}
        ..remove('');

  /// `{search_key english bangla} : "k"*` — a prefix query, column-filtered to
  /// the three things a learner searches by. [columns] is false for
  /// `examples_fts`, which has no such columns.
  static String _prefixQuery(String key, {bool columns = true}) {
    final term = '${_quote(key)}*';
    return columns ? '{search_key english bangla} : $term' : term;
  }

  /// The query's trigrams, ORed. A typo shares most of them, which is what
  /// makes this a candidate set rather than a match.
  static String _trigramQuery(String key) {
    final grams = <String>{
      for (var i = 0; i + _minimumTrigramLength <= key.length; i++)
        key.substring(i, i + _minimumTrigramLength),
    };
    return grams.map(_quote).join(' OR ');
  }

  /// Wraps a term as an FTS5 string literal.
  ///
  /// The quotes are what stop a term being parsed as syntax — a query of
  /// `OR` or `NEAR` is otherwise an operator. Everything that reaches here is
  /// a [searchKey], which has no double quote in it to escape, and
  /// `search_repository_test` holds that invariant rather than leaving it
  /// implied; the doubling stays because it is what makes the quoting correct
  /// rather than correct-by-coincidence.
  ///
  /// Control characters go (#738): SQLite reads the MATCH as a C string, so a
  /// NUL would end it inside the quotes, and "Search failed".
  static String _quote(String value) =>
      '"${value.replaceAll(_control, '').replaceAll('"', '""')}"';

  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F-\x9F]');

  /// BR-SEARCH-04. The app opens these in an in-app browser; it makes no
  /// request itself, which is why they are built here and not fetched.
  static Map<WebSource, Uri> webLinks(String term) {
    final encoded = Uri.encodeComponent(term.trim());
    return <WebSource, Uri>{
      WebSource.duden: Uri.parse(
        'https://www.duden.de/suchen/dudenonline/$encoded',
      ),
      WebSource.dwds: Uri.parse('https://www.dwds.de/wb/$encoded'),
      WebSource.wiktionary: Uri.parse(
        'https://de.wiktionary.org/wiki/$encoded',
      ),
      WebSource.linguee: Uri.parse(
        'https://www.linguee.de/deutsch-englisch/search?query=$encoded',
      ),
      WebSource.google: Uri.parse('https://www.google.com/search?q=$encoded'),
    };
  }
}

/// The five chips on the Search header, in the order they are drawn.
enum WebSource {
  duden('Duden'),
  dwds('DWDS'),
  wiktionary('Wiktionary'),
  linguee('Linguee'),
  google('Google');

  const WebSource(this.label);

  final String label;
}

/// [text] in runs with the words [key] (a [meaningKey]) matched marked: the
/// text's words keyed one by one, the key's words found in a row, its last
/// one as a prefix, as tier 4 matched the line (#1193). The punctuation
/// around them stays unmarked: «pani,» marks «pani».
List<(String, bool)> markedWords(String text, String key) {
  final want = key.split(' ');
  // Each key word of the text, with the span of the word it came from.
  final words = <(String, int, int)>[
    for (final word in RegExp(r'\S+').allMatches(text))
      for (final part in meaningKey(word[0]!).split(' '))
        if (part.isNotEmpty) (part, word.start, word.end),
  ];
  for (var i = 0; i + want.length <= words.length; i++) {
    var matches = true;
    for (var j = 0; j < want.length && matches; j++) {
      final word = words[i + j].$1;
      matches = j == want.length - 1
          ? word.startsWith(want[j])
          : word == want[j];
    }
    if (!matches) continue;
    var start = words[i].$2;
    var end = words[i + want.length - 1].$3;
    while (start < end && !_letter.hasMatch(text[start])) {
      start++;
    }
    while (end > start && !_letter.hasMatch(text[end - 1])) {
      end--;
    }
    return <(String, bool)>[
      if (start > 0) (text.substring(0, start), false),
      (text.substring(start, end), true),
      if (end < text.length) (text.substring(end), false),
    ];
  }
  return <(String, bool)>[(text, false)];
}

final RegExp _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A line's translation keyed for tier 4's search by it (#1193), with its
/// word's step and frequency.
typedef _KeyedLine = ({String uid, int ord, String step, int freq, String key});

/// [lang]'s lines, keyed once per content database on the first search in
/// it, off the UI isolate: some 10,500 lines, as `CourseMeanings` keys its
/// meanings.
// ponytail: kept while the database is open, as `loadCourseMeanings` is: a
// course update reaches it on the next start.
Future<List<_KeyedLine>> _keyedLines(ContentDao dao, String lang) {
  final byLang = _lineKeys[dao.attachedDatabase] ??=
      <String, Future<List<_KeyedLine>>>{};
  return byLang[lang] ??= () async {
    try {
      return await _keyOff(<(String, int, String, int, String)>[
        for (final row in await dao.exampleTranslationsIn(lang).get())
          (row.wordUid, row.ord, row.step, row.freq ?? 0, row.translation),
      ]);
    } on Object {
      // Not kept: the next search tries again.
      byLang.removeWhere((key, _) => key == lang);
      rethrow;
    }
  }();
}

final Expando<Map<String, Future<List<_KeyedLine>>>> _lineKeys =
    Expando<Map<String, Future<List<_KeyedLine>>>>();

/// [lines] keyed on an isolate of its own. Its closure holds [lines] alone:
/// one that shared [_keyedLines]'s would carry the cache's futures, which
/// can't be sent.
Future<List<_KeyedLine>> _keyOff(
  List<(String, int, String, int, String)> lines,
) => Isolate.run(
  () => <_KeyedLine>[
    for (final (uid, ord, step, freq, translation) in lines)
      (
        uid: uid,
        ord: ord,
        step: step,
        freq: freq,
        key: meaningKey(translation),
      ),
  ],
);
