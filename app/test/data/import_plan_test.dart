@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/setup_repository.dart';
import 'package:sogda/domain/plan_engine.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../db/content_fixture.dart';

/// #622: moving to this phone by export and *Import and merge*, then opening
/// Today. Two phones on one content.db, the engine over each, as the app
/// has them: the backup tests check rows, this checks the day they make.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // A Saturday and the Sunday after it.
  const yesterday = '2026-09-26';
  const today = '2026-09-27';
  const allDays = PlanEngine.allDays;
  const noSunday = allDays & ~(1 << (DateTime.sunday - 1));

  late Directory directory;
  late File content;
  final phones = <_Phone>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sogda_import_plan');
    content = ContentFixture.write('${directory.path}/content.db').file;
    final raw = sqlite.sqlite3.open(content.path);
    try {
      // Enough of A1.1 for two days at seven a day.
      for (var i = 1; i <= 20; i++) {
        raw.execute(
          '''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, english, search_key, search_key_alt, kind)
VALUES (?, 'A1.1', 'A1', ?, ?, ?, ?, ?, ?, 'vocab')
''',
          <Object>['s$i', 100 + i, 100 + i, 'Wort$i', 'w$i', 'w$i', 'w$i'],
        );
      }
    } finally {
      raw.close();
    }
  });

  tearDown(() async {
    for (final phone in phones) {
      await phone.close();
    }
    phones.clear();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  Future<_Phone> setUpPhone(PlanDate on, {int mask = allDays}) async {
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    final settings = SettingsRepository(db);
    await settings.load();
    final phone = _Phone(db, settings);
    phones.add(phone);
    await SetupRepository(db, settings).commit(
      SetupChoice(
        step: 'A1.1',
        dailyNew: 7,
        reviseCount: 10,
        studyDaysMask: mask,
        reminderOn: false,
        reminderTime: (hour: 19, minute: 0),
      ),
      today: on,
    );
    await phone.engine.openDay(on);
    return phone;
  }

  /// The old phone: A1.1 from yesterday, yesterday's seven learned, and
  /// today opened (seven new, those seven to revise) before the export.
  ///
  /// [rated] of yesterday's seven were rated; the rest are its backlog.
  Future<String> oldPhoneExport({int rated = 7}) async {
    final old = await setUpPhone(yesterday);
    final day1 = await old.engine.openDay(yesterday);
    for (final uid in day1.newToday.take(rated)) {
      await old.rate(uid, '${yesterday}T09:00:00Z');
    }
    await old.engine.openDay(today);
    return BackupRepository(old.db).exportJson();
  }

  /// What #622's acceptance criteria say of today after the import.
  void expectOnePlan(DailyPlan plan, Set<String> introduced) {
    expect(
      plan.newToday.toSet().intersection(plan.revise.toSet()),
      isEmpty,
      reason: 'no word both in Revise and New today',
    );
    expect(
      plan.newToday.where(introduced.contains),
      isEmpty,
      reason: 'no word learned before is planned as new',
    );
    expect(plan.newToday.length, lessThanOrEqualTo(7), reason: 'daily_new');
    expect(plan.newToday.toSet().length, plan.newToday.length);
  }

  test(
    '#622 FR-M6-03 into a fresh setup: one plan for today, the learned '
    'words to revise once and seven not met yet, and the older start',
    () async {
      final file = await oldPhoneExport(rated: 6);
      final phone = await setUpPhone(today);

      await phone.importFile(file, today);
      final plan = await phone.engine.openDay(today);

      final introduced = await phone.introduced();
      expect(introduced, hasLength(6));
      expectOnePlan(plan, introduced);
      expect(plan.revise.toSet(), introduced, reason: 'each once');
      expect(plan.newToday, hasLength(7));
      expect(plan.backlog, hasLength(1), reason: "the file's plan is the plan");
      expect(await phone.startedOn('A1.1'), yesterday);
    },
  );

  test('#622 FR-M6-03 onto a phone in use since yesterday: its backlog of '
      "words the file has learned goes, and today revises the file's words "
      'too', () async {
    final file = await oldPhoneExport();
    final phone = await setUpPhone(yesterday);
    final first = (await phone.engine.openDay(yesterday)).newToday.first;
    await phone.rate(first, '${yesterday}T08:00:00Z');
    expect((await phone.engine.openDay(today)).revise, <String>[first]);

    await phone.importFile(file, today);
    final plan = await phone.engine.openDay(today);

    final introduced = await phone.introduced();
    expect(introduced, hasLength(7));
    expectOnePlan(plan, introduced);
    expect(plan.revise.toSet(), introduced, reason: 'the merged schedule');
    expect(plan.backlog, isEmpty, reason: 'all seven were learned elsewhere');
    expect(plan.newToday, hasLength(7));
  });

  test('#622 FR-M6-03 onto a phone that rated a card first: still one plan '
      'for today, topped up to the pace, and the older start', () async {
    final file = await oldPhoneExport();
    final phone = await setUpPhone(today);
    final first = (await phone.engine.openDay(today)).newToday.first;
    // A card rated here makes this a phone in use (#658): its settings and
    // open step stay.
    await phone.rate(first, '${today}T08:00:00Z');

    await phone.importFile(file, today);
    final plan = await phone.engine.openDay(today);

    // The file's seven, less the one rated here since: today's new word.
    final introduced = await phone.introduced(before: today);
    expect(introduced, hasLength(6));
    expectOnePlan(plan, introduced);
    expect(plan.revise.toSet(), introduced, reason: 'the merged schedule');
    expect(plan.newToday, hasLength(7), reason: 'topped up to daily_new');
    expect(plan.newToday.first, first, reason: 'what was done here stays');
    expect(await phone.startedOn('A1.1'), yesterday);
  });

  test('#622 FR-M6-03 set up on a rest day: no imported new words on a day '
      'Today calls a rest day', () async {
    final file = await oldPhoneExport();
    final phone = await setUpPhone(today, mask: noSunday);

    await phone.importFile(file, today);
    final plan = await phone.engine.openDay(today);

    expect(plan.isStudyDay || plan.newToday.isEmpty, isTrue);
    expectOnePlan(plan, await phone.introduced());
  });

  test('#622 and the same onto a phone in use whose rest day it is', () async {
    final file = await oldPhoneExport();
    final phone = await setUpPhone(today, mask: noSunday);
    await phone.rate('uid-haus', '${today}T08:00:00Z');

    await phone.importFile(file, today);
    final plan = await phone.engine.openDay(today);

    expect(plan.isStudyDay, isFalse, reason: "this phone's study days stay");
    expect(plan.newToday, isEmpty);
  });
}

class _Phone {
  _Phone(this.db, this.settings);

  final AppDatabase db;
  final SettingsRepository settings;

  /// A fresh engine each time, as an import's invalidation makes one.
  PlanEngine get engine => PlanEngine(
    store: DriftPlanStore(db, settings),
    reviseCount: 10,
    backlogCatchupDays: 30,
  );

  /// The first rating of a new word, as the session writes it.
  Future<void> rate(String uid, String at) async {
    await db.customStatement(
      'INSERT INTO word_state (word_uid, status, stability, due, reps, '
      "last_review) VALUES (?, 'learning', 3.0, ?, 1, ?)",
      <Object?>[uid, at.substring(0, 10), at],
    );
    await db.customStatement(
      'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
      "VALUES (?, ?, 3, 'daily')",
      <Object?>[uid, at],
    );
    await db.customStatement(
      "UPDATE plan_items SET completed_at = ? WHERE word_uid = ? AND kind = 'new'",
      <Object?>[at, uid],
    );
  }

  /// M6's import, and what the screen does after it.
  Future<void> importFile(String json, PlanDate today) async {
    await BackupRepository(db)
        .import(json, mode: ImportMode.merge, today: today);
    await settings.reload();
  }

  /// The words with a schedule, last rated before [before].
  Future<Set<String>> introduced({String before = '9999'}) async {
    final rows = await db
        .customSelect(
          "SELECT word_uid FROM word_state WHERE status = 'learning' "
          'AND last_review < ?',
          variables: <Variable<Object>>[Variable<String>(before)],
        )
        .get();
    return <String>{for (final row in rows) row.read<String>('word_uid')};
  }

  Future<String> startedOn(String step) async =>
      (await db
              .customSelect(
                'SELECT started_on FROM enrollments WHERE sublevel_code = ?',
                variables: <Variable<Object>>[Variable<String>(step)],
              )
              .getSingle())
          .read<String>('started_on');

  Future<void> close() async {
    await settings.dispose();
    await db.close();
  }
}
