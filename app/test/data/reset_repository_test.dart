import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/reset_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// M7 · Reset (#149, `reset.md`).
void main() {
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late ResetRepository reset;

  const today = '2026-09-25';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_reset');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    reset = ResetRepository(db, settings);

    // A1.1 done (Haus, Tür, topic g1), A1.2 the current step (Straße): each
    // with its states, plans, reviews, sentences, grammar, quiz and mock.
    for (final uid in <String>[
      ContentFixture.haus,
      ContentFixture.tuer,
      ContentFixture.strasse,
    ]) {
      await db.customStatement(
        "INSERT INTO word_state (word_uid, status, due, reps, introduced_on) "
        "VALUES ('$uid', 'learning', '2026-09-26', 2, '2026-09-01')",
      );
      await db.customStatement(
        'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
        "VALUES ('$today', '$uid', 'revise', 'A1.2')",
      );
      await db.customStatement(
        'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
        "VALUES ('$uid', '2026-09-20T08:00:00Z', 3, 'daily')",
      );
      await db.customStatement(
        'INSERT INTO sentence_log (word_uid, ord, shown_on) '
        "VALUES ('$uid', 1, '2026-09-20')",
      );
    }
    await db.customStatement(
      "INSERT INTO grammar_state (grammar_uid) VALUES ('g1')",
    );
    await db.customStatement(
      'INSERT INTO grammar_practice_log '
      '(grammar_uid, practised_at, items, correct) '
      "VALUES ('g1', '2026-09-20T08:00:00Z', 3, 3)",
    );
    for (final (id, step) in <(int, String)>[(1, 'A1.1'), (2, 'A1.2')]) {
      await db.customStatement(
        'INSERT INTO exam_attempts (id, sublevel_code, seed, started_at) '
        "VALUES ($id, '$step', 1, '2026-09-20T08:00:00Z')",
      );
      await db.customStatement(
        'INSERT INTO exam_answers (attempt_id, ord, section, prompt) '
        "VALUES ($id, 1, 'vocabulary', 'Haus')",
      );
      await db.customStatement(
        'INSERT INTO quiz_attempts '
        '(started_at, direction, source, source_ref, seed, length) '
        "VALUES ('2026-09-20T08:00:00Z', 'deToEn', 'stepLearned', '$step', "
        '1, 10)',
      );
    }
    await db.customStatement(
      'INSERT INTO enrollments '
      '(sublevel_code, started_on, daily_new, study_days_mask, completed_on) '
      "VALUES ('A1.1', '2026-09-01', 7, 127, '2026-09-10'), "
      "('A1.2', '2026-09-11', 7, 127, NULL)",
    );
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 9, 25),
    );
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
    directory.deleteSync(recursive: true);
  });

  Future<int> count(String sql) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $sql').getSingle())
          .read<int>('n');

  test("FR-M7-01 one step's words, grammar, quizzes and mocks go; the "
      "other step's stay", () async {
    final exams = await reset.resetStep('A1.1', today: today);

    expect(exams, <int>[1], reason: 'its recordings go with it');
    for (final table in <String>[
      'word_state',
      'plan_items',
      'review_log',
      'sentence_log',
    ]) {
      expect(
        await count("$table WHERE word_uid = '${ContentFixture.strasse}'"),
        1,
        reason: table,
      );
      expect(await count(table), 1, reason: '$table: A1.1 gone');
    }
    expect(await count('grammar_state'), 0);
    expect(await count('grammar_practice_log'), 0);
    expect(await count("exam_attempts WHERE sublevel_code = 'A1.1'"), 0);
    expect(await count('exam_answers'), 1, reason: "A1.1's went with it");
    expect(await count("quiz_attempts WHERE source_ref = 'A1.1'"), 0);
    expect(await count("quiz_attempts WHERE source_ref = 'A1.2'"), 1);
    // A1.1 is no longer started; A1.2 is still the current step.
    expect(await count("enrollments WHERE sublevel_code = 'A1.1'"), 0);
    expect(
      await count(
        "enrollments WHERE sublevel_code = 'A1.2' AND started_on = "
        "'2026-09-11'",
      ),
      1,
    );
    expect(planDate(settings.read(SettingKeys.lastPlannedDate)!), today);
  });

  test(
    'FR-M7-01 the steps to reset: begun or touched, the current marked',
    () async {
      expect(await reset.steps(), <({String code, bool current})>[
        (code: 'A1.1', current: false),
        (code: 'A1.2', current: true),
      ]);
      await reset.resetStep('A1.1', today: today);
      expect(await reset.steps(), <({String code, bool current})>[
        (code: 'A1.2', current: true),
      ]);
    },
  );

  test('FR-M7-01 the current step starts again today, planned anew', () async {
    await reset.resetStep('A1.2', today: today);

    expect(
      await count(
        "enrollments WHERE sublevel_code = 'A1.2' AND started_on = '$today' "
        'AND completed_on IS NULL',
      ),
      1,
    );
    expect(
      planDate(settings.read(SettingKeys.lastPlannedDate)!),
      '2026-09-24',
      reason: 'today is planned again, from the step started over',
    );
    expect(await count('word_state'), 2, reason: "A1.1's stay");
    expect(await count("enrollments WHERE sublevel_code = 'A1.1'"), 1);
  });

  test('#420 a step reset leaves the course where it started: T1 day '
      'and M1 Learning since do not move', () async {
    await db.customStatement(
      "INSERT INTO daily_stats (day, new_done) VALUES ('2026-09-01', 7), "
      "('2026-09-12', 5)",
    );
    final plans = PlanRepository(db);
    expect(await plans.courseStartedOn(), '2026-09-01');

    await reset.resetStep('A1.1', today: today); // the first, finished
    expect(await plans.courseStartedOn(), '2026-09-01');
    await reset.resetStep('A1.2', today: today); // the current, restarted
    expect(await plans.courseStartedOn(), '2026-09-01');

    await reset.resetEverything();
    expect(await plans.courseStartedOn(), isNull, reason: 'starts over');
  });

  test(
    'FR-M7-01 the only step, finished, starts over rather than goes',
    () async {
      // Auto-advance off: A1.1 finished and nothing after it. Its row going
      // would leave Today no way on, and onboarding at the next start.
      await db.customStatement(
        "DELETE FROM enrollments WHERE sublevel_code = 'A1.2'",
      );
      await reset.resetStep('A1.1', today: today);

      expect(
        await count(
          "enrollments WHERE sublevel_code = 'A1.1' AND started_on = '$today' "
          'AND completed_on IS NULL',
        ),
        1,
      );
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        '2026-09-24',
        reason: 'planned anew, as the current step',
      );
    },
  );

  test('FR-M7-01 a step reset empties the undo stack', () async {
    await db.customStatement(
      'INSERT INTO undo_stack (created_at, payload_json) '
      "VALUES ('2026-09-20T08:00:00Z', '{}')",
    );
    await reset.resetStep('A1.1', today: today);
    expect(await count('undo_stack'), 0);
  });

  test('FR-M7-02 everything goes but the theme and the language', () async {
    await settings.write(SettingKeys.themeMode, ThemeModeSetting.dark);
    await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
    await settings.write(SettingKeys.dailyNew, 12);

    // A row in every table the fixture leaves empty, so "empty" proves it
    // went: "my words" above all, which the dialog promises.
    await db.customStatement(
      'INSERT INTO quiz_answers (attempt_id, ord, word_uid, prompt, expected) '
      "VALUES (1, 1, 'x', 'Haus', 'house')",
    );
    await db.customStatement(
      'INSERT INTO custom_words (created_at, german, meaning) '
      "VALUES ('2026-09-20T08:00:00Z', 'Pfandflasche', 'deposit bottle')",
    );
    await db.customStatement(
      "INSERT INTO daily_stats (day, new_done) VALUES ('2026-09-20', 3)",
    );
    await db.customStatement(
      "INSERT INTO content_updates (version) VALUES ('202609251045')",
    );
    await db.customStatement(
      'INSERT INTO translation_cache '
      '(src_lang, tgt_lang, src_text, model, result, created_at) '
      "VALUES ('de', 'en', 'Haus', 'm', 'house', '2026-09-20T08:00:00Z')",
    );
    await db.customStatement(
      'INSERT INTO undo_stack (created_at, payload_json) '
      "VALUES ('2026-09-20T08:00:00Z', '{}')",
    );
    for (final table in <String>[
      'quiz_answers',
      'custom_words',
      'daily_stats',
      'content_updates',
      'translation_cache',
      'undo_stack',
    ]) {
      expect(await count(table), 1, reason: 'seeded: $table');
    }

    await reset.resetEverything();

    for (final table in <String>[
      ...BackupRepository.tables,
      ...BackupRepository.excluded,
    ]) {
      expect(await count(table), table == 'settings' ? 2 : 0, reason: table);
    }
    expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.dark);
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.bangla);
    expect(
      settings.read(SettingKeys.dailyNew),
      SettingKeys.dailyNew.defaultValue,
    );
    expect(settings.read(SettingKeys.lastPlannedDate), isNull);
  });

  test('FR-M7-02 the recordings go, the models stay', () async {
    final support = Directory('${directory.path}/support');
    File('${support.path}/recordings/1.m4a').createSync(recursive: true);
    File('${support.path}/recordings/2.m4a').createSync(recursive: true);
    final model = File('${support.path}/models/hy-mt/model.bin')
      ..createSync(recursive: true);
    final models = ModelRepository(settings, support: support);

    await models.deleteRecordings(<int>[1]);
    expect(File('${support.path}/recordings/1.m4a').existsSync(), isFalse);
    expect(File('${support.path}/recordings/2.m4a').existsSync(), isTrue);

    await models.deleteRecordings();
    expect(Directory('${support.path}/recordings').existsSync(), isFalse);
    expect(model.existsSync(), isTrue);
  });
}
