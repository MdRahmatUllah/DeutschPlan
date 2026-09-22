import 'dart:convert';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

/// How an import combines with what is already on the phone. FR-M6-03/04.
enum ImportMode {
  /// Keep both, row by row.
  merge,

  /// Wipe and insert. Everything on this phone goes.
  replace,
}

/// Why an import cannot go ahead.
enum ImportRefusal {
  /// Not JSON, or not JSON of this shape.
  notABackup,

  /// Written by a newer build. FR-M6-02: refuse rather than guess what a
  /// column we have never heard of means.
  newerSchema,
}

/// An import that was refused before anything was written.
class ImportException implements Exception {
  ImportException(this.reason, this.message);

  final ImportRefusal reason;
  final String message;

  @override
  String toString() => 'ImportException($reason): $message';
}

/// What the file holds, shown before anything is written. FR-M6-02.
@immutable
class BackupPreview {
  const BackupPreview({
    required this.schemaVersion,
    required this.contentVersion,
    required this.exportedAt,
    required this.rowCounts,
    required this.wordStates,
    required this.lastActive,
    required this.activeStep,
  });

  final int schemaVersion;
  final String? contentVersion;
  final String exportedAt;

  /// Rows per table, for a bug report and for the size line.
  final Map<String, int> rowCounts;

  /// "2,104 word states" on the import card.
  final int wordStates;

  /// "last active 20 Sep" — the latest review in the file.
  final String? lastActive;

  /// "A2.1" — the step that was open when the file was written.
  final String? activeStep;
}

/// Export and import of everything the learner owns. M6.
///
/// The file is JSON rather than a copy of `user.db`, because a database file
/// carries a schema and a JSON file carries data: an export taken on an older
/// build has to be readable by a newer one, and FR-M6-02 says so.
///
/// Nothing here touches the network. `share_plus` hands the file to whatever
/// the learner picks, which is the only way it leaves the phone (BR-PRIV-02).
class BackupRepository {
  BackupRepository(this._db);

  final AppDatabase _db;

  /// `translation_cache` is a cache and `undo_stack` is this session's, so
  /// neither means anything on another phone. FR-M6-01 names both.
  static const Set<String> excluded = <String>{
    'translation_cache',
    'undo_stack',
  };

  /// Every table an export carries, in dependency order — parents before the
  /// children whose foreign keys point at them, so a replace can insert in
  /// this order without turning the constraints off.
  static const List<String> tables = <String>[
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
  ];

  /// What makes a row the same row across two phones.
  ///
  /// The primary key, except where it is an autoincrement id — an id means
  /// nothing on another device, so those tables use the natural key the rows
  /// actually differ by and are given fresh ids on the way in.
  static const Map<String, List<String>> rowKeys = <String, List<String>>{
    'settings': <String>['key'],
    'enrollments': <String>['sublevel_code'],
    'word_state': <String>['word_uid'],
    // FR-M6-03 names this one: unioned by (word_uid, reviewed_at).
    'review_log': <String>['word_uid', 'reviewed_at'],
    'plan_items': <String>['plan_date', 'word_uid', 'kind'],
    'grammar_state': <String>['grammar_uid'],
    'grammar_practice_log': <String>['grammar_uid', 'practised_at'],
    'sentence_log': <String>['word_uid', 'ord', 'shown_on'],
    'quiz_attempts': <String>['started_at', 'seed', 'direction', 'source'],
    'quiz_answers': <String>['attempt_id', 'ord'],
    'exam_attempts': <String>['sublevel_code', 'seed', 'started_at'],
    'exam_answers': <String>['attempt_id', 'ord'],
    'custom_words': <String>['created_at', 'german'],
    'daily_stats': <String>['day'],
    'content_updates': <String>['version'],
  };

  /// Tables whose `id` is meaningless off this device, and the child table
  /// that points at it.
  static const Map<String, String> _childOf = <String, String>{
    'quiz_attempts': 'quiz_answers',
    'exam_attempts': 'exam_answers',
  };

  /// Tables whose `id` nothing reads back, so the insert does not pay for a
  /// `last_insert_rowid()` round trip. Only the two attempt tables do.
  static final Set<String> _needsId = _childOf.keys.toSet();

  /// The column on the row that says when it was last touched, where there is
  /// one. FR-M6-03's tie-break.
  static const Map<String, String> _recencyColumn = <String, String>{
    'word_state': 'last_review',
    'grammar_state': 'last_review',
    'plan_items': 'completed_at',
  };

  /// FR-M6-01's shape, exactly.
  ///
  /// Recordings are not in it — they are the only thing on the phone bigger
  /// than the course, and a backup nobody can email is not a backup. The UI
  /// says so; this is where it is true.
  Future<Map<String, Object?>> export({String? contentVersion}) async {
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      data[table] = await _rowsOf(table);
    }

    return <String, Object?>{
      'schema_version': AppDatabase.latestSchemaVersion,
      'content_version': contentVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
    };
  }

  Future<String> exportJson({String? contentVersion}) async =>
      jsonEncode(await export(contentVersion: contentVersion));

  /// Reads the file and says what is in it, without writing anything.
  ///
  /// Refuses here rather than half way through: FR-M6-02 shows the preview
  /// before writing, and a file that cannot be imported should say so before
  /// the learner has chosen merge or replace.
  BackupPreview preview(String json) {
    final backup = _parse(json);
    final data = backup['tables']! as Map<String, Object?>;

    final rowCounts = <String, int>{
      for (final entry in data.entries)
        entry.key: (entry.value! as List<Object?>).length,
    };

    // Only the values that are what they should be. `_parse` checks the
    // envelope, not every row, so a file with a null where a timestamp
    // belongs has to read as a file we cannot preview rather than a crash.
    final reviewedAt = <String>[
      for (final row in _rowsIn(data, 'review_log'))
        if (row['reviewed_at'] case final String at) at,
    ];
    final lastActive = reviewedAt.isEmpty
        ? null
        : reviewedAt.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

    String? activeStep;
    for (final row in _rowsIn(data, 'enrollments')) {
      if (row['completed_on'] == null && row['sublevel_code'] is String) {
        activeStep = row['sublevel_code']! as String;
      }
    }

    return BackupPreview(
      schemaVersion: backup['schema_version']! as int,
      contentVersion: backup['content_version'] as String?,
      exportedAt: backup['exported_at']! as String,
      rowCounts: rowCounts,
      wordStates: rowCounts['word_state'] ?? 0,
      lastActive: lastActive,
      activeStep: activeStep,
    );
  }

  /// Writes the file into the database. FR-M6-03/04.
  ///
  /// One transaction either way, so a file that turns out to be broken half
  /// way through leaves the previous data exactly as it was — which matters
  /// most for [ImportMode.replace], where the alternative is a phone with the
  /// old data deleted and the new data not written.
  Future<void> import(String json, {required ImportMode mode}) async {
    final backup = _parse(json);
    final data = backup['tables']! as Map<String, Object?>;

    // Fresh ids assigned to imported parents, read by the child table's pass.
    // Local to the run: two imports must not see each other's mapping.
    final remap = <String, Map<int, int>>{};

    await _db.transaction(() async {
      if (mode == ImportMode.replace) {
        // Children first: the foreign keys are on, so a parent cannot go
        // before the rows pointing at it.
        for (final table in tables.reversed) {
          await _db.customStatement('DELETE FROM "$table"');
        }
      }

      for (final table in tables) {
        await _importTable(table, _rowsIn(data, table), mode, remap);
      }
    });

    _db.markTablesUpdated(_db.allTables.toSet());
  }

  Future<void> _importTable(
    String table,
    List<Map<String, Object?>> rows,
    ImportMode mode,
    Map<String, Map<int, int>> remap,
  ) async {
    if (rows.isEmpty) return;

    final columns = await _columnsOf(table);
    final child = _childOf[table];

    // A fresh id for every incoming attempt, and the same mapping applied to
    // its answers. Ids are per-device, so keeping them would collide with
    // whatever this phone happens to have used.
    final remapped = <int, int>{};
    final existing = mode == ImportMode.merge
        ? await _keysOf(table)
        : <String, Map<String, Object?>>{};

    for (final row in rows) {
      final incoming = <String, Object?>{
        for (final column in columns)
          if (row.containsKey(column)) column: row[column],
      };

      // On a replace the table was just emptied, so the ids in the file
      // cannot collide and keeping them makes the round trip exact. On a
      // merge they are this phone's to assign, and the answers are remapped
      // to match.
      if (child != null && mode == ImportMode.merge) incoming.remove('id');

      // The parent's new id goes on before the key is taken: a child row's
      // key is `(attempt_id, ord)`, and the attempt_id in the file is the
      // other phone's. Keying on that would match a local answer that has
      // nothing to do with it and drop the imported one.
      final mapped = <String, Object?>{
        ..._withRemappedParent(table, incoming, remap),
      };

      // BR-COURSE-04 allows one open enrollment, enforced by a unique index.
      // Merging a backup from a phone the learner was further back on would
      // otherwise fail the whole import on that index — which is exactly the
      // case merge exists for. This phone says where they are; the imported
      // step comes in as a step they have been on.
      if (mode == ImportMode.merge &&
          table == 'enrollments' &&
          mapped['completed_on'] == null &&
          await _hasOpenEnrollment()) {
        mapped['completed_on'] = mapped['started_on'];
      }

      if (mode == ImportMode.merge) {
        final local = existing[_keyOf(table, mapped)];
        if (local != null) {
          if (child != null) remapped[row['id']! as int] = local['id']! as int;
          if (!_isNewer(table, mapped, local)) continue;
          await _replaceRow(table, mapped);
          continue;
        }
      }

      final id = await _insertRow(table, mapped);
      if (child != null && row['id'] != null) {
        remapped[row['id']! as int] = id;
      }
    }

    if (child != null) remap[child] = remapped;
  }

  /// Inserts one row, and returns its id only for the tables whose children
  /// need it. Thirteen of the fifteen never read it, and the extra
  /// `last_insert_rowid()` round trip is the expensive half of a large import.
  Future<int> _insertRow(String table, Map<String, Object?> row) async {
    final names = row.keys.toList();
    if (names.isEmpty) return 0;

    final placeholders = List<String>.filled(names.length, '?').join(', ');
    final quoted = names.map((name) => '"$name"').join(', ');
    final sql = 'INSERT INTO "$table" ($quoted) VALUES ($placeholders)';
    final variables = <Variable<Object>>[
      for (final name in names) Variable<Object>(row[name]),
    ];

    if (!_needsId.contains(table)) {
      await _db.customStatement(sql, <Object?>[
        for (final name in names) row[name],
      ]);
      return 0;
    }

    await _db.customInsert(sql, variables: variables);
    final inserted = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();
    return inserted.read<int>('id');
  }

  Future<void> _replaceRow(String table, Map<String, Object?> row) async {
    final names = row.keys.toList();
    final placeholders = List<String>.filled(names.length, '?').join(', ');
    final quoted = names.map((name) => '"$name"').join(', ');
    await _db.customStatement(
      'INSERT OR REPLACE INTO "$table" ($quoted) VALUES ($placeholders)',
      <Object?>[for (final name in names) row[name]],
    );
  }

  Map<String, Object?> _withRemappedParent(
    String table,
    Map<String, Object?> row,
    Map<String, Map<int, int>> remap,
  ) {
    final mapping = remap[table];
    if (mapping == null || !row.containsKey('attempt_id')) return row;
    final old = row['attempt_id'];
    return <String, Object?>{
      ...row,
      if (old is int) 'attempt_id': mapping[old] ?? old,
    };
  }

  /// FR-M6-03: the later row wins where the table records when it was
  /// touched. Where it does not, the row already on this phone stays — the
  /// learner is merging *into* their device, and a silent overwrite of
  /// something they cannot see is the worse failure.
  bool _isNewer(
    String table,
    Map<String, Object?> incoming,
    Map<String, Object?> local,
  ) {
    final column = _recencyColumn[table];
    if (column == null) return false;

    final theirs = incoming[column] as String?;
    final ours = local[column] as String?;
    if (theirs == null) return false;
    if (ours == null) return true;
    return theirs.compareTo(ours) > 0;
  }

  Future<List<Map<String, Object?>>> _rowsOf(String table) async {
    final rows = await _db.customSelect('SELECT * FROM "$table"').get();
    return <Map<String, Object?>>[for (final row in rows) row.data];
  }

  /// The rows already here, by key, for the merge comparison.
  Future<Map<String, Map<String, Object?>>> _keysOf(String table) async {
    final rows = await _rowsOf(table);
    return <String, Map<String, Object?>>{
      for (final row in rows) _keyOf(table, row): row,
    };
  }

  String _keyOf(String table, Map<String, Object?> row) =>
      rowKeys[table]!.map((column) => '${row[column]}').join('\u0000');

  Future<List<String>> _columnsOf(String table) async {
    final rows = await _db.customSelect('PRAGMA table_info("$table")').get();
    return <String>[for (final row in rows) row.read<String>('name')];
  }

  Future<bool> _hasOpenEnrollment() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM enrollments WHERE completed_on IS NULL',
        )
        .getSingle();
    return row.read<int>('n') > 0;
  }

  static List<Map<String, Object?>> _rowsIn(
    Map<String, Object?> data,
    String table,
  ) => <Map<String, Object?>>[
    for (final row in (data[table] ?? <Object?>[]) as List<Object?>)
      row! as Map<String, Object?>,
  ];

  /// Parses and checks the version. FR-M6-02.
  ///
  /// An older file is read as it is: every migration this schema has had adds
  /// columns with defaults, so a row that predates one simply has no value for
  /// it and takes the default. A *newer* file is refused, because a column we
  /// have never heard of cannot be guessed at and dropping it silently would
  /// lose the learner's data without saying so.
  Map<String, Object?> _parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw ImportException(
        ImportRefusal.notABackup,
        'That file is not JSON: ${error.message}',
      );
    }

    if (decoded is! Map<String, Object?> ||
        decoded['schema_version'] is! int ||
        decoded['exported_at'] is! String ||
        decoded['tables'] is! Map<String, Object?>) {
      throw ImportException(
        ImportRefusal.notABackup,
        'That file is JSON, but not a DeutschPlan export.',
      );
    }

    final version = decoded['schema_version']! as int;
    if (version > AppDatabase.latestSchemaVersion) {
      throw ImportException(
        ImportRefusal.newerSchema,
        'That file was written by a newer version of DeutschPlan '
        '(format $version, this build reads up to '
        '${AppDatabase.latestSchemaVersion}). Update the app and try again.',
      );
    }

    return decoded;
  }
}
