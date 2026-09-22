@TestOn('vm')
library;

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// `PlanRepository`: the writes that have to be all-or-nothing.
///
/// `plan-engine.md` decides what goes in a plan; this decides nothing. What
/// these tests are about is that a rating lands in all five tables or none of
/// them, and that undo puts every one of them back.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PlanRepository plan;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    plan = PlanRepository(db);
  });

  tearDown(() => db.close());

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
        for (final date in <String>['2026-03-01', '2026-03-02', today])
          PlanEntry(
            planDate: date,
            wordUid: 'w-$date',
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
          wordUid: 'w1',
          kind: PlanKind.newWord,
          sublevelCode: 'A1.1',
        ),
      ]);
      await plan.rate(
        uid: 'w1',
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
          wordUid: 'w1',
          kind: PlanKind.newWord,
          sublevelCode: 'A1.1',
        ),
      ]);
      await plan.skip(
        planDate: '2026-03-01',
        uid: 'w1',
        kind: PlanKind.newWord,
      );

      expect(await plan.watchBacklog(today).first, hasLength(1));
    });

    test('revise rows are not backlog', () async {
      await plan.writePlan(<PlanEntry>[
        const PlanEntry(
          planDate: '2026-03-01',
          wordUid: 'w1',
          kind: PlanKind.revise,
          sublevelCode: 'A1.1',
        ),
      ]);
      expect(await plan.watchBacklog(today).first, isEmpty);
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
