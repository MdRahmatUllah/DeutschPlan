@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show PlanRepository;
import 'package:deutschplan/data/repositories/plan_repository.dart' as repo;
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

    final raw = sqlite.sqlite3.open(content.path);
    try {
      // The fixture stops at A1.2, so there is no level boundary to cross.
      // `sublevels.ord` restarts at 1 in every level, which is exactly the
      // case `stepAfter` has to get right.
      raw.execute(
        "INSERT INTO sublevels (code, level_code, ord, word_count, "
        "grammar_count) VALUES ('A2.1', 'A2', 1, 0, 0)",
      );

      // The fixture has three words; a seven-a-day plan needs more than that.
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

    test('#327 its local date, not its UTC one', () async {
      // Just after local midnight and just before it: east of Greenwich the
      // first is still the day before in UTC, west of it the second is
      // already the day after.
      await wordState(
        's1',
        lastReview: DateTime(2026, 2, 21, 0, 30).toUtc().toIso8601String(),
      );
      await wordState(
        's2',
        lastReview: DateTime(2026, 2, 21, 23, 30).toUtc().toIso8601String(),
      );

      final candidates = await store.revisionCandidates();

      expect(candidates.map((c) => c.lastReview), everyElement('2026-02-21'));
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

      expect(await store.plannedOn(monday, PlanKind.newWord), <String>['s1']);
      expect(await store.plannedOn(monday, PlanKind.revise), <String>['s2']);
    });

    test('keeps the days apart', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's2',
      ]);

      expect(await store.plannedOn(monday, PlanKind.newWord), <String>['s1']);
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

    test('reads back in the order it was written', () async {
      // The learner walks new words in teaching order and revisions in
      // BR-PLAN-03's priority, and both are the order the engine wrote. Row
      // order happens to agree today; nothing guarantees it, so it is ordered
      // explicitly. Deliberately not alphabetical, or the assertion would
      // pass under a default sort too.
      const written = <String>['s9', 's2', 's14', 's1', 's7'];
      await store.addToPlan(monday, PlanKind.newWord, written);

      expect(await store.plannedOn(monday, PlanKind.newWord), written);
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

  group('the next step (BR-COURSE-05)', () {
    test('follows course order within a level', () async {
      expect(await store.stepAfter('A1.1'), 'A1.2');
    });

    test('and crosses the level boundary', () async {
      // `sublevels.ord` restarts at 1 in every level, so A2.1 has ord 1 just
      // as A1.1 does. Ordering on it alone sends the learner back to the
      // start of the course at every boundary.
      expect(await store.stepAfter('A1.2'), 'A2.1');
    });

    test('and is null at the end of the course', () async {
      expect(await store.stepAfter('A2.1'), isNull);
    });

    test(
      'an unknown step has no successor rather than the first one',
      () async {
        expect(await store.stepAfter('Z9.9'), isNull);
      },
    );
  });

  group('enrolling and completing', () {
    test('completing closes the open row', () async {
      await enroll();

      await store.completeStep('A1.1', '2026-03-10');

      expect(await store.activeStep(), isNull);
      expect(await store.hasEverEnrolled(), isTrue);
      expect(await store.lastCompletedStep(), 'A1.1');
    });

    test('and leaves an already-closed row alone', () async {
      // BR-COURSE-04 allows one open row; closing must not rewrite history.
      await enroll(step: 'A1.1', completedOn: '2026-03-05');

      await store.completeStep('A1.1', '2026-03-10');

      final row = await db
          .customSelect('SELECT completed_on AS c FROM enrollments')
          .getSingle();
      expect(row.read<String>('c'), '2026-03-05');
    });

    test('enrolling opens a step that reads back as active', () async {
      await store.enroll(
        const ActiveStep(
          sublevelCode: 'A1.2',
          startedOn: '2026-03-10',
          dailyNew: 5,
          studyDaysMask: 0x1F,
        ),
      );

      final step = await store.activeStep();
      expect(step!.sublevelCode, 'A1.2');
      expect(step.dailyNew, 5);
      expect(step.studyDaysMask, 0x1F);
    });

    test('completing then enrolling keeps one open row', () async {
      // The unique index is what enforces BR-COURSE-04, so this is the order
      // the engine has to use — and the test that says so.
      await enroll();
      await store.completeStep('A1.1', '2026-03-10');
      await store.enroll(
        const ActiveStep(
          sublevelCode: 'A1.2',
          startedOn: '2026-03-10',
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        ),
      );

      final open = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM enrollments WHERE completed_on IS NULL',
          )
          .getSingle();
      expect(open.read<int>('n'), 1);
      expect((await store.activeStep())!.sublevelCode, 'A1.2');
    });

    test('enrolling never destroys another step’s row', () async {
      // `INSERT OR REPLACE` resolved the conflict on the open-row index by
      // *deleting* the other enrollment — start date, frozen pace and all.
      // The engine calls `completeStep` first so it never hit this, but #92
      // enrols directly, and losing a row silently is the worst of the
      // options. Now the partial index refuses it out loud.
      await enroll(step: 'A1.1', startedOn: '2026-01-05', dailyNew: 3);

      await expectLater(
        store.enroll(
          const ActiveStep(
            sublevelCode: 'A1.2',
            startedOn: '2026-03-10',
            dailyNew: 7,
            studyDaysMask: PlanEngine.allDays,
          ),
        ),
        throwsA(anything),
      );

      final row = await db
          .customSelect(
            'SELECT sublevel_code AS c, started_on AS s, daily_new AS d '
            'FROM enrollments',
          )
          .getSingle();
      expect(row.read<String>('c'), 'A1.1');
      expect(row.read<String>('s'), '2026-01-05');
      expect(row.read<int>('d'), 3, reason: 'the frozen pace was lost');
    });

    test('a step can be restarted after it was finished', () async {
      // `INSERT OR REPLACE` rather than a plain insert: coming back to a step
      // must reopen the row, not fail on the primary key.
      await enroll(step: 'A1.1', completedOn: '2026-03-05');

      await store.enroll(
        const ActiveStep(
          sublevelCode: 'A1.1',
          startedOn: '2026-03-10',
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        ),
      );

      expect((await store.activeStep())!.startedOn, '2026-03-10');

      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM enrollments')
          .getSingle();
      expect(count.read<int>('n'), 1, reason: 'the restart duplicated the row');
    });

    test('nobody has enrolled on a fresh install', () async {
      expect(await store.hasEverEnrolled(), isFalse);
      expect(await store.lastCompletedStep(), isNull);
    });

    test('an open step is not a completed one', () async {
      // The discriminating case for the `completed_on IS NOT NULL` filter.
      // With a completed row present the ORDER BY hides the bug — SQLite
      // sorts NULL last under DESC — so it takes a learner who is part way
      // through their *first* step to show it.
      await enroll();

      expect(await store.lastCompletedStep(), isNull);
      expect(await store.hasEverEnrolled(), isTrue);
    });

    test('the last completed step is the most recent one', () async {
      await enroll(
        step: 'A1.1',
        startedOn: '2026-01-01',
        completedOn: '2026-02-01',
      );
      await enroll(
        step: 'A1.2',
        startedOn: '2026-02-01',
        completedOn: '2026-03-01',
      );

      expect(await store.lastCompletedStep(), 'A1.2');
    });

    test('and ties on the day break by when the step started', () async {
      // A catch-up run can burn through a short step and close two on the
      // same day. Without the second key the answer is whichever row the
      // query happens to reach first.
      await enroll(
        step: 'A1.1',
        startedOn: '2026-01-01',
        completedOn: '2026-03-01',
      );
      await enroll(
        step: 'A1.2',
        startedOn: '2026-02-01',
        completedOn: '2026-03-01',
      );

      expect(await store.lastCompletedStep(), 'A1.2');
    });
  });

  group('BR-PLAN-06 — a skipped word', () {
    test('stays in the backlog from the next day', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);
      await PlanRepository(db)
          .skip(planDate: monday, uid: 's1', kind: repo.PlanKind.newWord);

      expect(await store.backlogBefore(monday), isEmpty, reason: 'not today');
      expect(
        await store.backlogBefore(addDays(monday, 1)),
        containsAll(<String>['s1', 's2']),
      );
    });

    test('and is still skipped, not completed', () async {
      // The distinction the backlog rests on: `skipped` stops it being
      // offered again in the same session, `completed_at` takes it out.
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await PlanRepository(db)
          .skip(planDate: monday, uid: 's1', kind: repo.PlanKind.newWord);

      final row = await db
          .customSelect('SELECT skipped, completed_at AS done FROM plan_items')
          .getSingle();
      expect(row.read<int>('skipped'), 1);
      expect(row.read<String?>('done'), isNull);
    });
  });

  group('the streak queries', () {
    Future<void> statsRow(
      String day, {
      int newDone = 0,
      int reviews = 0,
      int grammar = 0,
      int sentences = 0,
    }) => db.customStatement(
      'INSERT INTO daily_stats (day, new_done, reviews_done, grammar_done, '
      'sentences_done) VALUES (?, ?, ?, ?, ?)',
      <Object>[day, newDone, reviews, grammar, sentences],
    );

    test('a day counts when anything was done on it', () async {
      await statsRow(monday, newDone: 1);
      await statsRow(addDays(monday, 1), reviews: 3);
      await statsRow(addDays(monday, 2), grammar: 1);
      await statsRow(addDays(monday, 3), sentences: 2);

      expect(
        await store.activeDays(addDays(monday, 3), lookbackDays: 30),
        hasLength(4),
      );
    });

    test('and a row of zeroes does not', () async {
      // `_bumpDailyStats` can leave one behind when a rating is undone. A day
      // the learner did nothing on must not hold a streak together.
      await statsRow(monday);

      expect(await store.activeDays(monday, lookbackDays: 30), isEmpty);
    });

    test('the future is not counted', () async {
      await statsRow(addDays(monday, 5), newDone: 1);

      expect(await store.activeDays(monday, lookbackDays: 30), isEmpty);
    });

    test('and neither is anything past the lookback', () async {
      await statsRow(addDays(monday, -40), newDone: 1);
      await statsRow(addDays(monday, -10), newDone: 1);

      expect(await store.activeDays(monday, lookbackDays: 30), <String>{
        addDays(monday, -10),
      });
    });
  });

  group('the schedule check queries', () {
    test('counts new items planned and done', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's3',
      ]);
      await db.customStatement(
        "UPDATE plan_items SET completed_at = '2026-03-02T10:00:00Z' "
        "WHERE word_uid = 's1'",
      );

      expect(await store.newItemProgress(addDays(monday, 1)), (3, 1));
    });

    test('revise rows are not part of it', () async {
      // A missed revision is not "behind" — FSRS reschedules it by itself.
      await store.addToPlan(monday, PlanKind.revise, <String>['s1', 's2']);

      expect(await store.newItemProgress(monday), (0, 0));
    });

    test('and tomorrow is not either', () async {
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's1',
      ]);

      expect(await store.newItemProgress(monday), (0, 0));
    });
  });

  group('open plan items (BR-PLAN-10)', () {
    test('counts what is neither done nor skipped', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>[
        's1',
        's2',
        's3',
      ]);
      await db.customStatement(
        "UPDATE plan_items SET completed_at = '2026-03-02T10:00:00Z' "
        "WHERE word_uid = 's1'",
      );
      await db.customStatement(
        "UPDATE plan_items SET skipped = 1 WHERE word_uid = 's2'",
      );

      expect(await store.openPlanItems(monday), 1);
    });

    test('and a day with nothing planned is not open', () async {
      expect(await store.openPlanItems(monday), 0);
    });
  });

  group('BR-PLAN-09 — the measured timings', () {
    Future<void> log(String uid, String at) => db.customStatement(
      'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
      "VALUES (?, ?, 3, 'daily')",
      <Object>[uid, at],
    );

    test('are null until there is anything to measure', () async {
      final measured = await store.measuredSeconds();

      expect(measured.sessions, 0);
      expect(measured.enough, isFalse);
      expect(measured.newWord, isNull);
      expect(measured.revision, isNull);
    });

    test('come from the gaps between ratings of the same kind', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>[
        's1',
        's2',
        's3',
      ]);
      await log('s1', '2026-03-02T09:00:00Z');
      await log('s2', '2026-03-02T09:00:30Z');
      await log('s3', '2026-03-02T09:01:10Z');

      final measured = await store.measuredSeconds();

      expect(measured.newWord, 35, reason: 'gaps of 30 and 40, median 35');
    });

    test('new and revise are told apart by the plan row', () async {
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1', 's2']);
      await store.addToPlan(monday, PlanKind.revise, <String>['s3', 's4']);
      await log('s1', '2026-03-02T09:00:00Z');
      await log('s2', '2026-03-02T09:00:40Z');
      await log('s3', '2026-03-02T09:02:00Z');
      await log('s4', '2026-03-02T09:02:10Z');

      final measured = await store.measuredSeconds();

      expect(measured.newWord, 40);
      expect(measured.revision, 10);
    });

    test('a rating with no plan row is left out, not guessed at', () async {
      // From Search, a quiz or an exam: there is no block it belongs to.
      await log('s1', '2026-03-02T09:00:00Z');
      await log('s2', '2026-03-02T09:00:30Z');

      expect((await store.measuredSeconds()).newWord, isNull);
    });

    test('and the gap across two days is never taken', () async {
      // Grouped by day before the gaps are measured. The last review of
      // Monday and the first of Tuesday are not a gap.
      await store.addToPlan(monday, PlanKind.newWord, <String>['s1']);
      await store.addToPlan(addDays(monday, 1), PlanKind.newWord, <String>[
        's2',
      ]);
      await log('s1', '2026-03-02T09:00:00Z');
      await log('s2', '2026-03-03T09:00:10Z');

      expect((await store.measuredSeconds()).newWord, isNull);
    });

    test('seven sessions are what make them trusted', () async {
      for (var day = 0; day < 7; day++) {
        await db.customStatement(
          'INSERT INTO daily_stats (day, new_done) VALUES (?, 1)',
          <Object>[addDays(monday, day)],
        );
      }

      expect((await store.measuredSeconds()).enough, isTrue);
    });

    test('and six are not', () async {
      for (var day = 0; day < 6; day++) {
        await db.customStatement(
          'INSERT INTO daily_stats (day, new_done) VALUES (?, 1)',
          <Object>[addDays(monday, day)],
        );
      }

      expect((await store.measuredSeconds()).enough, isFalse);
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
