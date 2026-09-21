import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';

part 'app_database.g.dart';

/// The learner's database.
///
/// `docs/02-data/user-database.md`. Every table comes from
/// `user_schema.drift`, which is the authoritative DDL and the source drift
/// generates typed classes from — one file rather than a .sql asset mirrored by
/// hand-written Dart (ADR 22).
///
/// content.db is a separate, read-only file attached as schema `c` (#55); this
/// class owns only what the learner writes.
@DriftDatabase(include: <String>{'user_schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the real database, on a background isolate, in app-support storage.
  ///
  /// The isolate is the point: `accessibility-performance.md` budgets a card
  /// transition at under 16 ms a frame with "DB write off the UI isolate", and
  /// that has to be true by construction rather than by every call site
  /// remembering it.
  ///
  /// App-support, not documents, because user.db is ours and not something the
  /// learner browses — the export in M6 is how they get their data out.
  AppDatabase.open({String name = 'user'})
    : this(
        driftDatabase(
          name: name,
          native: DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
            shareAcrossIsolates: true,
            setup: configureConnection,
          ),
        ),
      );

  /// In-memory, for tests. `testing.md` asks for exactly this plus the real
  /// content.db attached.
  AppDatabase.memory()
    : this(
        DatabaseConnection(NativeDatabase.memory(setup: configureConnection)),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Every step ships its own migration and a fixture test that opens the
      // previous version (#56). Columns holding data are never dropped: add a
      // nullable column or a new table.
    },
  );

  /// The version the file itself reports, which is what a raw
  /// `PRAGMA user_version` on a copied database shows. drift writes it; this
  /// reads it back so a test or a bug report can check the two agree.
  Future<int> fileSchemaVersion() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }
}

/// Runs on every connection, on whichever isolate opened it.
///
/// Top-level because `drift_flutter` sends this function to the background
/// isolate; a closure or a method would not survive the trip.
///
/// - **WAL** is what `user-database.md` specifies. It is stored in the file, so
///   setting it repeatedly is a no-op, and it is what lets a read run while a
///   rating is being written.
/// - **Foreign keys** are off by default in SQLite and are per connection, not
///   stored in the file. The DDL is full of them, so without this line every
///   `REFERENCES` clause is decoration.
void configureConnection(CommonDatabase db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
}
