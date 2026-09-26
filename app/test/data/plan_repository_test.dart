@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// `PlanRepository`: the writes that have to be all-or-nothing.
///
/// `plan-engine.md` decides what goes in a plan; this decides nothing. What
/// these tests are about is that a rating lands in all five tables or none of
/// them, and that undo puts every one of them back.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late PlanRepository plan;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_plan_repo');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    // The course, as the app has it: the backlog's reads skip a course word
    // it doesn't have (BR-CONTENT-02), so their words are the fixture's.
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    plan = PlanRepository(db);
  });

  tearDown(() async {
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  const today = '2026-03-04';
  const now = '2026-03-04T09:00:00Z';

  ScheduledState scheduled({
    double stability = 3,
    String status = 'learning',
    String cardMode = 'plain',
    int reps = 1,
    int lapses = 0,
  }) => ScheduledState(
    stability: stability,
    difficulty: 5,
    due: '2026-03-07',
    fsrsState: 2,
    reps: reps,
    lapses: lapses,
    status: status,
    cardMode: cardMode,
    elapsedDays: 1,
    scheduledDays: 3,
  );

  Future<void> planFor(String uid, {PlanKind kind = PlanKind.newWord}) =>
      plan.writePlan(<PlanEntry>[
        PlanEntry(
          planDate: today,
          wordUid: uid,
          kind: kind,
          sublevelCode: 'A1.1',
        ),
      ]);

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return row.read<int>('n');
  }

  group('writing a plan', () {
    test('is idempotent, so reopening the day does not double it', () async {
      await planFor('w1');
      await planFor('w1');
      expect(await count('plan_items'), 1);
    });

    test('a whole day goes in together', () async {
      await plan.writePlan(<PlanEntry>[
        for (final uid in <String>['w1', 'w2', 'w3'])
          PlanEntry(
            planDate: today,
            wordUid: uid,
            kind: PlanKind.newWord,
            sublevelCode: 'A1.1',
          ),
      ]);
      expect(await plan.watchPlan(today).first, hasLength(3));
    });
  });

  group('rating', () {
    test('writes all five tables', () async {
      await planFor('w1');
      await plan.rate(
        uid: 'w1',
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: now,
        today: today,
        planDate: today,
        kind: PlanKind.newWord,
        seconds: 12,
      );

      expect(await count('word_state'), 1);
      expect(await count('review_log'), 1);
      expect(await count('undo_stack'), 1);

      final item = (await plan.watchPlan(today).first).single;
      expect(item.completedAt, now);

      final stats = await plan.statsFor(today);
      expect(stats!.newDone, 1);
      expect(stats.seconds, 12);
    });

    test('a rating outside the plan still logs and still counts', () async {
      // `search` and `known` ratings have no plan row. They still belong in
      // the log and the day's totals.
      await plan.rate(
        uid: 'w9',
        rating: 4,
        next: scheduled(),
        source: ReviewSource.known,
        reviewedAt: now,
        today: today,
      );

      expect(await count('review_log'), 1);
      expect((await plan.statsFor(today))!.reviewsDone, 1);
    });

    test('nothing lands when the transaction fails', () async {
      // A rating that reached three tables of five would leave the streak and
      // the word list disagreeing, with nothing to say which was right. The
      // CHECK on `rating` is the cheapest way to make the write fail halfway.
      await planFor('w1');

      await expectLater(
        plan.rate(
          uid: 'w1',
          rating: 9,
          next: scheduled(),
          source: ReviewSource.daily,
          reviewedAt: now,
          today: today,
          planDate: today,
          kind: PlanKind.newWord,
        ),
        throwsA(isA<SqliteException>()),
      );

      expect(await count('word_state'), 0);
      expect(await count('review_log'), 0);
      expect(await count('undo_stack'), 0);
      expect(await plan.statsFor(today), isNull);
      expect((await plan.watchPlan(today).first).single.completedAt, isNull);
    });

    test('the day totals accumulate rather than overwrite', () async {
      await plan.rate(
        uid: 'a',
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: '${today}T09:00:00Z',
        today: today,
        seconds: 5,
      );
      await plan.rate(
        uid: 'b',
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: '${today}T09:01:00Z',
        today: today,
        seconds: 7,
      );

      final stats = await plan.statsFor(today);
      expect(stats!.reviewsDone, 2);
      expect(stats.seconds, 12);
    });
  });

  group('undo', () {
    Future<void> rateOnce(String uid, {double stability = 3}) => plan.rate(
      uid: uid,
      rating: 3,
      next: scheduled(stability: stability),
      source: ReviewSource.daily,
      reviewedAt: now,
      today: today,
      planDate: today,
      kind: PlanKind.newWord,
      seconds: 10,
    );

    test('a first rating leaves no word_state behind', () async {
      // "Before" was *no row*. Restoring an empty one would leave the word
      // `learning` for ever, and the plan would never offer it as new again.
      await planFor('w1');
      await rateOnce('w1');

      expect(await plan.undo(), 'w1');
      expect(await count('word_state'), 0);
    });

    test('a later rating restores the previous row exactly', () async {
      await planFor('w1');
      await rateOnce('w1', stability: 3);
      await plan.rate(
        uid: 'w1',
        rating: 1,
        next: scheduled(stability: 0.4, lapses: 1, reps: 2),
        source: ReviewSource.daily,
        reviewedAt: '${today}T10:00:00Z',
        today: today,
      );

      await plan.undo();

      final state = await (db.select(
        db.wordState,
      )..where((t) => t.wordUid.equals('w1'))).getSingle();
      expect(state.stability, 3);
      expect(state.lapses, 0);
      expect(state.reps, 1);
    });

    test('the log entry goes with it', () async {
      await planFor('w1');
      await rateOnce('w1');
      await plan.undo();
      expect(await count('review_log'), 0);
    });

    test('the plan row reopens', () async {
      await planFor('w1');
      await rateOnce('w1');
      await plan.undo();
      expect((await plan.watchPlan(today).first).single.completedAt, isNull);
    });

    test('the day totals come back down', () async {
      await planFor('w1');
      await rateOnce('w1');
      await plan.undo();
      expect((await plan.statsFor(today))!.newDone, 0);
    });

    test('totals never go negative', () async {
      // Undoing more than was done should floor at zero rather than leave the
      // streak reading -1.
      await planFor('w1');
      await rateOnce('w1');
      await plan.undo();
      await plan.undo();
      expect((await plan.statsFor(today))!.newDone, 0);
    });

    test('the time spent comes back too', () async {
      // BR-PLAN-09 derives the session estimate from these seconds. Leaving
      // them behind would make it drift upward every time someone undoes.
      await planFor('w1');
      await rateOnce('w1');
      expect((await plan.statsFor(today))!.seconds, 10);

      await plan.undo();
      expect((await plan.statsFor(today))!.seconds, 0);
    });

    test('only the rating being undone leaves the log', () async {
      // Two ratings of the same word at the same timestamp: a quiz rating a
      // batch, or a caller passing a date rather than an instant. Deleting by
      // (word_uid, reviewed_at) would take both.
      for (var i = 0; i < 2; i++) {
        await plan.rate(
          uid: 'w1',
          rating: 3,
          next: scheduled(),
          source: ReviewSource.quiz,
          reviewedAt: now,
          today: today,
        );
      }
      expect(await count('review_log'), 2);

      await plan.undo();
      expect(await count('review_log'), 1);
    });

    test('rating a skipped row clears the skip', () async {
      await planFor('w1');
      await plan.skip(planDate: today, uid: 'w1', kind: PlanKind.newWord);
      await rateOnce('w1');

      final item = (await plan.watchPlan(today).first).single;
      expect(item.completedAt, isNotNull);
      expect(item.skipped, 0, reason: 'a rated row is not a skipped one');
    });

    test('nothing to undo is not an error', () async {
      expect(await plan.undo(), isNull);
    });

    test('it undoes the most recent rating first', () async {
      await plan.rate(
        uid: 'a',
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: '${today}T09:00:00Z',
        today: today,
      );
      await plan.rate(
        uid: 'b',
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: '${today}T09:01:00Z',
        today: today,
      );

      expect(await plan.undo(), 'b');
      expect(await plan.undo(), 'a');
    });
  });

  group('the undo stack', () {
    test('is trimmed to twenty', () async {
      for (var i = 0; i < 25; i++) {
        await plan.rate(
          uid: 'w$i',
          rating: 3,
          next: scheduled(),
          source: ReviewSource.daily,
          reviewedAt: '${today}T09:${i.toString().padLeft(2, '0')}:00Z',
          today: today,
        );
      }
      expect(await plan.undoDepthNow(), PlanRepository.undoDepth);
    });

    test('the twenty it keeps are the most recent', () async {
      for (var i = 0; i < 25; i++) {
        await plan.rate(
          uid: 'w$i',
          rating: 3,
          next: scheduled(),
          source: ReviewSource.daily,
          reviewedAt: '${today}T09:${i.toString().padLeft(2, '0')}:00Z',
          today: today,
        );
      }
      expect(await plan.undo(), 'w24');
    });

    test('the depth is the twenty user-database.md names', () {
      expect(PlanRepository.undoDepth, 20);
    });
  });

  group('the backlog', () {
    test('is open new rows from before today, newest first', () async {
      // BR-PLAN-05: there is no backlog table, because an incomplete plan row
      // *is* the backlog.
      await plan.writePlan(<PlanEntry>[
        for (final (date, uid) in <(String, String)>[
          ('2026-03-01', ContentFixture.haus),
          ('2026-03-02', ContentFixture.tuer),
          (today, ContentFixture.strasse),
        ])
          PlanEntry(
            planDate: date,
            wordUid: uid,
            kind: PlanKind.newWord,
            sublevelCode: 'A1.1',
          ),
      ]);

      final backlog = await plan.watchBacklog(today).first;
      expect(
        <String>[for (final item in backlog) item.planDate],
        <String>['2026-03-02', '2026-03-01'],
      );
    });

    test('a completed row leaves it', () async {
      await plan.writePlan(<PlanEntry>[
        const PlanEntry(
          planDate: '2026-03-01',
          wordUid: ContentFixture.haus,
          kind: PlanKind.newWord,
          sublevelCode: 'A1.1',
        ),
      ]);
      await plan.rate(
        uid: ContentFixture.haus,
        rating: 3,
        next: scheduled(),
        source: ReviewSource.daily,
        reviewedAt: now,
        today: today,
        planDate: '2026-03-01',
        kind: PlanKind.newWord,
      );

      expect(await plan.watchBacklog(today).first, isEmpty);
    });

    test('a skipped row stays in it', () async {
      // Skip is not completion: the word comes back tomorrow.
      await plan.writePlan(<PlanEntry>[
        const PlanEntry(
          planDate: '2026-03-01',
          wordUid: ContentFixture.haus,
          kind: PlanKind.newWord,
          sublevelCode: 'A1.1',
        ),
      ]);
      await plan.skip(
        planDate: '2026-03-01',
        uid: ContentFixture.haus,
        kind: PlanKind.newWord,
      );

      expect(await plan.watchBacklog(today).first, hasLength(1));
    });

    test('revise rows are not backlog', () async {
      await plan.writePlan(<PlanEntry>[
        const PlanEntry(
          planDate: '2026-03-01',
          wordUid: ContentFixture.haus,
          kind: PlanKind.revise,
          sublevelCode: 'A1.1',
        ),
      ]);
      expect(await plan.watchBacklog(today).first, isEmpty);
    });

    test("#368 a suspended word's row: out of Today's count, still in T4's "
        'list, which follows its state', () async {
      await plan.writePlan(<PlanEntry>[
        for (final uid in <String>[ContentFixture.haus, ContentFixture.tuer])
          PlanEntry(
            planDate: '2026-03-01',
            wordUid: uid,
            kind: PlanKind.newWord,
            sublevelCode: 'A1.1',
          ),
      ]);
      final t4 = plan.watchBacklogWithStates(today);
      final lists = <List<String>>[];
      final listening = t4.listen(
        (rows) => lists.add(<String>[for (final row in rows) row.wordUid]),
      );
      addTearDown(listening.cancel);
      await pumpEventQueue();
      await db.customStatement(
        'INSERT INTO word_state (word_uid, status) '
        "VALUES ('${ContentFixture.haus}', 'suspended')",
      );
      db.markTablesUpdated(<TableInfo<Table, Object?>>{db.wordState});
      await pumpEventQueue();

      expect(
        <String>[
          for (final row in await plan.watchBacklog(today).first) row.wordUid,
        ],
        <String>[ContentFixture.tuer],
      );
      expect(lists.length, greaterThanOrEqualTo(2), reason: 'T4 re-read it');
      expect(lists.last, <String>[ContentFixture.haus, ContentFixture.tuer]);
    });
  });

  group('#456 BR-CONTENT-02 a word a content update removed', () {
    // 'gone' was in the course when it was planned; the course the app has
    // now doesn't have it. A word of my own is in no course, and is read.
    const gone = 'gone';
    const mine = 'custom:1';
    const yesterday = '2026-03-03';

    Future<void> planOn(String date, List<String> uids) =>
        plan.writePlan(<PlanEntry>[
          for (final uid in uids)
            PlanEntry(
              planDate: date,
              wordUid: uid,
              kind: PlanKind.newWord,
              sublevelCode: 'A1.1',
            ),
        ]);

    // Hidden, never deleted.
    Future<int> goneRows() => count("plan_items WHERE word_uid = '$gone'");

    List<String> uids(List<PlanItem> rows) => <String>[
      for (final row in rows) row.wordUid,
    ];

    // Newest day first, then by uid: 'custom:1' sorts before 'uid-haus'.
    const kept = <String>[mine, ContentFixture.haus];

    test("#456 BR-CONTENT-02 watchBacklog: not in Today's backlog card, "
        'and its row stays', () async {
      await planOn(yesterday, <String>[ContentFixture.haus, gone, mine]);

      expect(uids(await plan.watchBacklog(today).first), kept);
      expect(await goneRows(), 1);
    });

    test("#456 BR-CONTENT-02 watchBacklogWithStates: not in T4's list, "
        'and its row stays', () async {
      await planOn(yesterday, <String>[ContentFixture.haus, gone, mine]);

      expect(uids(await plan.watchBacklogWithStates(today).first), kept);
      expect(await goneRows(), 1);
    });

    test("#456 BR-CONTENT-02 backlog: not in a backlog session's queue, "
        'and its row stays', () async {
      await planOn(yesterday, <String>[ContentFixture.haus, gone, mine]);

      expect(uids(await plan.backlog(today)), kept);
      expect(await goneRows(), 1);
    });

    test('#456 BR-CONTENT-02 stillOpen: a reopened session does not ask it, '
        'and its row stays', () async {
      await planOn(today, <String>[ContentFixture.haus, gone, mine]);

      expect(await plan.stillOpen(today), <(String, String)>{
        ('new', ContentFixture.haus),
        ('new', mine),
      });
      expect(await goneRows(), 1);
    });
  });

  test('the plan stream re-emits when a rating completes a row', () async {
    await planFor('w1');

    final seen = <String?>[];
    final subscription = plan
        .watchPlan(today)
        .listen((rows) => seen.add(rows.single.completedAt));
    addTearDown(subscription.cancel);

    await pumpEventQueue();
    await plan.rate(
      uid: 'w1',
      rating: 3,
      next: scheduled(),
      source: ReviewSource.daily,
      reviewedAt: now,
      today: today,
      planDate: today,
      kind: PlanKind.newWord,
    );
    await pumpEventQueue();

    expect(seen.last, now);
  });
}
