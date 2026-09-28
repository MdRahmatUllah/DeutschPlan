@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/sentence_store.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'content_fixture.dart';

/// BR-CONTENT-04 (#630): a note and a comparison are listed like any word,
/// and are never planned, revised, quizzed, examined, placed, practised or
/// counted. The learner met the note before it was one: it has a state, is
/// due, and sits in the backlog. The comparison is new.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const note = 'uid-note';
  const compare = 'uid-compare';
  const today = '2026-03-02';
  const studied = <String>{ContentFixture.haus, ContentFixture.tuer};

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('sogda_kind');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    final raw = sqlite.sqlite3.open(content.path);
    try {
      raw.execute('''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, pos, english, category_id, search_key,
                   search_key_alt, kind)
VALUES
  ('$note', 'A1.1', 'A1', 3, 3, 'Haustür — Wortbildung -tür', 'noun',
   'compounds in -tür', 1, 'haustuer wortbildung tuer',
   'haustur wortbildung tur', 'note'),
  ('$compare', 'A1.1', 'A1', 4, 4, 'Haus ↔ Tür', 'noun', 'house vs. door',
   1, 'haus tuer', 'haus tur', 'compare');
INSERT INTO word_examples (word_uid, ord, german, english) VALUES
  ('$note', 1, 'Die Haustür ist rot.', 'The front door is red.'),
  ('$compare', 1, 'Das Haus hat eine Tür.', 'The house has a door.');
''');
    } finally {
      raw.close();
    }

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();

    for (final uid in <String>[ContentFixture.haus, note]) {
      await db.customStatement(
        'INSERT INTO word_state (word_uid, status, introduced_on, due, '
        'stability, reps, last_review) '
        "VALUES (?, 'learning', '2026-02-20', '2026-03-01', 3, 2, "
        "'2026-02-28T09:00:00Z')",
        <Object>[uid],
      );
    }
    await db.customStatement(
      'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
      "VALUES ('2026-02-27', '$note', 'new', 'A1.1')",
    );
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  test(
    'BR-CONTENT-04 a note is never planned, revised or in the backlog',
    () async {
      final store = DriftPlanStore(db, settings);

      expect(await store.unplannedWords('A1.1', limit: 10), <String>[
        ContentFixture.tuer,
      ]);
      expect(
        <String>{for (final c in await store.revisionCandidates()) c.uid},
        <String>{ContentFixture.haus},
      );
      expect(await store.backlogBefore(today), isEmpty);
      expect(await store.openPlanItems('2026-02-27'), 0);
    },
  );

  test('BR-CONTENT-04 a note is never quizzed, due or practised', () async {
    final words = WordRepository(db, settings);

    expect(
      <String>{for (final w in await words.quizWords().get()) w.uid},
      <String>{ContentFixture.haus},
    );
    expect(<String>{
      for (final w in await words.quizPool('A1.1').get()) w.uid,
    }, studied);
    expect(
      <String>{for (final w in await words.dueWords(7, today).get()) w.w.uid},
      <String>{ContentFixture.haus},
    );
    expect(
      <String>{
        for (final s in await DriftSentenceStore(
          db,
        ).candidates(today, gapDays: 0))
          s.wordUid,
      },
      <String>{ContentFixture.haus},
    );
  });

  test('#867 FR-M3-01 BR-CONTENT-02 BR-CONTENT-04 the retention estimate sums '
      "every word rated and not suspended, the learner's own too: not a note, "
      'nor a word a content update removed', () async {
    // Haus and the note were met in setUp, stability 3 each.
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, stability, reps) VALUES
  ('${ContentFixture.tuer}', 'suspended', 12, 3),
  ('${ContentFixture.strasse}', 'todo', 0, 0),
  ('uid-removed', 'learning', 40, 5),
  ('custom:1', 'done', 30, 6)
''');

    expect(await WordRepository(db, settings).learnedStabilities(), <double>[
      30,
      3,
    ]);
  });

  test('BR-CONTENT-04 a note is never examined or placed', () async {
    final exams = ExamRepository(db);
    final content = ContentDao(db);

    expect(<String>{
      for (final w in await exams.examWords('A1.1').get()) w.uid,
    }, studied);
    expect(<String>{
      for (final e in await exams.examExamples('A1.1').get()) e.uid,
    }, studied);
    expect(<String>{
      for (final w in await content.placementPool('A1.1')) w.uid,
    }, studied);
  });

  test('BR-CONTENT-04 a step counts its words, not its notes, and lists '
      'both', () async {
    final words = WordRepository(db, settings);

    final counts = await words.statusCountsForStep(7, 'A1.1').getSingle();
    expect(counts.total, 2);
    expect(counts.todo + counts.learning + counts.done, 2);
    final step = (await words.stepProgress(7).get()).firstWhere(
      (s) => s.code == 'A1.1',
    );
    expect(step.total, 2);
    expect(
      (await words.categoryProgress(7).get()).single.total,
      3,
      reason: "haus, tuer and strasse: the fixture's one category",
    );
    expect((await ContentDao(db).contentCounts().getSingle()).wordTotal, 3);

    final listed = <String>{
      for (final w in await words.wordsWithStateForStep(7, 'A1.1').get())
        w.w.uid,
    };
    expect(listed, <String>{...studied, note, compare});
  });
}
