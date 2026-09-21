@TestOn('vm')
library;

import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

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
        // and constraint against the fixture for the target version.
        //
        // With one fixture this is a no-op upgrade: onUpgrade never fires, so
        // today it proves only that the fixture matches, the same as the test
        // below. The first real exercise of stepByStep() is the v1 -> v2 step.
        await verifier.migrateAndValidate(db, current, options: _strict);
      });
    }
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
}
