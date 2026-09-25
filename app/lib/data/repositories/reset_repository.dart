import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart'
    show PlanDate, addDays, parsePlanDate, planDate;
import 'package:drift/drift.dart' show Variable;

/// M7 · Reset (`reset.md`, #149): one step's progress, or all of it.
class ResetRepository {
  ResetRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// The settings a full reset keeps (FR-M7-02): how the app looks and
  /// speaks, which the learner set before the course began.
  static final Set<String> kept = <String>{
    SettingKeys.themeMode.name,
    SettingKeys.uiLanguage.name,
  };

  /// The steps there is something of to reset, in course order, and which is
  /// the current one: begun, or with a word, topic, quiz or mock of theirs
  /// touched.
  Future<List<({String code, bool current})>> steps() async {
    final rows = await _db.customSelect('''
SELECT s.code AS code,
  EXISTS (SELECT 1 FROM enrollments e
          WHERE e.sublevel_code = s.code AND e.completed_on IS NULL) AS current
FROM sublevels s JOIN levels l ON l.code = s.level_code
WHERE EXISTS (SELECT 1 FROM enrollments e WHERE e.sublevel_code = s.code)
   OR EXISTS (SELECT 1 FROM word_state ws JOIN words w ON w.uid = ws.word_uid
              WHERE w.sublevel_code = s.code)
   OR EXISTS (SELECT 1 FROM grammar_state gs
              JOIN grammar_topics g ON g.uid = gs.grammar_uid
              WHERE g.sublevel_code = s.code)
   OR EXISTS (SELECT 1 FROM exam_attempts x WHERE x.sublevel_code = s.code)
   OR EXISTS (SELECT 1 FROM quiz_attempts q
              WHERE q.source = 'stepLearned' AND q.source_ref = s.code)
ORDER BY l.ord, s.ord
''').get();
    return <({String code, bool current})>[
      for (final row in rows)
        (code: row.read<String>('code'), current: row.read<bool>('current')),
    ];
  }

  /// FR-M7-01: [step]'s words back to To-do. Their states, plans, reviews and
  /// sentence practice go, its topics' grammar state and practice, and its
  /// quizzes and mock exams. The current step starts again [today]; any other
  /// is no longer started. Returns the mock exams deleted, whose Speaking
  /// recordings go with them.
  Future<List<int>> resetStep(String step, {required PlanDate today}) async {
    const words = 'SELECT uid FROM words WHERE sublevel_code = ?1';
    const topics = 'SELECT uid FROM grammar_topics WHERE sublevel_code = ?1';
    late final List<int> exams;
    late final bool current;
    await _db.transaction(() async {
      for (final table in <String>[
        'word_state',
        'plan_items',
        'review_log',
        'sentence_log',
      ]) {
        await _db.customStatement(
          'DELETE FROM $table WHERE word_uid IN ($words)',
          <Object>[step],
        );
      }
      for (final table in <String>['grammar_state', 'grammar_practice_log']) {
        await _db.customStatement(
          'DELETE FROM $table WHERE grammar_uid IN ($topics)',
          <Object>[step],
        );
      }
      exams = <int>[
        for (final row
            in await _db
                .customSelect(
                  'SELECT id FROM exam_attempts WHERE sublevel_code = ?1',
                  variables: <Variable<Object>>[Variable<String>(step)],
                )
                .get())
          row.read<int>('id'),
      ];
      // Their answers go with them (ON DELETE CASCADE).
      await _db.customStatement(
        'DELETE FROM exam_attempts WHERE sublevel_code = ?1',
        <Object>[step],
      );
      await _db.customStatement(
        "DELETE FROM quiz_attempts WHERE source = 'stepLearned' "
        'AND source_ref = ?1',
        <Object>[step],
      );
      current =
          (await _db
                  .customSelect(
                    'SELECT 1 FROM enrollments WHERE sublevel_code = ?1 '
                    'AND completed_on IS NULL',
                    variables: <Variable<Object>>[Variable<String>(step)],
                  )
                  .get())
              .isNotEmpty;
      if (current) {
        await _db.customStatement(
          'UPDATE enrollments SET started_on = ?2 WHERE sublevel_code = ?1',
          <Object>[step, today],
        );
      } else {
        await _db.customStatement(
          'DELETE FROM enrollments WHERE sublevel_code = ?1',
          <Object>[step],
        );
      }
    });
    // Today was planned with the step's words, which are gone: plan it again,
    // from the step started over (BR-PLAN-08's record is written anew).
    final last = _settings.read(SettingKeys.lastPlannedDate);
    if (current && last != null && planDate(last).compareTo(today) >= 0) {
      await _settings.write(
        SettingKeys.lastPlannedDate,
        parsePlanDate(addDays(today, -1)),
      );
    }
    _db.markTablesUpdated(_db.allTables.toSet());
    return exams;
  }

  /// FR-M7-02: user.db as a first start has it, but for [kept]: every table
  /// an export carries and the two it leaves out.
  Future<void> resetEverything() async {
    await _db.transaction(() async {
      // Children first: the foreign keys are on.
      for (final table in <String>[
        ...BackupRepository.tables.reversed,
        ...BackupRepository.excluded,
      ]) {
        if (table == 'settings') {
          await _db.customStatement(
            'DELETE FROM settings WHERE key NOT IN '
            "(${kept.map((key) => "'$key'").join(', ')})",
          );
        } else {
          await _db.customStatement('DELETE FROM "$table"');
        }
      }
    });
    _db.markTablesUpdated(_db.allTables.toSet());
    await _settings.reload();
  }
}
