@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../db/content_fixture.dart';

/// `DriftPlanStore` — #76's half of the plan engine that touches the database.
///
/// The engine is tested against a map; this is tested against SQLite, because
/// the SQL is where the mistakes are: a join that drops suspended words, an
/// insert that clobbers `completed_at`, a backlog that includes today.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const monday = '2026-03-02';

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late DriftPlanStore store;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_plan');
    final content = ContentFixture.write('${directory.path}/content.db').file;

    // The fixture has three words; a seven-a-day plan needs more than that.
    final raw = sqlite.sqlite3.open(content.path);
    try {
      for (var i = 1; i <= 20; i++) {
        raw.execute(
          '''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, english, search_key, search_key_alt)
VALUES (?, 'A1.1', 'A1', ?, ?, ?, ?, ?, ?)
''',
          <Object>[
            's$i',
            100 + i,
            100 + i,
            'Wort$i',
            'word$i',
            'wort$i',
            'wort$i',
          ],
        );
      }
    } finally {
      raw.close();
    }

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );

    settings = SettingsRepository(db);
    await settings.load();
    store = DriftPlanStore(db, settings);
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

  Future<void> enroll({
    String step = 'A1.1',
    String startedOn = monday,
    int dailyNew = 7,
    int mask = PlanEngine.allDays,
    String? completedOn,
  }) => db.customStatement(
    '''
INSERT INTO enrollments (sublevel_code, started_on, daily_new,
                         study_days_mask, completed_on)
VALUES (?, ?, ?, ?, ?)
''',
    <Object?>[step, startedOn, dailyNew, mask, completedOn],
  );

  Future<void> wordState(
    String uid, {
    String status = 'learning',
    double stability = 5,
    String? due,
    String? lastReview = '2026-02-20T09:00:00Z',
  }) => db.customStatement(
    '''
INSERT INTO word_state (word_uid, status, stability, due, last_review)
VALUES (?, ?, ?, ?, ?)
''',
    <Object?>[uid, status, stability, due, lastReview],
  );

  group('the active step', () {
    test('is the open enrollment', () async {
      await enroll();

      final step = await store.activeStep();

      expect(step, isNotNull);
      expect(step!.sublevelCode, 'A1.1');
      expect(step.startedOn, monday);
      expect(step.dailyNew, 7);
      expect(step.studyDaysMask, PlanEngine.allDays);
    });

    test('is null before anyone enrolls', () async {
      expect(await store.activeStep(), isNull);
    });

    test('a finished step is not the active one', () async {
      // BR-COURSE-04: exactly one step is active. A learner between steps has
      // none, and planning must stop rather than plan against the old one.
      await enroll(completedOn: '2026-03-20');

      expect(await store.activeStep(), isNull);
    });

    test('and it reads the open one, not the first row', () async {
      await enroll(step: 'A1.1', completedOn: '2026-03-20');
      await enroll(step: 'A1.2', startedOn: '2026-03-21', dailyNew: 5);

      expect((await store.activeStep())!.sublevelCode, 'A1.2');
    });
  });

  group('the next new words', () {
    test('come in teaching order', () async {
      final picked = await store.unplannedWords('A1.1', limit: 5);

      final ordered = await db
          .customSelect(
            "SELECT uid FROM words WHERE sublevel_code = 'A1.1' "
            'ORDER BY seq_in_sublevel LIMIT 5',
          )
          .get();

      expect(picked, <String>[
        for (final row in ordered) row.read<String>('uid'),
      ]);
    });

    test('only from the step asked for', () async {
      final picked = await store.unplannedWords('A1.2', limit: 10);

      for (final uid in picked) {
        final row = await db
            .customSelect(
              'SELECT sublevel_code AS c FROM words WHERE uid = ?',
              variables: <Variable<Object>>[Variable<String>(uid)],
            )
            .getSingle();
        expect(row.read<String>('c'), 'A1.2');
      }
    });

    test('never one already planned', () async {
      // The backlog is made of plan rows, so a word sitting in it must not
      // come round again as new.
      final first = await store.unplannedWords('A1.1', limit: 3);
      await store.addToPlan(monday, PlanKind.newWord, first);

      final second = await store.unplannedWords('A1.1', limit: 3);

      expect(second.toSet().intersection(first.toSet()), isEmpty);
    });

    test('never a suspended one', () async {
      // BR-STATUS-03: suspended words are out of plans until resumed, and
      // that has to include never having been introduced.
      final head = (await store.unplannedWords('A1.1', limit: 1)).single;
      await wordState(head, status: 'suspended');

      expect(
        await store.unplannedWords('A1.1', limit: 10),
        isNot(contains(head)),
      );
    });

    test('never one already learning', () async {
      final head = (await store.unplannedWords('A1.1', limit: 1)).single;
      await wordState(head);

      expect(
        await store.unplannedWords('A1.1', limit: 10),
        isNot(contains(head)),
      );
    });

    test('a limit of zero asks for nothing', () async {
      expect(await store.unplannedWords('A1.1', limit: 0), isEmpty);
    });

    test('and an exhausted step gives back an empty list', () async {
      // Bounded, not `while (picked.isNotEmpty)`. If the query ever stops
      // filtering out what it has already handed back, an unbounded loop here
      // spins forever and the whole suite hangs with no failure to read — I
      // hit exactly that, and a test that can hang is worse than one that
      // fails. Ten rounds is far more than the fixture needs.
      var rounds = 0;
      var picked = await store.unplannedWords('A1.1', limit: 100);
      while (picked.isNotEmpty && rounds++ < 10) {
        await store.addToPlan(monday, PlanKind.newWord, picked);
        picked = await store.unplannedWords('A1.1', limit: 100);
      }

      expect(
        rounds,
        lessThan(10),
        reason: 'the query kept returning words it had already given out',
      );
      expect(await store.unplannedWords('A1.1', limit: 7), isEmpty);
    });
  });

  group('the revision candidates', () {
    test('are the words the learner has met', () async {
      await wordState('s1');
      await wordState('s2', status: 'done', stability: 20);

      final candidates = await store.revisionCandidates();

      expect(
        candidates.map((c) => c.uid),
        unorderedEquals(<String>['s1', 's2']),
      );
    });

    test('exclude suspended and to-do words', () async {
      // BR-STATUS-03, and a to-do word has nothing to revise.
      await wordState('s1', status: 'suspended');
      await wordState('s2', status: 'todo', lastReview: null);

      expect(await store.revisionCandidates(), isEmpty);
    });

    test('exclude a word with no review yet', () async {
      // Retrievability needs a last review. Without one there is no curve to
      // put it on, and a null would sort ahead of everything.
      await wordState('s1', lastReview: null);

      expect(await store.revisionCandidates(), isEmpty);
    });

    test('carry the fields the ranking needs', () async {
      await wordState('s1', stability: 12.5, due: '2026-03-05');

      final candidate = (await store.revisionCandidates()).single;

      expect(candidate.stability, 12.5);
      expect(candidate.due, '2026-03-05');
    });

    test('cut last_review down to its date', () async {
      // It is stored as an instant and the engine works in local days. A
      // timestamp reaching `daysBetween` would fail to parse.
      await wordState('s1', lastReview: '2026-02-20T09:00:00Z');

      final candidate = (await store.revisionCandidates()).single;

      expect(candidate.lastReview, '2026-02-20');
      expect(
        () => parsePlanDate(candidate.lastReview),
        returnsNormally,
        reason: 'the engine could not parse it',
      );
    });
  });

  group('writing the plan', () {
    test('adds rows that read back', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);

      expect(await store.plannedOn(monday, PlanKind.newWord), <String>{
        's1',
        's2',
      });
    });

    test('keeps the kinds apart', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await store.addToPlan(monday, PlanKind.revise, <String>['s2']);

      expect(await store.plannedOn(monday, PlanKind.newWord), <String>{'s1'});
      expect(await store.plannedOn(monday, PlanKind.revise), <String>{'s2'});
    });

    test('keeps the days apart', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's2',
      ]);

      expect(await store.plannedOn(monday, PlanKind.newWord), <String>{'s1'});
    });

    test('carries the word\'s own step, not the learner\'s', () async {
      // A revise row for a word from an earlier step must say so, or the Learn
      // tab's per-step counts drift.
      await store.addToPlan(monday, PlanKind.revise, <String>[
        ContentFixture.haus,
      ]);

      final row = await db
          .customSelect(
            'SELECT sublevel_code AS c FROM plan_items WHERE word_uid = ?',
            variables: <Variable<Object>>[
              Variable<String>(ContentFixture.haus),
            ],
          )
          .getSingle();

      expect(row.read<String>('c'), isNotEmpty);
    });

    test('writing twice does not double the rows', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);

      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM plan_items')
          .getSingle();

      expect(count.read<int>('n'), 2);
    });

    test('and does not un-complete what the learner has done', () async {
      // The reason it is INSERT OR IGNORE rather than an upsert. Reopening a
      // day mid-session must not wipe the morning's work.
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await db.customStatement(
        "UPDATE plan_items SET completed_at = '2026-03-02T10:00:00Z'",
      );

      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);

      final row = await db
          .customSelect('SELECT completed_at AS done FROM plan_items')
          .getSingle();
      expect(row.read<String?>('done'), isNotNull);
    });

    test('an empty list writes nothing', () async {
      await store.addToPlan(monday, PlanKind.newWord, const <String>[]);

      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM plan_items')
          .getSingle();
      expect(count.read<int>('n'), 0);
    });
  });

  group('the backlog', () {
    test('is the open new rows from before today', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's2',
      ]);

      expect(await store.backlogBefore(addDays(monday, 2)), <String>[
        's2',
        's1',
      ], reason: 'newest day first');
    });

    test('never includes today', () async {
      // BR-PLAN-05: it is what was missed, not what is open now. Including
      // today would show the learner their own morning as overdue.
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);

      expect(await store.backlogBefore(monday), isEmpty);
    });

    test('drops a row once it is completed', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);
      await db.customStatement(
        "UPDATE plan_items SET completed_at = '2026-03-02T10:00:00Z' "
        "WHERE word_uid = 's1'",
      );

      expect(await store.backlogBefore(addDays(monday, 1)), <String>['s2']);
    });

    test('but keeps a skipped one', () async {
      // BR-PLAN-06: a skip leaves the word uncompleted, and it appears in the
      // backlog from the next day. `skipped` stops it coming round again in
      // the same session; it does not remove it.
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await db.customStatement('UPDATE plan_items SET skipped = 1');

      expect(await store.backlogBefore(addDays(monday, 1)), <String>['s1']);
    });

    test('and never a revise row', () async {
      // A missed revision is not backlog: FSRS reschedules it by itself.
      await store.addToPlan(monday, PlanKind.revise, <String>['s1']);

      expect(await store.backlogBefore(addDays(monday, 1)), isEmpty);
    });
  });

  group('grammar due', () {
    Future<void> topic(String uid, {String? due, String status = 'learning'}) =>
        db.customStatement(
          'INSERT INTO grammar_state (grammar_uid, due, status) '
          'VALUES (?, ?, ?)',
          <Object?>[uid, due, status],
        );

    test('is the topics due on or before the day', () async {
      await topic('g1', due: '2026-03-01');
      await topic('g2', due: monday);
      await topic('g3', due: '2026-03-03');

      expect(await store.grammarDueOn(monday), <String>['g1', 'g2']);
    });

    test('and never one with no schedule', () async {
      await topic('g1');

      expect(await store.grammarDueOn(monday), isEmpty);
    });

    test('nor a suspended one', () async {
      // Grammar runs on the same scheduler and the same statuses as words, so
      // BR-STATUS-03 applies to it too.
      await topic('g1', due: '2026-03-01', status: 'suspended');

      expect(await store.grammarDueOn(monday), isEmpty);
    });
  });

  group('last_planned_date', () {
    test('round-trips as a plan date', () async {
      await store.setLastPlannedDate(monday);

      expect(await store.lastPlannedDate(), monday);
    });

    test('is null before the first run', () async {
      expect(await store.lastPlannedDate(), isNull);
    });

    test('survives a reload, which is the point of storing it', () async {
      await store.setLastPlannedDate('2026-12-31');

      final reloaded = SettingsRepository(db);
      await reloaded.load();
      addTearDown(reloaded.dispose);

      expect(
        await DriftPlanStore(db, reloaded).lastPlannedDate(),
        '2026-12-31',
      );
    });

    test('keeps single-digit months and days padded', () async {
      // The column sorts as a string and every query compares it that way. An
      // unpadded "2026-3-4" sorts after "2026-12-31".
      await store.setLastPlannedDate('2026-03-04');

      expect(await store.lastPlannedDate(), '2026-03-04');
    });
  });

  group('end to end, against SQLite rather than a map', () {
    test('a first day plans seven and a backlog forms behind it', () async {
      await enroll();
      final engine = PlanEngine(
        store: store,
        reviseCount: 10,
        backlogCatchupDays: 30,
      );

      final first = await engine.openDay(monday);
      expect(first.newToday, hasLength(7));
      expect(first.backlog, isEmpty);

      final later = await engine.openDay(addDays(monday, 2));
      expect(later.newToday, hasLength(7));
      expect(later.backlog, hasLength(14), reason: 'Monday and Tuesday');
      expect(
        later.newToday.toSet().intersection(later.backlog.toSet()),
        isEmpty,
        reason: 'a word was planned twice',
      );
    });

    test('and reopening it changes nothing', () async {
      await enroll();
      final engine = PlanEngine(
        store: store,
        reviseCount: 10,
        backlogCatchupDays: 30,
      );

      final first = await engine.openDay(monday);
      final again = await engine.openDay(monday);

      expect(again.newToday, first.newToday);

      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM plan_items')
          .getSingle();
      expect(count.read<int>('n'), first.newToday.length);
    });

    test('a met word comes back to revise, and today\'s new do not', () async {
      await enroll();
      await wordState('s20', due: '2026-02-28');

      final plan = await PlanEngine(
        store: store,
        reviseCount: 10,
        backlogCatchupDays: 30,
      ).openDay(monday);

      expect(plan.revise, contains('s20'));
      expect(plan.revise.toSet().intersection(plan.newToday.toSet()), isEmpty);
    });
  });
}
