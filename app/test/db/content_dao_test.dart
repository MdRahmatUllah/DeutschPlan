@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'content_fixture.dart';

/// `docs/02-data/content-database.md`: content.db is attached to the user
/// database as schema `c` and opened read-only.
///
/// Every query here runs against a real file built from the pipeline's own
/// DDL, so a mismatch between `content_schema.drift` and what `make content`
/// produces fails here rather than on a learner's phone.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late ContentDao dao;
  late File content;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_content');
    content = ContentFixture.write('${directory.path}/content.db').file;

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    dao = ContentDao(db);
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
  });

  tearDown(() async {
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases the file a moment later; the OS clears its temp.
    }
  });

  group('the attach itself', () {
    test('the course is readable through the user database', () async {
      expect(
        await dao.contentMeta('content_version').getSingle(),
        ContentFixture.version,
      );
    });

    test('nothing in the DAO can write to it', () {
      // SQLite only honours a `?mode=ro` attach when the main connection was
      // opened with SQLITE_OPEN_URI, and drift_flutter's is not — so the
      // guarantee is structural instead (ADR 26). content.drift holds only
      // reads, the manager API that would generate writers is off, and
      // architecture_test.dart fails the build if anything under lib/ writes
      // to a content table.
      final queries = File('lib/data/db/content.drift').readAsStringSync();
      final writes = RegExp(
        'INSERT|UPDATE|DELETE|REPLACE',
        caseSensitive: false,
      );
      expect(
        writes.hasMatch(queries),
        isFalse,
        reason: 'content.drift must contain only reads',
      );
    });

    test('no table name exists in both schemas', () async {
      // The queries in content.drift name tables unqualified and rely on
      // SQLite falling through from `main` to the attached database. A table
      // called `words` in user.db would capture every one of them silently.
      // AppDatabase.ownTables, not allTables: the latter carries the content
      // tables too, because content.drift is included for type-checking.
      const userTables = AppDatabase.ownTables;
      final contentTables = {
        for (final row
            in await db
                .customSelect(
                  "SELECT name FROM c.sqlite_master WHERE type = 'table' "
                  "AND name NOT LIKE 'sqlite_%'",
                )
                .get())
          row.read<String>('name'),
      };

      expect(
        userTables.intersection(contentTables),
        isEmpty,
        reason:
            'a shared name would make every unqualified query in '
            'content.drift read the wrong table',
      );
    });

    test('user.db has none of the content tables of its own', () async {
      // The other half: drift warns that ContentDao references tables not on
      // the main database, and that warning has to stay unaddressed. Adding
      // them would make createAll() build empty copies in user.db, which
      // would then shadow the attached ones.
      final rows = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM main.sqlite_master "
            "WHERE name IN ('words', 'words_fts', 'sublevels', 'meta')",
          )
          .getSingle();
      expect(rows.read<int>('n'), 0);
    });
  });

  group('the four documented query shapes', () {
    test('wordsForStep is ordered by seq_in_sublevel', () async {
      final words = await dao.wordsForStep('A1.1').get();
      expect(
        <String>[for (final w in words) w.german],
        <String>['Haus', 'Tür'],
      );
      expect(<int>[for (final w in words) w.seqInSublevel], <int>[1, 2]);
    });

    test('exactMatches takes both keys and the raw Bangla', () async {
      // search.md tier 1. The Bangla is matched as typed, because a Bangla
      // query is not normalised.
      expect(
        (await dao.exactMatches('tuer', 'x', 'y', null).get()).single.german,
        'Tür',
      );
      expect(
        (await dao.exactMatches('x', 'tur', 'y', null).get()).single.german,
        'Tür',
      );
      expect(
        (await dao.exactMatches('x', 'y', 'বাড়ি', null).get()).single.german,
        'Haus',
      );
    });

    test('prefixMatches ranks, and joins back to the word', () async {
      final hits = await dao.prefixMatches('"Hau"*', null, 5).get();
      expect(hits.single.w.german, 'Haus');
      expect(hits.single.rank, isNotNull);
    });

    test('sentenceMatches names the headword above the sentence', () async {
      final hits = await dao.sentenceMatches('"offen"', null, 5).get();
      expect(hits.single.head, 'Tür');
      expect(hits.single.german, 'Die Tür ist offen.');
    });
  });

  group('the MATCH strings search.md specifies', () {
    test('a column filter narrows the search', () async {
      // `english : "door"` must not match a German column containing "door".
      final hits = await dao.prefixMatches('english : "door"', null, 5).get();
      expect(hits.single.w.german, 'Tür');
    });

    test('the tokenizer folds diacritics, so Tur finds Tür', () async {
      // remove_diacritics 2, on top of search_key_alt.
      expect(
        (await dao.prefixMatches('"Tur"', null, 5).get()).single.w.german,
        'Tür',
      );
    });

    test('trigram candidates survive a misspelling', () async {
      // Tier 3 returns candidates; search.md ranks them by edit distance in
      // Dart, because SQLite has no OSA distance.
      final hits = await dao.trigramCandidates('"stras"', null, 400).get();
      expect(<String>[for (final w in hits) w.german], contains('Straße'));
    });

    test('a uid is not searchable, so a hex query returns nothing', () async {
      expect(
        await dao.prefixMatches('"${ContentFixture.haus}"', null, 5).get(),
        isEmpty,
      );
    });
  });

  group('the rest of the course', () {
    test('examples keep their order and their missing translation', () async {
      final examples = await dao.examplesForWord(ContentFixture.haus).get();
      expect(<int>[for (final e in examples) e.ord], <int>[1, 2]);
      expect(examples.last.english, isNull);
    });

    test('a step reports its stored counts', () async {
      final counts = await dao.countForStep('A1.1').getSingle();
      expect(counts.wordCount, 2);
      expect(counts.grammarCount, 1);
    });

    test('sublevels come back with their level name and exam target', () async {
      final steps = await dao.allSublevels().get();
      expect(steps.first.code, 'A1.1');
      expect(steps.first.levelName, 'Beginner');
      expect(steps.first.examTarget, contains('Goethe'));
    });

    test('BR-COURSE-01 the steps come in course order', () async {
      // Level first, then step. `PlanStore.stepAfter` was written against an
      // `ord` that restarts in each level; ordering on `s.ord` alone would
      // then interleave them — A1.1, A2.1, A1.2, A2.2.
      final writer = sqlite3.open(content.path);
      addTearDown(writer.close);
      writer.execute('''
        INSERT INTO sublevels (code, level_code, ord, word_count, grammar_count)
        VALUES ('A2.2', 'A2', 2, 5, 0), ('A2.1', 'A2', 1, 4, 0);
      ''');

      final steps = await dao.courseSteps();

      expect(steps.map((step) => step.code), <String>[
        'A1.1',
        'A1.2',
        'A2.1',
        'A2.2',
      ]);
      expect(steps.first.levelCode, 'A1');
      expect(steps.first.wordCount, 2, reason: "the fixture's own count");
    });

    test("S3's pool is a step's words, with their examples", () async {
      final pool = await dao.placementPool('A1.1');

      expect(pool.map((w) => w.german), containsAll(<String>['Haus', 'Tür']));
      final haus = pool.firstWhere((w) => w.uid == ContentFixture.haus);
      expect((haus.article, haus.pos.isNotEmpty), ('das', true));
      expect(
        pool.every((w) => w.uid != ContentFixture.strasse),
        isTrue,
        reason: 'another step',
      );
      expect(
        pool.expand((w) => w.examples),
        isNotEmpty,
        reason: 'the fixture gives its words examples',
      );
      // One word, however many examples — the join must not repeat it.
      expect(pool.map((w) => w.uid).toSet(), hasLength(pool.length));
    });

    test('grammar carries the tags the generator reads', () async {
      final topics = await dao.grammarForStep('A1.1').get();
      expect(topics.single.tags.split(','), contains('word-order'));
    });

    test('an interference tip reaches its word', () async {
      final tips = await dao.tipsForWord(ContentFixture.strasse).get();
      expect(tips.single.tipBn, isNotNull);
    });

    test('skill prompts belong to a level', () async {
      expect(await dao.skillPromptsForLevel('A1').get(), hasLength(1));
    });
  });
}
