import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_update.dart' show ContentUpdater;
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart'
    show customId, customUid;
import 'package:sogda/domain/exam_generator.dart' show ExamSection;
import 'package:sogda/domain/fsrs.dart' show Fsrs;
import 'package:sogda/domain/plan_engine.dart' show PlanDate, addDays;

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
    this.planDays = 0,
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

  /// "30 days planned": the days `plan_items` holds a plan for (#396).
  final int planDays;
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
  /// neither means anything on another phone. FR-M6-01 names both. An import
  /// empties `undo_stack` (#688 DA-5) and leaves the cache.
  ///
  /// `content_updates` is this phone's own course history: each update it
  /// installed, when it saw it, and whether its card went. An import leaves
  /// it, and a file's rows (older exports carry them) are not read: a
  /// Replace from an older course swapped in that course's history, and
  /// Today's card described an update two builds old (#1025).
  static const Set<String> excluded = <String>{
    'translation_cache',
    'undo_stack',
    'content_updates',
  };

  /// Every table an export carries, in dependency order — parents before the
  /// children whose foreign keys point at them, so a replace can insert in
  /// this order without turning the constraints off.
  static const List<String> tables = <String>[
    'settings',
    'enrollments',
    // Before the tables that name its words as `custom:<id>`: a merge gives
    // them fresh ids, and those tables are rewritten to match (#369).
    'custom_words',
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
    'daily_stats',
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
  };

  /// Tables whose `id` is meaningless off this device, and the child table
  /// that points at it.
  static const Map<String, String> _childOf = <String, String>{
    'quiz_attempts': 'quiz_answers',
    'exam_attempts': 'exam_answers',
  };

  /// The learner's own words (#363). On a merge their ids are this phone's
  /// to assign, like an attempt's. The rows that name one as `custom:<id>`
  /// follow the id it ends up with (#369).
  static const String _customWords = 'custom_words';
  static const Set<String> _namesCustomWords = <String>{
    'word_state',
    'review_log',
    'plan_items',
    'quiz_answers',
  };

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
  ///
  /// Read in one transaction (#700), so a rating landing mid-export can't
  /// put its `review_log` row in the file without its `word_state`.
  Future<Map<String, Object?>> export({String? contentVersion}) async {
    final data = <String, List<Map<String, Object?>>>{};
    await _db.transaction(() async {
      for (final table in tables) {
        data[table] = await _rowsOf(table);
      }
    });

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
  Future<BackupPreview> preview(String json) async {
    final backup = await _parsed(json, _columns);
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
      planDays: <String>{
        for (final row in _rowsIn(data, 'plan_items'))
          if (row['plan_date'] case final String day) day,
      }.length,
    );
  }

  /// Writes the file into the database. FR-M6-03/04.
  ///
  /// One transaction either way, so a file that turns out to be broken half
  /// way through leaves the previous data exactly as it was — which matters
  /// most for [ImportMode.replace], where the alternative is a phone with the
  /// old data deleted and the new data not written.
  ///
  /// [today] is the day Today is on: a merge clears what it can no longer
  /// hold, for `PlanEngine.replanToday` to plan again (#622).
  ///
  /// [aliases] are the installed course's PIPE-09 links, old uid to uid now
  /// (`ContentUpdater.aliases`): a file's rows under an old uid come in under
  /// the new one (#809).
  Future<void> import(
    String json, {
    required ImportMode mode,
    PlanDate? today,
    Map<String, String> aliases = const <String, String>{},
  }) async {
    final backup = await _parsed(json, _columns);
    final data = backup['tables']! as Map<String, Object?>;

    // Fresh ids assigned on a merge, by the table that reads them: an
    // attempt's under its answers' table, a word of the learner's own under
    // `custom_words`, for the tables that name it. Local to the run: two
    // imports must not see each other's mapping.
    final remap = <String, Map<int, int>>{};

    await _db.transaction(() async {
      // #839: `last_export` is this phone's bookkeeping, not progress, and a
      // file carries the export before itself: the day is written once the
      // share sheet has taken it. So an import leaves it as it was.
      final lastExport = await _setting(SettingKeys.lastExport.name);

      // #688 DA-5: an Undo still on screen would put back a word's
      // pre-import state, and delete the review_log row with its stored id,
      // which may now be another word's review. A reset empties it too.
      await _db.customStatement('DELETE FROM undo_stack');
      if (mode == ImportMode.replace) {
        // Children first: the foreign keys are on, so a parent cannot go
        // before the rows pointing at it.
        for (final table in tables.reversed) {
          await _db.customStatement('DELETE FROM "$table"');
        }
      }

      // #658: restoring onto a phone where nothing has been studied yet.
      // M6 comes after onboarding, so such a phone always has an open step,
      // a pace, study days and today's plan, and none of it is the learner's
      // history: it is setup's first guess. Merged by the usual rules, that
      // guess would close the file's open step on the day it started and
      // keep onboarding's settings. Here the file says where they are: its
      // steps and plan replace setup's, and its settings win. Everything
      // else merges as ever, and nothing studied is lost, because there is
      // none.
      final fileWins =
          mode == ImportMode.merge &&
          _rowsIn(data, 'enrollments').isNotEmpty &&
          !await _studiedHere();
      if (fileWins) {
        await _db.customStatement('DELETE FROM plan_items');
        await _db.customStatement('DELETE FROM enrollments');
      }

      for (final table in tables) {
        await _importTable(
          table,
          _rowsIn(data, table),
          mode,
          remap,
          aliases,
          fileWins: fileWins,
        );
      }

      await _db.customStatement('DELETE FROM settings WHERE key = ?', <Object?>[
        SettingKeys.lastExport.name,
      ]);
      if (lastExport != null) {
        await _replaceRow('settings', <String, Object?>{
          'key': SettingKeys.lastExport.name,
          'value': lastExport,
        });
      }

      if (mode == ImportMode.merge && today != null) await _replan(today);
    });

    _db.markTablesUpdated(_db.allTables.toSet());
  }

  /// #622: after a merge, what the merged data says can't stay planned.
  ///
  /// A new word the file has a schedule for can't be new here any more, on
  /// any day, so its open `new` rows go. Today's open revisions go too: they
  /// were picked from this phone's schedule alone. `PlanEngine.replanToday`
  /// then tops today up from the merged data (#937). What was done today
  /// stays done.
  Future<void> _replan(PlanDate today) async {
    await _db.customStatement('''
DELETE FROM plan_items
WHERE kind = 'new' AND completed_at IS NULL
  AND word_uid IN (
    SELECT word_uid FROM word_state WHERE status IN ('learning', 'done'))
''');
    await _db.customStatement(
      "DELETE FROM plan_items WHERE plan_date = ? AND kind = 'revise' "
      'AND completed_at IS NULL',
      <Object?>[today],
    );
  }

  Future<void> _importTable(
    String table,
    List<Map<String, Object?>> rows,
    ImportMode mode,
    Map<String, Map<int, int>> remap,
    Map<String, String> aliases, {
    bool fileWins = false,
  }) async {
    if (rows.isEmpty) return;

    final columns = await _columnsOf(table);
    final child = _childOf[table];
    // #809: the column naming a course word, or a grammar topic (#808), and
    // the file's keys, which a row moved to its uid now must not take (below).
    final aliased = <String, String>{
      for (final (name, column) in [
        ...ContentUpdater.aliasedColumns,
        ...ContentUpdater.aliasedGrammarColumns,
      ])
        name: column,
    }[table];
    final taken = <String>{for (final row in rows) _keyOf(table, row)};
    // Merged words of the learner's own get fresh ids, as attempts do; a
    // replace keeps them, and the mapping is then each id to itself (#618).
    final ownIds = table == _customWords;

    // A fresh id for every incoming attempt, and the same mapping applied to
    // its answers. Ids are per-device, so keeping them would collide with
    // whatever this phone happens to have used.
    final remapped = <int, int>{};
    final existing = mode == ImportMode.merge
        ? await _keysOf(table)
        : <String, Map<String, Object?>>{};

    // #712: a row whose id nothing reads goes in one batch with the rest of
    // its table, one trip to the database's isolate, not one a row (a year's
    // `review_log` is thousands). An attempt's and a word of the learner's
    // own's ids are read back for the rows naming them, and `enrollments`
    // reads its own rows as it goes (one open step): those go one by one.
    final queued = child == null && !ownIds && table != 'enrollments'
        ? <(String, List<Object?>)>[]
        : null;

    for (final row in rows) {
      final incoming = <String, Object?>{
        for (final column in columns)
          if (row.containsKey(column)) column: row[column],
      };

      // On a replace the table was just emptied, so the ids in the file
      // cannot collide and keeping them makes the round trip exact. On a
      // merge an AUTOINCREMENT id is this phone's to assign, in every table
      // whose row key doesn't hold it: the attempts and their answers, the
      // learner's own words and the rows that name them, and `review_log`
      // and `grammar_practice_log`, whose ids two phones that were both
      // studied share (#369).
      if (mode == ImportMode.merge && !rowKeys[table]!.contains('id')) {
        incoming.remove('id');
      }

      // #688 DA-6: recordings stay on the phone that made them (FR-M6-01),
      // so an imported Speaking answer names no file here, or another
      // attempt's. It comes in unrecorded; its points stand.
      if (table == 'exam_answers' &&
          incoming['section'] == ExamSection.speaking.name) {
        incoming['given'] = null;
      }

      // #622: a phone in use plans its own days, so the file's plan comes in
      // only where it was done. Its open rows would give a day planned on
      // both phones two plans, twice the new words, and make the other
      // phone's backlog this one's.
      if (mode == ImportMode.merge &&
          !fileWins &&
          table == 'plan_items' &&
          incoming['completed_at'] == null) {
        continue;
      }

      // The parent's new id goes on before the key is taken: a child row's
      // key is `(attempt_id, ord)`, and the attempt_id in the file is the
      // other phone's. Keying on that would match a local answer that has
      // nothing to do with it and drop the imported one.
      final mapped = <String, Object?>{
        ..._withRemappedParent(table, incoming, remap),
      };

      // `custom:<id>` as the id its word got here, before the key is taken:
      // `word_state`'s key is the uid. A word the file doesn't have would
      // name whichever of this phone's words has that id, so its rows stay
      // out (#369), a deleted word's reviews with them. A compare quiz's
      // `source_ref` can list `custom:<id>` too, and isn't rewritten:
      // nothing reads it back.
      //
      // A replace too (#618): it keeps the file's ids, and AUTOINCREMENT
      // resumes above the highest one, so a deleted word's id is the next
      // one given out, and the next word the learner adds would inherit its
      // history.
      if (_namesCustomWords.contains(table)) {
        if (customId('${mapped['word_uid']}') case final id?) {
          final here = remap[_customWords]?[id];
          if (here == null) continue;
          mapped['word_uid'] = customUid(here);
        }
      }

      // #809: a file exported under an older course names a word whose uid
      // has changed since by the old uid, which nothing here reads. It comes
      // in under the uid now, before the key is taken, so a merge compares
      // it with this phone's row as ever. Where the file has a row under the
      // new uid too, the update's rule (`UPDATE OR IGNORE`): that row wins,
      // and the old one stays where it was.
      if (aliases[mapped[aliased]] case final now? when aliased != null) {
        final moved = <String, Object?>{...mapped, aliased: now};
        if (!rowKeys[table]!.contains(aliased) ||
            taken.add(_keyOf(table, moved))) {
          mapped[aliased] = now;
        }
      }
      // #808: an exam's grammar ref, `<topic uid>#<n>`, moves with its topic
      // and keeps its `#<n>`, as on an update. The key is (attempt, ord).
      if (mapped['item_ref'] case final String ref
          when table == 'exam_answers' && ref.contains('#')) {
        final hash = ref.indexOf('#');
        if (aliases[ref.substring(0, hash)] case final now?) {
          mapped['item_ref'] = '$now${ref.substring(hash)}';
        }
      }

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
          if ((child != null || ownIds) && row['id'] is int) {
            remapped[row['id']! as int] = local['id']! as int;
          }
          // #622: a step begun on both phones began on the earlier day.
          if (table == 'enrollments' && mapped['started_on'] is String) {
            await _db.customStatement(
              'UPDATE enrollments SET started_on = MIN(started_on, ?) '
              'WHERE sublevel_code = ?',
              <Object?>[mapped['started_on'], mapped['sublevel_code']],
            );
          }
          final wins = fileWins && table == 'settings';
          if (!wins && !_isNewer(table, mapped, local)) continue;
          if (queued != null) {
            queued.add(_insertOf(table, mapped, replace: true));
          } else {
            await _replaceRow(table, mapped);
          }
          continue;
        }
      }

      if (queued != null) {
        if (mapped.isNotEmpty) queued.add(_insertOf(table, mapped));
        continue;
      }
      final id = await _insertRow(table, mapped);
      if ((child != null || ownIds) && row['id'] != null) {
        remapped[row['id']! as int] = id;
      }
    }

    if (queued != null && queued.isNotEmpty) {
      await _db.batch((batch) {
        for (final (sql, args) in queued) {
          batch.customStatement(sql, args);
        }
      });
    }
    if (child != null) remap[child] = remapped;
    if (ownIds) remap[_customWords] = remapped;
  }

  /// Inserts one row and returns its id, which an attempt's answers and a
  /// word of the learner's own's rows are remapped to. `customInsert` hands
  /// it back from the insert itself: no `last_insert_rowid()` round trip
  /// (#700).
  Future<int> _insertRow(String table, Map<String, Object?> row) async {
    if (row.isEmpty) return 0;
    final (sql, args) = _insertOf(table, row);
    return _db.customInsert(
      sql,
      variables: <Variable<Object>>[
        for (final arg in args) Variable<Object>(arg),
      ],
    );
  }

  Future<void> _replaceRow(String table, Map<String, Object?> row) async {
    final (sql, args) = _insertOf(table, row, replace: true);
    await _db.customStatement(sql, args);
  }

  /// [row]'s INSERT (OR REPLACE) into [table], and its arguments.
  static (String, List<Object?>) _insertOf(
    String table,
    Map<String, Object?> row, {
    bool replace = false,
  }) {
    final names = row.keys.toList();
    final placeholders = List<String>.filled(names.length, '?').join(', ');
    final quoted = names.map((name) => '"$name"').join(', ');
    return (
      'INSERT ${replace ? 'OR REPLACE ' : ''}INTO "$table" ($quoted) '
          'VALUES ($placeholders)',
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

  Future<String?> _setting(String key) async {
    final row = await _db
        .customSelect(
          'SELECT value FROM settings WHERE key = ?',
          variables: <Variable<Object>>[Variable<String>(key)],
        )
        .getSingleOrNull();
    return row?.read<String>('value');
  }

  /// Whether anything has been studied on this phone: a rating, or a
  /// grammar run (#658).
  Future<bool> _studiedHere() async {
    final row = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM review_log) '
          'OR EXISTS (SELECT 1 FROM grammar_practice_log) AS studied',
        )
        .getSingle();
    return row.read<bool>('studied');
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

  /// The numbers a file could set to what no screen can (#657): the ranges
  /// `settings.md`'s steppers and slider give them, and at least one study
  /// day (BR-PLAN-01; M5 keeps the last one). A `daily_new` of a million
  /// plans the whole course today, and a mask of 0 has no study day ever.
  /// Checked on `settings` rows by key and on `enrollments` by column. Read
  /// from the keys M3 reads them from, and FSRS's retention bounds (#820).
  static final Map<String, (num, num)> ranges = <String, (num, num)>{
    for (final key in SettingKeys.all)
      if (key case IntSetting(range: (:final min, :final max)))
        key.name: (min, max),
    SettingKeys.desiredRetention.name: (Fsrs.minRetention, Fsrs.maxRetention),
  };

  /// Each table's columns by name: its type and whether it takes null.
  /// Plain values, for a parse in another isolate to check rows against.
  late final _Columns _columns = <String, Map<String, (Object, bool)>>{
    for (final table in _db.allTables)
      table.actualTableName: <String, (Object, bool)>{
        for (final column in table.$columns)
          column.name: (column.type, column.$nullable),
      },
  };

  /// A file this long or longer is parsed and checked in an isolate of its
  /// own (#712): a year of use, ~5 MB, took ~290 ms in a debug VM, and the
  /// UI isolate paid it twice, for the preview and again for the import.
  // ponytail: a smaller file is parsed where it is: a spawn costs more than
  // it saves, and a widget test's fake clock never sees an isolate finish.
  static const int isolateFrom = 256 * 1024;

  /// [_parse], in an isolate once [json] is [isolateFrom] long. Static, so
  /// the isolate is sent the text and the columns and nothing else.
  static Future<Map<String, Object?>> _parsed(
    String json,
    _Columns columns,
  ) async => json.length < isolateFrom
      ? _parse(json, columns)
      : Isolate.run(() => _parse(json, columns));

  /// Parses and checks the version. FR-M6-02.
  ///
  /// An older file is read as it is: every migration this schema has had adds
  /// columns with defaults, so a row that predates one simply has no value for
  /// it and takes the default. A *newer* file is refused, because a column we
  /// have never heard of cannot be guessed at and dropping it silently would
  /// lose the learner's data without saying so.
  ///
  /// The file is from outside the app, so every row is checked here, before
  /// the preview (#657): SQLite would store `"stability": "x"` as text, and
  /// every typed read of it would then throw, Today's plan first.
  static Map<String, Object?> _parse(String json, _Columns columns) {
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
        'That file is JSON, but not a Sogda export.',
      );
    }

    final version = decoded['schema_version']! as int;
    if (version > AppDatabase.latestSchemaVersion) {
      throw ImportException(
        ImportRefusal.newerSchema,
        'That file was written by a newer version of Sogda '
        '(format $version, this build reads up to '
        '${AppDatabase.latestSchemaVersion}). Update the app and try again.',
      );
    }

    if (decoded['content_version'] is! String?) _refuse('content_version');
    final data = decoded['tables']! as Map<String, Object?>;
    for (final MapEntry(key: table, value: rows) in data.entries) {
      if (rows is! List<Object?> ||
          rows.any((row) => row is! Map<String, Object?>)) {
        _refuse('tables.$table is not a list of rows');
      }
    }
    for (final table in tables) {
      _checkRows(table, _rowsIn(data, table), columns[table]!);
    }

    return decoded;
  }

  /// Each value of [rows] against its column's declared type and
  /// nullability, and the [ranges] (#657). A column the file has and this
  /// build doesn't is not checked: the import leaves it out.
  static void _checkRows(
    String table,
    List<Map<String, Object?>> rows,
    Map<String, (Object, bool)> columns,
  ) {
    for (final (index, row) in rows.indexed) {
      for (final MapEntry(key: name, value: value) in row.entries) {
        final column = columns[name];
        if (column == null) continue;
        final (type, nullable) = column;
        final fits = switch (value) {
          null => nullable,
          int() => type == DriftSqlType.int || type == DriftSqlType.double,
          double() => type == DriftSqlType.double,
          String() => type == DriftSqlType.string,
          _ => false,
        };
        if (!fits || (value is String && !_isWhen(name, value))) {
          _refuse('$table[$index].$name: $value');
        }
      }
      final ranged = switch (table) {
        'settings' => <(String, Object?)>[
          (row['key'].toString(), num.tryParse('${row['value']}')),
        ],
        'enrollments' => <(String, Object?)>[
          ('daily_new', row['daily_new']),
          ('study_days_mask', row['study_days_mask']),
        ],
        _ => const <(String, Object?)>[],
      };
      for (final (name, value) in ranged) {
        final range = ranges[name];
        if (range == null || value is! num) continue;
        if (value < range.$1 || value > range.$2) {
          _refuse('$table[$index].$name: $value is outside $range');
        }
      }
    }
  }

  /// #820: a date or an instant is `TEXT`, so the type check passes any
  /// string, and a date that isn't one throws in every read that parses it
  /// (Today's estimate, the next rating). A day (`*_on`, `plan_date`, `day`)
  /// is a real `YYYY-MM-DD`; an instant (`*_at`, `due`, `last_review`) is
  /// one `DateTime.parse` reads. Any other column passes.
  static bool _isWhen(String column, String value) {
    if (column.endsWith('_on') || column == 'plan_date' || column == 'day') {
      return _day.hasMatch(value) && addDays(value, 0) == value;
    }
    if (column.endsWith('_at') || column == 'due' || column == 'last_review') {
      return DateTime.tryParse(value) != null;
    }
    return true;
  }

  static final RegExp _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static Never _refuse(String what) => throw ImportException(
    ImportRefusal.notABackup,
    'That file is JSON, but not a Sogda export ($what).',
  );
}

typedef _Columns = Map<String, Map<String, (Object, bool)>>;
