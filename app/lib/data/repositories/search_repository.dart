import 'package:deutschplan/data/db/app_database.dart' show Word;
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/domain/edit_distance.dart';
import 'package:deutschplan/domain/text_norm.dart';
import 'package:flutter/foundation.dart' show immutable;

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
    required this.english,
    required this.head,
    required this.article,
    required this.step,
    this.runs = const <(String, bool)>[],
  });

  final String wordUid;
  final String german;
  final String? english;

  /// The headword the sentence belongs to, shown above it.
  final String head;
  final String? article;

  /// Its step, shown after it: "die Straße · A1.1".
  final String step;

  /// [german] in runs, each marked when it is a word the query matched.
  final List<(String, bool)> runs;
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

  /// BR-SEARCH-03: a longer query earns a longer leash, because a typo in a
  /// compound is further from the word than a typo in "Haus".
  static const int _longQueryLength = 5;

  /// How many words the course has (`meta.word_count`): R1's "5,593 words,
  /// none spelled like this" (#139). Null when the course doesn't say.
  Future<int?> courseWords() async => int.tryParse(
    await _content.contentMeta('word_count').getSingleOrNull() ?? '',
  );

  /// [step] keeps every tier to one step (L2's search icon), in each query,
  /// so the caps count that step's rows only.
  Future<SearchResults> search(String query, {String? step}) async {
    final raw = query.trim();
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

    take(await _exact(raw, key, alt, step, prefixed), exactLimit);
    take(_startsWith(prefixed), startsWithLimit);
    take(await _similar(key, alt, step), similarLimit);

    return SearchResults(
      words: words,
      sentences: await _sentences(raw, key, alt, step),
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

    // BR-SEARCH-01: higher frequency first inside a tier.
    return hits.values.toList()..sort(_byRank);
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
  /// finds the sentences that mean it.
  Future<List<SentenceHit>> _sentences(
    String raw,
    String key,
    String alt,
    String? step,
  ) async {
    if (key.isEmpty) return const <SentenceHit>[];
    final german = <String>{alt, raw.toLowerCase(), _respelled(key)}
      ..remove(key);
    String any(Iterable<String> forms) =>
        forms.map((form) => _prefixQuery(form, columns: false)).join(' OR ');
    final rows = await _content
        .sentenceMatches(
          german.isEmpty
              ? any(<String>[key])
              : '${any(<String>[key])} OR german : (${any(german)})',
          step,
          sentenceLimit,
        )
        .get();
    return <SentenceHit>[
      for (final row in rows)
        SentenceHit(
          wordUid: row.wordUid,
          german: row.german,
          english: row.english,
          head: row.head,
          article: row.article,
          step: row.step,
          runs: markedRuns(row.marked ?? row.german),
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

  /// The synonyms in an `english` cell, normalised the same way the query is.
  ///
  /// The workbook writes them with commas, semicolons or slashes. When
  /// `answer_check.dart` lands (`checkMeaning`) this is what it replaces.
  static final RegExp _separators = RegExp('[,;/]');

  /// A bracketed gloss: "house (building)" is still the meaning "house".
  static final RegExp _aside = RegExp(r'\([^)]*\)');

  static Set<String> _meanings(String english) {
    final keys = <String>{};
    for (final part in english.split(_separators)) {
      // Both forms, because the aside is sometimes the disambiguation the
      // learner typed: "bank (river)" answers to "bank" and to "bank river",
      // and `searchKey` only strips the brackets, not the words inside them.
      for (final form in <String>[part, part.replaceAll(_aside, '')]) {
        final key = searchKey(form);
        if (key.isNotEmpty) keys.add(key);
      }
    }
    return keys;
  }

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
  static String _quote(String value) => '"${value.replaceAll('"', '""')}"';

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
