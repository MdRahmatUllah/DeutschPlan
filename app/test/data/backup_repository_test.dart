@TestOn('vm')
library;

import 'dart:convert';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `BackupRepository` — M6's export and import.
///
/// Written against raw SQL rather than the repositories, because an export has
/// to carry every table whether or not a repository exists for it yet, and a
/// test that only exercises the tables that do would pass while losing the
/// rest of the learner's data.
void main() {
  late AppDatabase db;
  late BackupRepository backup;

  setUp(() {
    db = AppDatabase.memory();
    backup = BackupRepository(db);
  });

  tearDown(() => db.close());

  Future<void> sql(
    String statement, [
    List<Object?> args = const <Object?>[],
  ]) => db.customStatement(statement, args);

  /// A phone with something in every table an export carries.
  Future<void> fillEverything() async {
    await sql("INSERT INTO settings VALUES ('daily_new', '9')");
    await sql(
      'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
      "study_days_mask) VALUES ('A1.1', '2026-01-05', 7, 127)",
    );
    await sql(
      'INSERT INTO word_state (word_uid, status, stability, last_review) '
      "VALUES ('uid-haus', 'learning', 3.5, '2026-03-01T09:00:00Z')",
    );
    await sql(
      'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
      "VALUES ('uid-haus', '2026-03-01T09:00:00Z', 3, 'daily')",
    );
    await sql(
      'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
      "VALUES ('2026-03-01', 'uid-haus', 'new', 'A1.1')",
    );
    await sql(
      'INSERT INTO grammar_state (grammar_uid, status, last_review) '
      "VALUES ('g1', 'learning', '2026-03-01T09:00:00Z')",
    );
    await sql(
      'INSERT INTO grammar_practice_log (grammar_uid, practised_at, items, '
      "correct) VALUES ('g1', '2026-03-01T09:00:00Z', 4, 3)",
    );
    await sql(
      'INSERT INTO sentence_log (word_uid, ord, shown_on) '
      "VALUES ('uid-haus', 1, '2026-03-01')",
    );
    await sql(
      'INSERT INTO quiz_attempts (started_at, direction, source, seed, length) '
      "VALUES ('2026-03-01T10:00:00Z', 'deEn', 'stepLearned', 7, 10)",
    );
    await sql(
      'INSERT INTO quiz_answers (attempt_id, ord, word_uid, prompt, expected) '
      "VALUES (1, 1, 'uid-haus', 'Haus', 'house')",
    );
    await sql(
      'INSERT INTO exam_attempts (sublevel_code, seed, started_at) '
      "VALUES ('A1.1', 1, '2026-03-02T10:00:00Z')",
    );
    await sql(
      'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
      "VALUES (1, 1, 'vocabulary', 'das Haus')",
    );
    await sql(
      'INSERT INTO custom_words (created_at, german, meaning) '
      "VALUES ('2026-03-01T11:00:00Z', 'Pfandflasche', 'deposit bottle')",
    );
    await sql(
      "INSERT INTO daily_stats (day, new_done) VALUES ('2026-03-01', 7)",
    );
    await sql(
      "INSERT INTO content_updates (version, added) VALUES ('202601011200', 3)",
    );
    // The two that must never be exported.
    await sql(
      'INSERT INTO translation_cache (src_lang, tgt_lang, src_text, model, '
      "result, created_at) VALUES ('de', 'en', 'Haus', 'hymt', 'house', 'x')",
    );
    await sql(
      "INSERT INTO undo_stack (created_at, payload_json) VALUES ('x', '{}')",
    );
  }

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM "$table"')
        .getSingle();
    return row.read<int>('n');
  }

  Future<List<Map<String, Object?>>> rowsOf(String table) async {
    final rows = await db
        .customSelect('SELECT * FROM "$table" ORDER BY rowid')
        .get();
    return <Map<String, Object?>>[for (final row in rows) row.data];
  }

  group('FR-M6-01 — the export shape', () {
    test('is exactly the four documented keys', () async {
      final file = await backup.export();
      expect(file.keys, <String>[
        'schema_version',
        'content_version',
        'exported_at',
        'tables',
      ]);
    });

    test('carries the schema version and the content version', () async {
      final file = await backup.export(contentVersion: '202601011200');
      expect(file['schema_version'], AppDatabase.latestSchemaVersion);
      expect(file['content_version'], '202601011200');
      expect(
        DateTime.parse(file['exported_at']! as String).isUtc,
        isTrue,
        reason: 'exported_at is a UTC instant',
      );
    });

    test('carries every user table', () async {
      final tables = (await backup.export())['tables']! as Map<String, Object?>;
      for (final table in AppDatabase.ownTables) {
        if (BackupRepository.excluded.contains(table)) continue;
        expect(
          tables.keys,
          contains(table),
          reason: '$table is in the database and not in the export',
        );
      }
    });

    test('excludes the cache and the undo stack', () async {
      await fillEverything();
      final tables = (await backup.export())['tables']! as Map<String, Object?>;
      expect(tables.keys, isNot(contains('translation_cache')));
      expect(tables.keys, isNot(contains('undo_stack')));
    });

    test('carries no recordings', () async {
      // FR-M6-01: they are the biggest thing on the phone and a backup nobody
      // can email is not a backup. Nothing in the file may be a path into the
      // recordings directory.
      await fillEverything();
      expect(await backup.exportJson(), isNot(contains('recordings')));
    });

    test('is JSON that survives a round trip through a file', () async {
      await fillEverything();
      final json = await backup.exportJson();
      expect(jsonDecode(json), isA<Map<String, Object?>>());
    });
  });

  group('FR-M6-02 — the version', () {
    test('a newer file is refused before anything is written', () async {
      await fillEverything();
      final file = await backup.export();
      final newer = jsonEncode(<String, Object?>{
        ...file,
        'schema_version': AppDatabase.latestSchemaVersion + 1,
      });

      expect(
        () => backup.preview(newer),
        throwsA(
          isA<ImportException>().having(
            (e) => e.reason,
            'reason',
            ImportRefusal.newerSchema,
          ),
        ),
      );
      await expectLater(
        backup.import(newer, mode: ImportMode.replace),
        throwsA(isA<ImportException>()),
      );
      expect(await count('word_state'), 1, reason: 'the refusal wrote anyway');
    });

    test('an older file is read, and the new column takes its default', () async {
      // v1 had no `content_updates.recorded_at`. Every migration so far adds a
      // column with a default, so a row that predates one simply has no value
      // for it — which is what makes reading an older file possible at all.
      final older = jsonEncode(<String, Object?>{
        'schema_version': 1,
        'content_version': null,
        'exported_at': '2026-01-01T00:00:00Z',
        'tables': <String, Object?>{
          'content_updates': <Object?>[
            <String, Object?>{
              'version': '202601011200',
              'added': 5,
              'removed': 0,
              'changed_json': null,
              'seen': 0,
            },
          ],
        },
      });

      await backup.import(older, mode: ImportMode.replace);

      final rows = await rowsOf('content_updates');
      expect(rows.single['added'], 5);
      expect(rows.single['recorded_at'], isNull);
    });

    test('something that is not JSON is refused', () {
      expect(
        () => backup.preview('not json at all'),
        throwsA(
          isA<ImportException>().having(
            (e) => e.reason,
            'reason',
            ImportRefusal.notABackup,
          ),
        ),
      );
    });

    test('JSON of the wrong shape is refused', () {
      expect(
        () => backup.preview('{"hello":"world"}'),
        throwsA(
          isA<ImportException>().having(
            (e) => e.reason,
            'reason',
            ImportRefusal.notABackup,
          ),
        ),
      );
    });
  });

  group('the preview', () {
    test('says what the import card shows', () async {
      await fillEverything();
      await sql(
        'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
        "VALUES ('uid-tuer', '2026-03-05T09:00:00Z', 2, 'daily')",
      );
      final json = await backup.exportJson(contentVersion: '202601011200');

      final preview = backup.preview(json);
      expect(preview.wordStates, 1);
      expect(preview.lastActive, '2026-03-05T09:00:00Z');
      expect(preview.activeStep, 'A1.1');
      expect(preview.contentVersion, '202601011200');
      expect(preview.rowCounts['review_log'], 2);
    });

    test('writes nothing', () async {
      await fillEverything();
      final json = await backup.exportJson();
      await sql("DELETE FROM word_state WHERE word_uid = 'uid-haus'");

      backup.preview(json);
      expect(await count('word_state'), 0);
    });

    test('a finished step is not the active one', () async {
      await sql(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask, completed_on) VALUES ('A1.1', '2026-01-05', 7, 127, "
        "'2026-02-01')",
      );
      await sql(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A1.2', '2026-02-01', 7, 127)",
      );

      expect(backup.preview(await backup.exportJson()).activeStep, 'A1.2');
    });
  });

  group('the round trip', () {
    test('export then replace gives back exactly what went in', () async {
      await fillEverything();
      final before = <String, List<Map<String, Object?>>>{
        for (final table in BackupRepository.tables) table: await rowsOf(table),
      };

      final json = await backup.exportJson();
      await backup.import(json, mode: ImportMode.replace);

      for (final table in BackupRepository.tables) {
        expect(await rowsOf(table), before[table], reason: table);
      }
    });

    test('into an empty database too', () async {
      await fillEverything();
      final json = await backup.exportJson();
      final before = <String, List<Map<String, Object?>>>{
        for (final table in BackupRepository.tables) table: await rowsOf(table),
      };

      for (final table in BackupRepository.tables.reversed) {
        await sql('DELETE FROM "$table"');
      }
      await backup.import(json, mode: ImportMode.replace);

      for (final table in BackupRepository.tables) {
        expect(await rowsOf(table), before[table], reason: table);
      }
    });

    test('a quiz answer still points at its own attempt', () async {
      // The ids are reassigned on the way in, so the join has to be rebuilt
      // rather than carried.
      await fillEverything();
      final json = await backup.exportJson();
      for (final table in BackupRepository.tables.reversed) {
        await sql('DELETE FROM "$table"');
      }
      await backup.import(json, mode: ImportMode.replace);

      final joined = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM quiz_answers a '
            'JOIN quiz_attempts t ON t.id = a.attempt_id',
          )
          .getSingle();
      expect(joined.read<int>('n'), 1);
    });
  });

  group('FR-M6-04 — replace', () {
    test('wipes what was here', () async {
      await fillEverything();
      final json = await backup.exportJson();

      await sql(
        'INSERT INTO word_state (word_uid, status) '
        "VALUES ('uid-only-here', 'learning')",
      );
      await backup.import(json, mode: ImportMode.replace);

      final rows = await rowsOf('word_state');
      expect(rows.map((row) => row['word_uid']), <String>['uid-haus']);
    });

    test('a failed import leaves the previous data intact', () async {
      // FR-M6-04's other half. A `rating` of 9 fails the CHECK, part way
      // through — the wipe has already run inside the transaction, so
      // everything has to come back.
      await fillEverything();
      final file = await backup.export();
      final tables = file['tables']! as Map<String, Object?>;
      (tables['review_log']! as List<Object?>).add(<String, Object?>{
        'word_uid': 'uid-haus',
        'reviewed_at': '2026-03-09T09:00:00Z',
        'rating': 9,
        'source': 'daily',
      });

      await expectLater(
        backup.import(jsonEncode(file), mode: ImportMode.replace),
        throwsA(anything),
      );

      expect(await count('word_state'), 1);
      expect(await count('review_log'), 1);
      expect(await count('quiz_attempts'), 1);
    });

    test('it does not touch the cache or the undo stack', () async {
      // They are not in the file, so a replace that wiped them would be
      // deleting data the import cannot put back.
      await fillEverything();
      final json = await backup.exportJson();
      await backup.import(json, mode: ImportMode.replace);

      expect(await count('translation_cache'), 1);
      expect(await count('undo_stack'), 1);
    });
  });

  group('FR-M6-03 — merge', () {
    /// A file describing one word reviewed at [reviewedAt].
    String fileWith({
      required String reviewedAt,
      required double stability,
      String uid = 'uid-haus',
    }) => jsonEncode(<String, Object?>{
      'schema_version': AppDatabase.latestSchemaVersion,
      'content_version': null,
      'exported_at': '2026-03-09T00:00:00Z',
      'tables': <String, Object?>{
        'word_state': <Object?>[
          <String, Object?>{
            'word_uid': uid,
            'status': 'learning',
            'stability': stability,
            'last_review': reviewedAt,
          },
        ],
        'review_log': <Object?>[
          <String, Object?>{
            'word_uid': uid,
            'reviewed_at': reviewedAt,
            'rating': 3,
            'source': 'daily',
          },
        ],
      },
    });

    test('a later row wins', () async {
      await fillEverything();
      await backup.import(
        fileWith(reviewedAt: '2026-03-08T09:00:00Z', stability: 99),
        mode: ImportMode.merge,
      );

      final row = (await rowsOf('word_state')).single;
      expect(row['stability'], 99);
      expect(row['last_review'], '2026-03-08T09:00:00Z');
    });

    test('an earlier row loses', () async {
      await fillEverything();
      await backup.import(
        fileWith(reviewedAt: '2026-02-01T09:00:00Z', stability: 99),
        mode: ImportMode.merge,
      );

      final row = (await rowsOf('word_state')).single;
      expect(row['stability'], 3.5, reason: 'the older row overwrote a newer');
      expect(row['last_review'], '2026-03-01T09:00:00Z');
    });

    test('a row with no review loses to one that has one', () async {
      await fillEverything();
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'word_state': <Object?>[
            <String, Object?>{
              'word_uid': 'uid-haus',
              'status': 'todo',
              'stability': 0,
              'last_review': null,
            },
          ],
        },
      });

      await backup.import(file, mode: ImportMode.merge);
      expect((await rowsOf('word_state')).single['stability'], 3.5);
    });

    test('a word only the file has is added', () async {
      await fillEverything();
      await backup.import(
        fileWith(
          reviewedAt: '2026-03-08T09:00:00Z',
          stability: 5,
          uid: 'uid-neu',
        ),
        mode: ImportMode.merge,
      );

      expect(await count('word_state'), 2);
    });

    test('nothing already here is deleted', () async {
      await fillEverything();
      await backup.import(
        fileWith(
          reviewedAt: '2026-03-08T09:00:00Z',
          stability: 5,
          uid: 'uid-neu',
        ),
        mode: ImportMode.merge,
      );

      expect(await count('quiz_attempts'), 1);
      expect(await count('custom_words'), 1);
    });

    test('review_log is unioned by (word_uid, reviewed_at)', () async {
      await fillEverything();

      // One review the phone already has, one it does not.
      await backup.import(
        fileWith(reviewedAt: '2026-03-01T09:00:00Z', stability: 4),
        mode: ImportMode.merge,
      );
      expect(await count('review_log'), 1, reason: 'the same review twice');

      await backup.import(
        fileWith(reviewedAt: '2026-03-08T09:00:00Z', stability: 4),
        mode: ImportMode.merge,
      );
      expect(await count('review_log'), 2);
    });

    test(
      'importing the same file twice changes nothing the second time',
      () async {
        await fillEverything();
        final json = await backup.exportJson();

        await backup.import(json, mode: ImportMode.merge);
        final once = <String, int>{
          for (final table in BackupRepository.tables)
            table: await count(table),
        };

        await backup.import(json, mode: ImportMode.merge);
        for (final table in BackupRepository.tables) {
          expect(await count(table), once[table], reason: table);
        }
      },
    );

    test('an attempt from the other phone comes with its answers', () async {
      await fillEverything();
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'quiz_attempts': <Object?>[
            <String, Object?>{
              // Deliberately id 1, which this phone has already used for a
              // different attempt.
              'id': 1,
              'started_at': '2026-03-07T10:00:00Z',
              'direction': 'enDe',
              'source': 'allLearned',
              'seed': 3,
              'length': 5,
            },
          ],
          'quiz_answers': <Object?>[
            <String, Object?>{
              'attempt_id': 1,
              'ord': 1,
              'word_uid': 'uid-tuer',
              'prompt': 'door',
              'expected': 'die Tür',
            },
          ],
        },
      });

      await backup.import(file, mode: ImportMode.merge);

      expect(await count('quiz_attempts'), 2);
      final joined = await db
          .customSelect(
            'SELECT a.word_uid AS word FROM quiz_answers a '
            'JOIN quiz_attempts t ON t.id = a.attempt_id '
            "WHERE t.started_at = '2026-03-07T10:00:00Z'",
          )
          .getSingle();
      expect(joined.read<String>('word'), 'uid-tuer');
    });

    test('a backup from a step behind does not break the merge', () async {
      // BR-COURSE-04 allows one open enrollment, and the index enforces it.
      // Restoring an old phone's backup onto the one in use is the case merge
      // exists for, and two open rows would fail the whole import.
      await sql(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A2.1', '2026-02-01', 7, 127)",
      );

      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'enrollments': <Object?>[
            <String, Object?>{
              'sublevel_code': 'A1.2',
              'started_on': '2026-01-01',
              'daily_new': 7,
              'study_days_mask': 127,
              'completed_on': null,
            },
          ],
        },
      });

      await backup.import(file, mode: ImportMode.merge);

      final rows = await rowsOf('enrollments');
      expect(rows, hasLength(2));
      final open = rows.where((row) => row['completed_on'] == null);
      expect(
        open.single['sublevel_code'],
        'A2.1',
        reason: 'this phone says where the learner is',
      );
    });

    test('a finished step from the other phone comes in as finished', () async {
      await sql(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask) VALUES ('A2.1', '2026-02-01', 7, 127)",
      );
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'enrollments': <Object?>[
            <String, Object?>{
              'sublevel_code': 'A1.1',
              'started_on': '2026-01-01',
              'daily_new': 7,
              'study_days_mask': 127,
              'completed_on': '2026-01-31',
            },
          ],
        },
      });

      await backup.import(file, mode: ImportMode.merge);

      final rows = await rowsOf('enrollments');
      final imported = rows.firstWhere((row) => row['sublevel_code'] == 'A1.1');
      expect(imported['completed_on'], '2026-01-31');
    });

    test('an open step on a phone with none stays open', () async {
      // Nothing to collide with, so the learner's step comes back as it was.
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'enrollments': <Object?>[
            <String, Object?>{
              'sublevel_code': 'A1.2',
              'started_on': '2026-01-01',
              'daily_new': 7,
              'study_days_mask': 127,
              'completed_on': null,
            },
          ],
        },
      });

      await backup.import(file, mode: ImportMode.merge);
      expect((await rowsOf('enrollments')).single['completed_on'], isNull);
    });

    test('a failed merge leaves the previous data intact', () async {
      await fillEverything();
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'word_state': <Object?>[
            <String, Object?>{
              'word_uid': 'uid-neu',
              'status': 'learning',
              'stability': 5,
              'last_review': '2026-03-08T09:00:00Z',
            },
          ],
          'review_log': <Object?>[
            <String, Object?>{
              'word_uid': 'uid-neu',
              'reviewed_at': '2026-03-08T09:00:00Z',
              'rating': 42,
              'source': 'daily',
            },
          ],
        },
      });

      await expectLater(
        backup.import(file, mode: ImportMode.merge),
        throwsA(anything),
      );

      expect(await count('word_state'), 1, reason: 'a half-merge landed');
      expect(await count('review_log'), 1);
    });
  });

  group('a file that is the right shape but wrong inside', () {
    test('previews rather than crashing', () {
      // `_parse` checks the envelope, not every row. A null where a timestamp
      // belongs must read as a file we cannot say much about, not a crash.
      final file = jsonEncode(<String, Object?>{
        'schema_version': AppDatabase.latestSchemaVersion,
        'content_version': null,
        'exported_at': '2026-03-09T00:00:00Z',
        'tables': <String, Object?>{
          'review_log': <Object?>[
            <String, Object?>{'word_uid': 'uid-haus', 'reviewed_at': null},
            <String, Object?>{
              'word_uid': 'uid-tuer',
              'reviewed_at': '2026-03-01T09:00:00Z',
            },
          ],
          'enrollments': <Object?>[
            <String, Object?>{'sublevel_code': null, 'completed_on': null},
          ],
        },
      });

      final preview = backup.preview(file);
      expect(preview.lastActive, '2026-03-01T09:00:00Z');
      expect(preview.activeStep, isNull);
      expect(preview.rowCounts['review_log'], 2);
    });
  });

  test('the row keys cover every exported table', () {
    // A table with no key would silently fall out of a merge.
    for (final table in BackupRepository.tables) {
      expect(
        BackupRepository.rowKeys[table],
        isNotNull,
        reason: '$table has no merge key',
      );
    }
  });

  test('the excluded tables are the ones the doc names', () {
    expect(BackupRepository.excluded, <String>{
      'translation_cache',
      'undo_stack',
    });
    for (final table in BackupRepository.tables) {
      expect(BackupRepository.excluded, isNot(contains(table)));
    }
  });
}
