import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/schema_versions.dart';
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
@DriftDatabase(
  include: <String>{'user_schema.drift', 'content.drift'},
  daos: <Type>[ContentDao],
)
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

  /// Readable without an instance, which the migration tests need.
  static const int latestSchemaVersion = 2;

  /// The tables this database actually owns.
  ///
  /// `content.drift` is included so drift can type-check `ContentDao`'s
  /// queries, which means the content tables appear in `allSchemaEntities`
  /// too. They must never be **created** here: an empty `words` table in
  /// user.db would shadow the attached `c.words` for every unqualified query,
  /// and the app would show a course with nothing in it.
  ///
  /// The list is `user-database.md`'s, and `app_database_test.dart` checks it
  /// against that doc — so the doc is the one source, read twice.
  static const Set<String> ownTables = <String>{
    'settings',
    'enrollments',
    'word_state',
    'review_log',
    'plan_items',
    'grammar_state',
    'grammar_practice_log',
    'sentence_log',
    'quiz_attempts',
    'quiz_answers',
    'exam_attempts',
    'exam_answers',
    'custom_words',
    'daily_stats',
    'content_updates',
    'translation_cache',
    'undo_stack',
  };

  @override
  int get schemaVersion => latestSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // In a transaction because drift does not put one here and only writes
      // `user_version` once this returns: a step that throws part-way would
      // otherwise leave the file partly migrated at the old version, and the
      // next open would replay the steps against a schema that had already
      // moved. On the learner's device, permanently.
      await transaction(
        () => stepByStep(
          // v2: `content_updates.recorded_at`. Nullable, so the rows already
          // there keep their data — the rule is to add a nullable column
          // rather than drop or back-fill one. The "updated" chip reads a
          // null as "before this device started recording", which is exactly
          // what it means.
          from1To2: (m, schema) => m.addColumn(
            schema.contentUpdates,
            schema.contentUpdates.recordedAt,
          ),
        )(m, from, to),
      );

      // `Migrator.alterTable` turns foreign keys off while it recreates a
      // table, so a migration can leave dangling references behind and
      // nothing would notice until a query returned a row that points at
      // nothing.
      final dangling = await customSelect('PRAGMA foreign_key_check').get();
      if (dangling.isNotEmpty) {
        throw StateError(
          'migration $from -> $to left ${dangling.length} dangling '
          'reference(s): ${dangling.map((r) => r.data).toList()}',
        );
      }
    },
  );

  /// Only what user.db owns.
  ///
  /// `content.drift` is included so drift can type-check `ContentDao`'s
  /// queries, and that puts the content tables into the generated
  /// `allSchemaEntities`. Everything that reads this list would then act on
  /// them: `createAll` would build an empty `words` inside user.db — shadowing
  /// the attached course, so the app would show a course with nothing in it —
  /// and the schema verifier would compare a real file against tables nobody
  /// created.
  ///
  /// Filtering here rather than at each call site means there is one answer to
  /// "what is in this database", and it is the true one.
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      super.allSchemaEntities.where(_belongsToUserDatabase).toList();

  /// True for the tables and indexes user.db owns.
  ///
  /// An index is matched by the table its `CREATE INDEX` names, not by its own
  /// name: `idx_one_active_enrollment` is on `enrollments` and shares no
  /// substring with it, and a naming convention is the wrong thing to make
  /// load-bearing when the SQL says so exactly.
  bool _belongsToUserDatabase(DatabaseSchemaEntity entity) {
    if (entity is TableInfo) return ownTables.contains(entity.actualTableName);
    if (entity is Index) {
      final sql = entity.createStatementsByDialect.values.first;
      final on = RegExp(
        r'\bON\s+"?(\w+)"?',
        caseSensitive: false,
      ).firstMatch(sql);
      return on != null && ownTables.contains(on.group(1));
    }
    // Anything else belongs here. The content tables are what is being
    // excluded, so the default has to be "create it" — otherwise a trigger or
    // a view added to `user_schema.drift` would be skipped without a word, the
    // database would open, and whatever it enforced would quietly stop being
    // enforced.
    return true;
  }

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
