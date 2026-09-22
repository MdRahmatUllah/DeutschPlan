@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// `docs/02-data/user-database.md` is the contract this file holds the schema
/// to. Every table it lists must exist, and every rule it states as a key rule
/// must be enforced by the database rather than by whichever repository
/// remembers to.
///
/// A CHECK that is never exercised is indistinguishable from a comment, so each
/// one here is proved by an insert that must fail, not only by one that passes.
void main() {
  // The WAL test opens a second AppDatabase, on its own executor. drift cannot
  // tell that apart from the mistake the warning is for, and prints a stack
  // trace over the run.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    // Opening is lazy; this forces the schema to be created now, so a DDL error
    // fails setUp rather than the first unrelated test.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  Future<Set<String>> namesOf(String type) async {
    final rows = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = ? AND name NOT LIKE 'sqlite_%'",
          variables: <Variable<Object>>[Variable<String>(type)],
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  /// Runs a statement the schema must refuse.
  Future<void> expectRejected(String sql, {required String because}) async {
    await expectLater(
      db.customStatement(sql),
      throwsA(isA<SqliteException>()),
      reason: because,
    );
  }

  group('the tables user-database.md lists', () {
    // Straight off the table in the doc, in its order.
    const documented = <String>{
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

    test('all exist', () async {
      expect(await namesOf('table'), containsAll(documented));
    });

    test('and nothing else does', () async {
      // A table nobody documented is a table nobody will migrate. namesOf
      // already drops SQLite's own sqlite_* bookkeeping.
      expect((await namesOf('table')).difference(documented), isEmpty);
    });

    test('drift generated a typed accessor for every one of them', () {
      // A superset, not an equality: `content.drift` is included too so drift
      // can type-check ContentDao's queries, which puts the content tables in
      // allTables as well. They are never created here — the test above is
      // what holds that line.
      expect(
        db.allTables.map((t) => t.actualTableName).toSet(),
        containsAll(documented),
        reason:
            'user_schema.drift is the single source (ADR 23); a table it '
            'declares that drift did not pick up means the include is wrong',
      );
    });

    test('ownTables is exactly what the doc lists', () {
      // `onCreate` builds only these, so a name missing here is a table the
      // app would never create, and one added by mistake is a content table
      // that would shadow the attached course.
      expect(AppDatabase.ownTables, documented);
    });
  });

  group('the indexes the engines need', () {
    test('exist', () async {
      expect(await namesOf('index'), <String>{
        'idx_word_state_due',
        'idx_word_state_status',
        'idx_review_log_word',
        'idx_review_log_at',
        'idx_one_active_enrollment',
        'idx_plan_items_date',
        'idx_plan_items_backlog',
        'idx_grammar_state_due',
        'idx_exam_attempts_step',
      });
    });

    test(
      'the backlog index leads with the columns that query filters',
      () async {
        // BR-PLAN-05: the backlog is open 'new' rows with plan_date < today. An
        // index on plan_date alone cannot serve that, which is why this one
        // exists; leading with kind and completed_at is the whole point of it.
        final sql = await db
            .customSelect(
              'SELECT sql FROM sqlite_master '
              "WHERE name = 'idx_plan_items_backlog'",
            )
            .getSingle();
        expect(
          sql.read<String>('sql'),
          contains('(kind, completed_at, plan_date)'),
        );
      },
    );
  });

  group('the status rules the docs state, enforced by the database', () {
    test('only one enrollment can be open at a time', () async {
      // BR-COURSE-04: the row with completed_on IS NULL is the active step.
      // A plain unique index would not hold this — SQLite treats every NULL in
      // a unique index as distinct — which is why the index is on a constant.
      await db.customStatement(
        'INSERT INTO enrollments '
        '(sublevel_code, started_on, daily_new, study_days_mask) '
        "VALUES ('A1.1', '2026-01-01', 10, 127)",
      );
      await expectRejected(
        'INSERT INTO enrollments '
        '(sublevel_code, started_on, daily_new, study_days_mask) '
        "VALUES ('A1.2', '2026-01-02', 10, 127)",
        because: 'two open enrollments means no single active step',
      );

      // Completing the first frees the slot, which is how the learner moves on.
      await db.customStatement(
        "UPDATE enrollments SET completed_on = '2026-02-01' "
        "WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        'INSERT INTO enrollments '
        '(sublevel_code, started_on, daily_new, study_days_mask) '
        "VALUES ('A1.2', '2026-02-01', 10, 127)",
      );
    });

    test('word_state.status is one of the four in BR-STATUS', () async {
      await expectRejected(
        "INSERT INTO word_state (word_uid, status) VALUES ('w1', 'mastered')",
        because: 'BR-STATUS names todo, learning, done and suspended only',
      );
      await db.customStatement(
        "INSERT INTO word_state (word_uid, status) VALUES ('w1', 'learning')",
      );
    });

    test('card_mode is plain or cloze', () async {
      await expectRejected(
        "INSERT INTO word_state (word_uid, card_mode) VALUES ('w2', 'typing')",
        because: 'BR-FSRS-06 switches between plain and cloze, nothing else',
      );
    });

    test('a rating is 1 to 4', () async {
      for (final rating in <int>[0, 5]) {
        await expectRejected(
          'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
          "VALUES ('w1', '2026-01-01T00:00:00Z', $rating, 'daily')",
          because: 'FSRS ratings are Again, Hard, Good, Easy — 1 to 4',
        );
      }
      await db.customStatement(
        'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
        "VALUES ('w1', '2026-01-01T00:00:00Z', 4, 'daily')",
      );
    });

    test('a review names where it came from', () async {
      await expectRejected(
        'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
        "VALUES ('w1', '2026-01-01T00:00:00Z', 3, 'somewhere')",
        because:
            'stats split reviews by source, so an unknown one would vanish '
            'from every chart silently',
      );
    });

    test('a plan item is new or revise', () async {
      await expectRejected(
        'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
        "VALUES ('2026-01-01', 'w1', 'grammar', 'A1.1')",
        because: 'the plan has two kinds; grammar is scheduled separately',
      );
    });

    test('an exam attempt has three states and three seeds', () async {
      await expectRejected(
        'INSERT INTO exam_attempts (sublevel_code, seed, started_at, status) '
        "VALUES ('A1.1', 1, '2026-01-01T00:00:00Z', 'paused')",
        because: 'FR-L12-04 has in_progress, finished and abandoned',
      );
      await expectRejected(
        'INSERT INTO exam_attempts (sublevel_code, seed, started_at) '
        "VALUES ('A1.1', 4, '2026-01-01T00:00:00Z')",
        because: 'each step ships three exam papers',
      );
    });

    test('a quiz verdict is one of the four the verdict row draws', () async {
      await db.customStatement(
        'INSERT INTO quiz_attempts '
        '(started_at, direction, source, seed, length) '
        "VALUES ('2026-01-01T00:00:00Z', 'de_bn', 'plan', 1, 10)",
      );
      await expectRejected(
        'INSERT INTO quiz_answers '
        '(attempt_id, ord, word_uid, prompt, expected, verdict) '
        "VALUES (1, 1, 'w1', 'p', 'e', 'nearly')",
        because: 'DpVerdictRow draws correct, almost, wrongArticle and wrong',
      );
      // Unanswered is legal: rows are pre-inserted before they are answered.
      await db.customStatement(
        'INSERT INTO quiz_answers (attempt_id, ord, word_uid, prompt, expected) '
        "VALUES (1, 1, 'w1', 'p', 'e')",
      );
    });

    test('a sentence self-rating is 1 to 3, or absent', () async {
      await expectRejected(
        'INSERT INTO sentence_log (word_uid, ord, shown_on, self_rating) '
        "VALUES ('w1', 1, '2026-01-01', 4)",
        because: 'the sentence rating bar has three faces, not four',
      );
      await db.customStatement(
        'INSERT INTO sentence_log (word_uid, ord, shown_on) '
        "VALUES ('w1', 1, '2026-01-01')",
      );
    });
  });

  group('foreign keys', () {
    test('are on, so an answer cannot point at a missing attempt', () async {
      // Off by default in SQLite, and set per connection rather than stored in
      // the file. Without configureConnection every REFERENCES clause in the
      // DDL is a comment.
      final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      await expectRejected(
        'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
        "VALUES (999, 1, 'reading', 'p')",
        because: 'no attempt 999 exists',
      );
    });

    test('can be checked in bulk, which is what onUpgrade does', () async {
      // onUpgrade runs this after every migration, because alterTable turns
      // foreign keys off while it recreates a table. The statement is only
      // reachable once a migration step exists, so this is where it is proved
      // to parse and to read back.
      final dangling = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(dangling, isEmpty);
    });

    test('cascade, so deleting an attempt takes its answers with it', () async {
      await db.customStatement(
        'INSERT INTO exam_attempts (sublevel_code, seed, started_at) '
        "VALUES ('A1.1', 1, '2026-01-01T00:00:00Z')",
      );
      await db.customStatement(
        'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
        "VALUES (1, 1, 'reading', 'p')",
      );

      await db.customStatement('DELETE FROM exam_attempts WHERE id = 1');

      final left = await db
          .customSelect('SELECT COUNT(*) AS n FROM exam_answers')
          .getSingle();
      expect(left.read<int>('n'), 0);
    });
  });

  test('bumping the schema version without a migration fails loudly', () async {
    // The generated migrationSteps() raises for a version it has no step for.
    // An empty onUpgrade would swallow that, and the first learner to update
    // would open their existing file against the new schema.
    final dir = Directory.systemTemp.createTempSync('deutschplan_upgrade');
    final file = File('${dir.path}/user.sqlite');

    final v1 = AppDatabase(DatabaseConnection(NativeDatabase(file)));
    await v1.customSelect('SELECT 1').get();
    await v1.close();

    final v2 = _FutureSchema(DatabaseConnection(NativeDatabase(file)));
    await expectLater(
      v2.customSelect('SELECT 1').get(),
      throwsA(isA<ArgumentError>()),
    );
    await v2.close();

    dir.deleteSync(recursive: true);
  });

  test('the schema version is written where a raw inspection reads it', () async {
    // ADR 23: PRAGMA user_version replaces the schema_version table
    // user-database.md originally called for. This is what makes the pragma an
    // adequate replacement rather than a silent loss.
    expect(await db.fileSchemaVersion(), db.schemaVersion);
    expect(db.schemaVersion, greaterThan(0));
  });

  test('a database on disk is in WAL mode', () async {
    // user-database.md: "user.db uses WAL mode." A memory database always
    // reports 'memory', so this is the only place the setting can actually be
    // checked — and it runs through configureConnection, the same callback the
    // real isolate connection uses.
    final dir = Directory.systemTemp.createTempSync('deutschplan_wal');

    final onDisk = AppDatabase(
      DatabaseConnection(
        NativeDatabase(
          File('${dir.path}/user.sqlite'),
          setup: configureConnection,
        ),
      ),
    );

    final mode = await onDisk.customSelect('PRAGMA journal_mode').getSingle();
    expect(mode.read<String>('journal_mode'), 'wal');

    await onDisk.close();
    dir.deleteSync(recursive: true);
  });
}

/// The same schema one version ahead, with no migration written for it.
class _FutureSchema extends AppDatabase {
  _FutureSchema(super.e);

  @override
  int get schemaVersion => super.schemaVersion + 1;
}
