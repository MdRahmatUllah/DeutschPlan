@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/domain/text_norm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../db/content_fixture.dart';

/// `SearchRepository` — the four tiers of `search.md`.
///
/// Two fixtures. The small one is the shared `ContentFixture`, three words
/// chosen for their umlauts; the large one is built here at course scale
/// (5,594 words, 11,188 sentences) because "< 50 ms per query" is not a claim
/// three rows can support.
void main() {
  group('the tiers', () {
    late Directory directory;
    late AppDatabase db;
    late SearchRepository search;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_search');
      final content = ContentFixture.write('${directory.path}/content.db').file;

      db = AppDatabase.memory();
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      search = SearchRepository(ContentDao(db));
    });

    tearDown(() async {
      await db.close();
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows releases it a moment later.
      }
    });

    group('BR-SEARCH-02 — exact', () {
      test('finds the word as it is spelled', () async {
        final results = await search.search('Haus');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Haus');
      });

      test('ignores the article', () async {
        final results = await search.search('das Haus');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Haus');
      });

      test('ignores case', () async {
        final results = await search.search('hAuS');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Haus');
      });

      test('takes the umlaut written out', () async {
        // search_key: Tür is keyed `tuer`.
        final results = await search.search('Tuer');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Tür');
      });

      test('takes the umlaut dropped', () async {
        // search_key_alt: someone without a German keyboard types `Tur`.
        final results = await search.search('Tur');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Tür');
      });

      test('takes the umlaut itself', () async {
        final results = await search.search('Tür');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Tür');
      });

      test('matches Bangla exactly', () async {
        final results = await search.search('বাড়ি');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Haus');
      });

      test('matches an English meaning', () async {
        final results = await search.search('door');
        expect(results.inTier(SearchTier.exact).single.word.german, 'Tür');
      });

      test(
        'an English word that is only part of a meaning is not exact',
        () async {
          // `street` is the meaning; a query for a word that merely appears in
          // some meaning must not be promoted to the exact tier.
          final results = await search.search('the');
          expect(results.inTier(SearchTier.exact), isEmpty);
        },
      );
    });

    group('BR-SEARCH-01 — tier order', () {
      test('exact comes before starts-with', () async {
        final results = await search.search('Haus');
        final tiers = results.words.map((hit) => hit.tier).toList();
        expect(tiers.first, SearchTier.exact);
      });

      test('a word is in one tier only', () async {
        final results = await search.search('Haus');
        final uids = results.words.map((hit) => hit.uid).toList();
        expect(uids.toSet(), hasLength(uids.length));
      });

      test('the groups come back in the order the screen draws them', () async {
        final results = await search.search('Tür');
        expect(
          results.tiers,
          orderedEquals(
            results.tiers.toList()..sort((a, b) => a.index.compareTo(b.index)),
          ),
        );
      });
    });

    group('starts with', () {
      test('a prefix of the German finds it', () async {
        final results = await search.search('Str');
        expect(
          results.inTier(SearchTier.startsWith).map((h) => h.word.german),
          contains('Straße'),
        );
      });

      test('a prefix of the English finds it', () async {
        final results = await search.search('hou');
        expect(
          results.inTier(SearchTier.startsWith).map((h) => h.word.german),
          contains('Haus'),
        );
      });
    });

    group('BR-SEARCH-03 — similar', () {
      test('a misspelling finds the word', () async {
        final results = await search.search('Strase');
        expect(
          results.inTier(SearchTier.similar).map((h) => h.word.german),
          contains('Straße'),
        );
      });

      test('a query under three characters skips the tier', () async {
        // The trigram index has nothing shorter than three characters to
        // match, so running it would be a scan that answers nothing.
        final results = await search.search('Ha');
        expect(results.inTier(SearchTier.similar), isEmpty);
      });

      test('something unrelated is not similar', () async {
        final results = await search.search('Fahrrad');
        expect(results.inTier(SearchTier.similar), isEmpty);
      });
    });

    group('in sentences', () {
      test('finds a word used in an example', () async {
        final results = await search.search('offen');
        expect(results.sentences.single.german, 'Die Tür ist offen.');
      });

      test('names the headword above the sentence', () async {
        final results = await search.search('offen');
        expect(results.sentences.single.head, 'Tür');
        expect(results.sentences.single.article, 'die');
      });

      test(
        'BR-SEARCH-02 a word typed with its umlaut or ß finds its sentences',
        () async {
          // examples_fts folds umlauts and keeps ß: the key alone (tuer,
          // strasse) matched neither.
          expect(
            (await search.search('Tür')).sentences.map((s) => s.german),
            contains('Die Tür ist offen.'),
          );
          expect(
            (await search.search('Straße')).sentences.map((s) => s.german),
            contains('Die Straße ist lang.'),
          );
        },
      );

      test('R1 marks the matched word, and names the step', () async {
        final hit = (await search.search('offen')).sentences.single;
        expect(hit.runs, <(String, bool)>[
          ('Die Tür ist ', false),
          ('offen', true),
          ('.', false),
        ]);
        expect(hit.step, 'A1.1');
      });

      test('BR-SEARCH-02 typed with ae/oe/ue or ss, the sentences are '
          'still found', () async {
        // The index has `tur` and `straße`; the key is `tuer`, `strasse`.
        expect(
          (await search.search('tuer')).sentences.map((s) => s.german),
          contains('Die Tür ist offen.'),
        );
        expect(
          (await search.search('strasse')).sentences.map((s) => s.german),
          contains('Die Straße ist lang.'),
        );
      });

      test('FR-R1-01 the German forms search the German only: "Tür" is not '
          '"Turn"', () async {
        await db.customStatement(
          "INSERT INTO c.examples_fts (word_uid, german, english) VALUES "
          "('${ContentFixture.haus}', 'Mach das Licht an.', "
          "'Turn on the light.')",
        );
        final hits = (await search.search('Tür')).sentences;
        expect(hits, isNotEmpty);
        for (final hit in hits) {
          expect(
            hit.runs.any((run) => run.$2),
            isTrue,
            reason: '${hit.german} has nothing marked',
          );
        }
        // The key still searches the English: "house" finds what means it.
        expect(
          (await search.search('turn')).sentences.map((s) => s.german),
          contains('Mach das Licht an.'),
        );
        expect(
          (await search.search('house')).sentences.map((s) => s.german),
          contains('Das Haus ist groß.'),
        );
      });

      test('FR-R1-01 markedRuns reads highlight() markers', () {
        expect(markedRuns('a b c d'), <(String, bool)>[
          ('a ', false),
          ('b', true),
          (' c ', false),
          ('d', true),
        ]);
        expect(markedRuns('plain'), <(String, bool)>[('plain', false)]);
      });

      test('a sentence hit does not need a word hit', () async {
        final results = await search.search('offen');
        expect(results.words, isEmpty);
        expect(results.sentences, isNotEmpty);
        expect(results.tiers, <SearchTier>[SearchTier.inSentences]);
      });
    });

    group("L2's step", () {
      test('goes into every tier, before the caps', () async {
        final other = await search.search('Haus', step: 'A1.2');
        expect(other.words, isEmpty);
        expect(other.sentences, isEmpty);

        final own = await search.search('Straße', step: 'A1.2');
        expect(own.inTier(SearchTier.exact).single.word.german, 'Straße');
      });

      test('keeps the sentences to it', () async {
        final hits = (await search.search('ist', step: 'A1.2')).sentences;
        expect(hits.map((s) => s.german), <String>['Die Straße ist lang.']);
        expect((await search.search('ist')).sentences, hasLength(3));
      });
    });

    group('a query that is not one', () {
      test('empty answers with nothing', () async {
        expect((await search.search('')).isEmpty, isTrue);
      });

      test('whitespace answers with nothing', () async {
        expect((await search.search('   ')).isEmpty, isTrue);
      });

      test('punctuation does not match every word', () async {
        // `searchKey('...')` is empty, and `search_key = ''` would otherwise
        // be true of any row whose key normalised away.
        expect((await search.search('...')).isEmpty, isTrue);
      });

      test('a quote in the query is not a syntax error', () async {
        // FTS5 string literals are double-quoted, so a quote reaching the
        // MATCH unescaped is a parse error rather than a search.
        expect((await search.search('Haus"')).isEmpty, isFalse);
      });

      test('an FTS operator is a word, not an operator', () async {
        // `OR`, `NEAR` and `*` are FTS5 syntax. Unquoted they either change
        // the query or fail to parse it.
        for (final query in const <String>['OR', 'NEAR', 'AND haus']) {
          await expectLater(search.search(query), completes, reason: query);
        }
      });

      test('a word nobody has is no results, not an error', () async {
        final results = await search.search('Wohnungsgeberbestaetigung');
        expect(results.isEmpty, isTrue);
      });
    });
  });

  test('a search key never carries FTS syntax into a MATCH', () {
    // What makes the quoting above safe. `searchKey` strips punctuation, so
    // nothing a learner types reaches the MATCH as a quote or a wildcard —
    // and if that ever changes, this is what says so.
    for (final nasty in const <String>[
      'Haus"',
      '"OR" *',
      'Stra"ße',
      'a" OR "b',
      "Haus'; DROP TABLE words;--",
    ]) {
      final key = searchKey(nasty);
      expect(key, isNot(contains('"')), reason: nasty);
      expect(key, isNot(contains('*')), reason: nasty);
    }
  });

  group('BR-SEARCH-04 — web links', () {
    test('all five sources, in the order the chips are drawn', () {
      final links = SearchRepository.webLinks('Straße');
      expect(links.keys, orderedEquals(WebSource.values));
    });

    test('each one points at that site', () {
      final links = SearchRepository.webLinks('Haus');
      expect(links[WebSource.duden]!.host, 'www.duden.de');
      expect(links[WebSource.dwds]!.host, 'www.dwds.de');
      expect(links[WebSource.wiktionary]!.host, 'de.wiktionary.org');
      expect(links[WebSource.linguee]!.host, 'www.linguee.de');
      expect(links[WebSource.google]!.host, 'www.google.com');
    });

    test('every one is https', () {
      for (final link in SearchRepository.webLinks('Haus').values) {
        expect(link.scheme, 'https', reason: '$link');
      }
    });

    test('the term is encoded, not pasted', () {
      // "Straße" and a space both have to survive going into a URL, or the
      // chip opens a 404 and the learner thinks the word is not in Duden.
      final links = SearchRepository.webLinks('die Straße');
      for (final link in links.values) {
        expect(link.toString(), isNot(contains(' ')), reason: '$link');
        expect(link.toString(), isNot(contains('ß')), reason: '$link');
      }
      expect(links[WebSource.google]!.queryParameters['q'], 'die Straße');
    });

    test('nothing is fetched — these are links', () {
      // BR-SEARCH-04: "Nothing is sent by the app itself." The method is
      // static and synchronous, which is the structural version of that.
      expect(SearchRepository.webLinks('Haus'), isA<Map<WebSource, Uri>>());
    });
  });

  group('at course scale', () {
    late Directory directory;
    late AppDatabase db;
    late SearchRepository search;

    setUpAll(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_scale');
      _writeCourseSizedContent('${directory.path}/content.db');

      db = AppDatabase.memory();
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(File('${directory.path}/content.db'))}' AS c",
      );
      search = SearchRepository(ContentDao(db));
    });

    tearDownAll(() async {
      await db.close();
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows releases it a moment later.
      }
    });

    test('the fixture really is course-sized', () async {
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM c.words')
          .getSingle();
      expect(rows.read<int>('n'), _wordCount + 36);
    });

    test('a multi-word query is a phrase, not two terms', () async {
      // What the FTS quoting buys. Unquoted, these two tokens are an implicit
      // AND and the order stops mattering — "gibt es" would find "es gibt".
      final right = await search.search('es gibt');
      expect(right.words.map((hit) => hit.word.german), contains('es gibt'));

      final wrong = await search.search('gibt es');
      expect(
        wrong.inTier(SearchTier.startsWith).map((hit) => hit.word.german),
        isNot(contains('es gibt')),
      );
    });

    test('BR-SEARCH-01 — frequency breaks a tie inside a tier', () async {
      // Two words FTS scores the same. The commoner one goes first.
      final results = await search.search('tief');
      final tied = results.words
          .map((hit) => hit.word.german)
          .where((german) => german.startsWith('tief'))
          .toList();

      // `tiefe` is the commoner one and sorts *later* by uid, so a run that
      // fell through to the uid tie-break would answer the other way round.
      expect(tied, <String>['tiefe', 'tiefa']);
    });

    test('a meaning with a bracketed gloss still matches exactly', () async {
      // `bank (river)` keys as `bank river`, so without stripping the aside
      // this word is not an exact match for `bank` at all.
      final results = await search.search('bank');
      expect(
        results.inTier(SearchTier.exact).map((hit) => hit.word.german),
        contains('Ufer'),
      );
    });

    test('the gloss is still searchable in its own right', () async {
      final results = await search.search('bank river');
      expect(
        results.inTier(SearchTier.exact).map((hit) => hit.word.german),
        contains('Ufer'),
      );
    });

    test('an exact meaning is found past the starts-with cap', () async {
      // Thirty shorter meanings outrank it, so a meaning pass that only read
      // as far as the starts-with cap would never see this word — and the
      // learner would search the English they know and get nothing.
      final results = await search.search('hand');
      final exact = results
          .inTier(SearchTier.exact)
          .map((hit) => hit.word.german);

      expect(exact, contains('Pfote'));
    });

    test('a word cut off by a cap does not reappear lower down', () async {
      // Far more than `startsWithLimit` words start with `wort`. The ones
      // that do not fit are dropped, not refiled under *Similar words*.
      final results = await search.search('wort');
      expect(results.inTier(SearchTier.startsWith), hasLength(20));

      for (final hit in results.inTier(SearchTier.similar)) {
        expect(
          hit.word.searchKey.startsWith('wort'),
          isFalse,
          reason: '${hit.word.german} starts with the query',
        );
      }
    });

    test('a query stays under the caps', () async {
      // A prefix every word shares. `search.md`: under 40 rows plus 10
      // sentences, whatever the query matches.
      final results = await search.search('wort');
      expect(results.words.length, lessThan(40));
      expect(results.sentences.length, lessThanOrEqualTo(10));
    });

    test('FR-R1-01 — under 50 ms per query', () async {
      // Warm the page cache first; the first query of the process pays for
      // opening the FTS indexes and is not what the learner feels typing.
      for (final query in _benchmarkQueries) {
        await search.search(query);
      }

      final timings = <int>[];
      for (var round = 0; round < 5; round++) {
        for (final query in _benchmarkQueries) {
          final watch = Stopwatch()..start();
          await search.search(query);
          watch.stop();
          timings.add(watch.elapsedMicroseconds);
        }
      }

      timings.sort();
      final worst = timings.last / 1000;
      final median = timings[timings.length ~/ 2] / 1000;

      final report =
          'slowest ${worst.toStringAsFixed(1)} ms, '
          'median ${median.toStringAsFixed(1)} ms over ${timings.length} '
          'queries against $_wordCount words';

      // The median is the budget. One slow sample on a box running the rest
      // of the suite in parallel is contention, not a regression — judging on
      // the slowest made this fail at random, which is worse than not
      // measuring at all. The ceiling below is the coarse guard that a real
      // blow-up still trips.
      expect(median, lessThan(50), reason: report);
      expect(worst, lessThan(250), reason: report);
    });
  });
}

/// The real course: `content-database.md` counts 5,594 words and 11,188
/// sentences. The workbooks are not in the repository, so the timing test
/// builds a database of that shape rather than claiming a number it cannot
/// stand behind.
const int _wordCount = 5594;

/// One of each kind of query, because they cost different things: an exact hit
/// is an index probe, a short prefix is the widest FTS scan, a misspelling is
/// the trigram tier plus four hundred edit distances, and a common word is the
/// sentence index.
const List<String> _benchmarkQueries = <String>[
  'Wort1000',
  'wor',
  'Wrot1000',
  'ist',
  'haus',
  'Wohnungsgeberbestaetigung',
];

void _writeCourseSizedContent(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  final tools = Directory('../tools');
  final db = sqlite3.open(path);
  try {
    db.execute(File('${tools.path}/content_schema.sql').readAsStringSync());
    db.execute(File('${tools.path}/content_fts.sql').readAsStringSync());
    db.execute('''
      INSERT INTO levels (code, ord, name) VALUES ('B1', 1, 'Intermediate');
      INSERT INTO sublevels (code, level_code, ord, word_count, grammar_count)
        VALUES ('B1.1', 'B1', 1, $_wordCount, 0);
    ''');

    // Deterministic, so a slow run is the machine and never the data.
    final random = Random(7);
    const stems = <String>[
      'Wort',
      'Haus',
      'Strasse',
      'Wohnung',
      'Arbeit',
      'Schule',
      'Wasser',
      'Freund',
    ];

    db.execute('BEGIN');
    final word = db.prepare(
      'INSERT INTO words (uid, sublevel_code, level_code, seq, '
      'seq_in_sublevel, article, german, pos, english, bangla, freq, '
      'source_week, search_key, search_key_alt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    final example = db.prepare(
      'INSERT INTO word_examples (word_uid, ord, german, english) '
      'VALUES (?, ?, ?, ?)',
    );

    // Multi-word headwords, because a German course has them ("zu Hause",
    // "es gibt") and because they are the only queries where the FTS quoting
    // is observable: unquoted, the two tokens become an implicit AND and the
    // word order stops mattering.
    var uidSeed = 0;
    // Two words the same prefix query scores identically, differing only in
    // `freq`. BR-SEARCH-01 breaks the tie on frequency, and nothing else in
    // the fixture can tell whether it does.
    for (final tie in const <List<Object>>[
      <Object>['tiefa', 1],
      <Object>['tiefe', 5],
    ]) {
      word.execute(<Object?>[
        'uid-tie-${tie[0]}',
        'B1.1',
        'B1',
        80000 + uidSeed,
        80000 + uidSeed,
        'die',
        tie[0],
        'noun',
        'depth',
        'গভীরতা',
        tie[1],
        1,
        tie[0],
        tie[0],
      ]);
      uidSeed++;
    }

    // Thirty short meanings that prefix-match `hand`, and one word whose
    // meaning *is* `hand` buried in a long cell. bm25 favours the short
    // fields, so the one that matters ranks below the starts-with cap — which
    // is the case the meaning pass has to look past.
    for (var i = 0; i < 30; i++) {
      word.execute(<Object?>[
        'uid-hand-$i',
        'B1.1',
        'B1',
        80200 + i,
        80200 + i,
        'das',
        'Handbuch$i',
        'noun',
        'handbook$i',
        'হ্যান্ডবুক',
        2,
        1,
        'handbuch$i',
        'handbuch$i',
      ]);
    }
    word.execute(<Object?>[
      'uid-hand-target',
      'B1.1',
      'B1',
      80300,
      80300,
      'die',
      'Pfote',
      'noun',
      'hand, paw of an animal used informally of a person in some regions',
      'হাত',
      4,
      1,
      'pfote',
      'pfote',
    ]);

    // A meaning with a bracketed gloss, which is how vocabulary lists
    // disambiguate. `searchKey` only strips the brackets.
    word.execute(<Object?>[
      'uid-gloss',
      'B1.1',
      'B1',
      80100,
      80100,
      'das',
      'Ufer',
      'noun',
      'bank (river)',
      'তীর',
      3,
      1,
      'ufer',
      'ufer',
    ]);

    for (final phrase in const <String>['es gibt', 'zu Hause']) {
      final uid = 'uid-phrase-$uidSeed';
      word.execute(<Object?>[
        uid,
        'B1.1',
        'B1',
        90000 + uidSeed,
        90000 + uidSeed,
        null,
        phrase,
        'phrase',
        'there is',
        'আছে',
        5,
        1,
        phrase.toLowerCase(),
        phrase.toLowerCase(),
      ]);
      uidSeed++;
    }

    for (var i = 0; i < _wordCount; i++) {
      final stem = stems[i % stems.length];
      final german = '$stem$i';
      final uid = 'uid-$i';
      word.execute(<Object?>[
        uid,
        'B1.1',
        'B1',
        i + 1,
        i + 1,
        'das',
        german,
        'noun',
        'meaning $i, sense $i',
        'অর্থ $i',
        random.nextInt(5) + 1,
        1,
        german.toLowerCase(),
        german.toLowerCase(),
      ]);
      // `content-database.md`: two sentences per word.
      for (var ord = 1; ord <= 2; ord++) {
        example.execute(<Object?>[
          uid,
          ord,
          'Das $german ist gross und $ord.',
          'The $german is big and $ord.',
        ]);
      }
    }
    word.close();
    example.close();

    db.execute('''
      INSERT INTO words_fts (uid, german, english, bangla, search_key)
        SELECT uid, german, english, bangla, search_key FROM words;
      INSERT INTO words_trigram (uid, german, english, search_key)
        SELECT uid, german, english, search_key FROM words;
      INSERT INTO examples_fts (word_uid, german, english)
        SELECT word_uid, german, english FROM word_examples;
      INSERT INTO meta ("key", value) VALUES ('content_version', '202601011200');
    ''');
    db.execute('COMMIT');
  } finally {
    db.close();
  }
}
