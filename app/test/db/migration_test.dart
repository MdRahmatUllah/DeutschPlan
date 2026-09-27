@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'generated/schema.dart';

/// `user-database.md`: "Every change ships a migration step in
/// `lib/data/db/migrations.dart` and a test in `test/db/migration_test.dart`
/// that opens a fixture of each previous version."
///
/// The fixtures are the JSON files in `drift_schemas/`, captured by
/// `make schema-dump`. They are the only record of what a learner's file looks
/// like at an older version — nothing else in the repo remembers it, because
/// `user_schema.drift` always describes the newest.
///
/// Adding the next one is one step: bump `schemaVersion`, write the step in
/// `user_schema.drift`, run `make schema-dump`, run `make gen`. The loop below
/// picks it up with no edit here.
/// `validateDropped` catches the opposite mistake to the usual one: a table or
/// index that exists in the database and not in the fixture, which is what a
/// migration that forgot to drop something leaves behind.
const _strict = ValidationOptions(validateDropped: true);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the fixtures cover every version up to the current one', () {
    // A gap means some learner's version has no fixture, so nothing can test
    // the migration out of it. This is the check that makes the loop below
    // meaningful rather than vacuously short.
    expect(
      GeneratedHelper.versions,
      List<int>.generate(AppDatabase.latestSchemaVersion, (i) => i + 1),
      reason:
          'run `make schema-dump` after bumping schemaVersion — the fixture '
          'is the only record of the older shape',
    );
  });

  group('migrating forward from', () {
    const current = AppDatabase.latestSchemaVersion;

    for (final from in GeneratedHelper.versions) {
      test('v$from arrives at the current schema', () async {
        final connection = await verifier.startAt(from);
        final db = AppDatabase(connection);
        addTearDown(db.close);

        // Runs the real onUpgrade, then compares every table, column, index
        // and constraint against the fixture for the target version. From
        // the current version itself onUpgrade never fires: that one proves
        // only that its fixture matches, as the test below does.
        await verifier.migrateAndValidate(db, current, options: _strict);
      });
    }
  });

  test('v1 -> v2: an update already recorded keeps its row, with no '
      'recorded_at, and progress stays (#695)', () async {
    final schema = await verifier.schemaAt(1);
    schema.rawDatabase.execute(
      'INSERT INTO content_updates (version, added, removed, seen) '
      "VALUES ('202601011200', 3, 1, 1)",
    );
    schema.rawDatabase.execute(
      "INSERT INTO word_state (word_uid, status, reps) VALUES ('w1', 'learning', 4)",
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2, options: _strict);

    final update = await db.select(db.contentUpdates).getSingle();
    expect(update.version, '202601011200');
    expect((update.added, update.removed, update.seen), (3, 1, 1));
    expect(update.recordedAt, null);
    // At v2 word_state has no card_mode_manual yet, so not its row class.
    final word = await db
        .customSelect('SELECT word_uid, status, reps FROM word_state')
        .getSingle();
    expect(word.data, {'word_uid': 'w1', 'status': 'learning', 'reps': 4});
  });

  test('v2 -> v3: a word already there keeps the card the rule gave it '
      '(BR-FSRS-06, #316)', () async {
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute(
      "INSERT INTO word_state (word_uid, card_mode) VALUES ('w1', 'cloze')",
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3, options: _strict);

    final row = await db.select(db.wordState).getSingle();
    expect(row.cardMode, 'cloze');
    expect(row.cardModeManual, 0);
  });

  test('the live DDL still matches the fixture for its own version', () async {
    // The one that bites day to day: editing user_schema.drift without
    // bumping the version and re-dumping leaves the fixture describing a
    // schema that no longer exists, and every migration test above then
    // validates against a lie.
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, db.schemaVersion, options: _strict);
  });

  group('#656 a step of the kind main has none of yet', () {
    const previous = AppDatabase.latestSchemaVersion - 1;
    late Directory directory;
    late File file;

    // A learner's file one version back, with the connection the app opens,
    // foreign keys on: an exam attempt and its two answers.
    setUp(() async {
      directory = Directory.systemTemp.createTempSync('sogda_migrate');
      file = File('${directory.path}/user.db');
      final db = AppDatabase(NativeDatabase(file, setup: configureConnection));
      await db.customStatement(
        'INSERT INTO exam_attempts (id, sublevel_code, seed, started_at) '
        "VALUES (1, 'A1.1', 2, '2026-09-01T09:00:00Z')",
      );
      await db.customStatement(
        'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
        "VALUES (1, 0, 'lesen', 'p0'), (1, 1, 'lesen', 'p1')",
      );
      await db.customStatement('PRAGMA user_version = $previous');
      await db.close();
    });

    tearDown(() {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows releases it a moment later.
      }
    });

    _Planted open(Future<void> Function(AppDatabase db, Migrator m) step) =>
        _Planted(NativeDatabase(file, setup: configureConnection), step);

    test('#656 recreating a parent table keeps its children', () async {
      // alterTable drops exam_attempts and renames a copy into its place.
      // With the keys on, the drop's ON DELETE CASCADE takes every answer.
      final db = open((db, m) => m.alterTable(TableMigration(db.examAttempts)));
      addTearDown(db.close);

      final answers = await db
          .customSelect('SELECT COUNT(*) AS n FROM exam_answers')
          .getSingle();
      final keys = await db.customSelect('PRAGMA foreign_keys').getSingle();

      expect(answers.read<int>('n'), 2);
      expect(keys.read<int>('foreign_keys'), 1, reason: 'and back on after');
      expect(await db.fileSchemaVersion(), AppDatabase.latestSchemaVersion);
    });

    test('#656 a step that leaves a dangling reference changes nothing, and '
        'the next launch checks again', () async {
      final db = open(
        (db, m) => db.customStatement(
          'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
          "VALUES (99, 0, 'lesen', 'orphan')",
        ),
      );
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('dangling'),
          ),
        ),
      );
      await db.close();

      final raw = sqlite3.open(file.path);
      addTearDown(raw.close);
      expect(raw.select('PRAGMA user_version').single.values.single, previous);
      expect(
        raw
            .select('SELECT COUNT(*) FROM exam_answers WHERE attempt_id = 99')
            .single
            .values
            .single,
        0,
      );
    });
  });
}

/// The app's database with one planted migration step, run through the real
/// [AppDatabase.upgrade] (#656).
class _Planted extends AppDatabase {
  _Planted(super.e, this._step);

  final Future<void> Function(AppDatabase db, Migrator m) _step;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) => upgrade(from, to, () => _step(this, m)),
  );
}
