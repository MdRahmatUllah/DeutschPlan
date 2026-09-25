@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// `RatingService` — #78.
///
/// The piece between `Fsrs` and `plan_items`. Most of the writing was already
/// there from M0; what is new is running the scheduler and deriving the two
/// things that are not FSRS — the status (BR-STATUS-02) and the card format
/// (BR-FSRS-06).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const uid = ContentFixture.haus;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late RatingService rating;
  late DateTime now;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_rating');
    final content = ContentFixture.write('${directory.path}/content.db').file;

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );

    settings = SettingsRepository(db);
    await settings.load();

    now = DateTime(2026, 3, 2, 9);
    rating = RatingService(
      db,
      settings,
      PlanRepository(db),
      WordRepository(db, settings),
      () => now,
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

  Future<WordStateData?> stateOf(String id) => (db.select(
    db.wordState,
  )..where((t) => t.wordUid.equals(id))).getSingleOrNull();

  Future<List<ReviewLogData>> logOf(String id) =>
      (db.select(db.reviewLog)..where((t) => t.wordUid.equals(id))).get();

  /// Rates [times] in a row, moving the clock a day each time.
  Future<void> rateRun(List<Rating> ratings, {String id = uid}) async {
    for (final r in ratings) {
      await rating.rate(id, r, source: ReviewSource.daily);
      now = now.add(const Duration(days: 1));
    }
  }

  group('a first rating', () {
    test('creates the word state from the scheduler', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      final state = await stateOf(uid);
      expect(state, isNotNull);
      expect(state!.stability, closeTo(Fsrs.defaultWeights[2], 0.0001));
      expect(state.reps, 1);
      expect(state.lapses, 0);
      expect(state.fsrsState, FsrsState.learning.value);
    });

    test('and the due date is four days out, as FSRS says', () async {
      // The reference value: Good on a fresh card is a four-day interval.
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await stateOf(uid))!.due, '2026-03-06');
    });

    test('records when it was introduced', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await stateOf(uid))!.introducedOn, '2026-03-02');
    });

    test('writes one log row with its rating and source', () async {
      await rating.rate(uid, Rating.hard, source: ReviewSource.quiz);

      final log = await logOf(uid);
      expect(log, hasLength(1));
      expect(log.single.rating, Rating.hard.value);
      expect(log.single.source, 'quiz');
      expect(log.single.elapsedDays, 0, reason: 'nothing to elapse from');
    });
  });

  group('BR-STATUS-02 — the status is derived', () {
    test('a fresh Good is still learning', () async {
      // Stability 3.71 is under the seven-day threshold.
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await stateOf(uid))!.status, WordStatus.learning.name);
    });

    test('a fresh Easy is done straight away', () async {
      // Stability 13.8 clears seven days on the first review.
      await rating.rate(uid, Rating.easy, source: ReviewSource.daily);

      expect((await stateOf(uid))!.status, WordStatus.done.name);
    });

    test('the threshold is the setting, not a constant', () async {
      await settings.write(SettingKeys.doneStabilityDays, 30);

      await rating.rate(uid, Rating.easy, source: ReviewSource.daily);

      expect(
        (await stateOf(uid))!.status,
        WordStatus.learning.name,
        reason: 'stability 13.8 is under a 30-day threshold',
      );
    });

    test('and a lapse moves a done word back to learning', () async {
      await rating.rate(uid, Rating.easy, source: ReviewSource.daily);
      expect((await stateOf(uid))!.status, WordStatus.done.name);

      now = now.add(const Duration(days: 14));
      await rating.rate(uid, Rating.again, source: ReviewSource.daily);

      expect((await stateOf(uid))!.status, WordStatus.learning.name);
      expect((await stateOf(uid))!.lapses, 1);
    });

    test('the threshold is inclusive, as BR-STATUS-01 writes it', () {
      // Unreachable through `rate`: FSRS stabilities are products of the
      // weights and never land exactly on an integer threshold, so planting
      // `>` for `>=` changes nothing observable there. The rule still says
      // `>=`, so it is held here, where it can be.
      expect(statusForStability(7, 7), WordStatus.done);
      expect(statusForStability(6.9999, 7), WordStatus.learning);
      expect(statusForStability(7.0001, 7), WordStatus.done);
      expect(
        statusForStability(0, 0),
        WordStatus.done,
        reason: 'a zero threshold',
      );
    });

    test('there is no path that sets done by hand', () async {
      // The rule is the derivation. A status that could be written directly
      // would drift from the stability it is supposed to describe.
      await settings.write(SettingKeys.doneStabilityDays, 1);

      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await stateOf(uid))!.status, WordStatus.done.name);
    });
  });

  group('BR-FSRS-06 — the cloze switch', () {
    test('two consecutive Good switch the card to cloze', () async {
      await rateRun(<Rating>[Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.plain.name);

      await rateRun(<Rating>[Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.cloze.name);
    });

    test('Good then Easy counts, and Easy then Good', () async {
      await rateRun(<Rating>[Rating.good, Rating.easy]);
      expect((await stateOf(uid))!.cardMode, CardMode.cloze.name);

      await rating.rate(
        ContentFixture.tuer,
        Rating.easy,
        source: ReviewSource.daily,
      );
      now = now.add(const Duration(days: 1));
      await rating.rate(
        ContentFixture.tuer,
        Rating.good,
        source: ReviewSource.daily,
      );

      expect(
        (await stateOf(ContentFixture.tuer))!.cardMode,
        CardMode.cloze.name,
      );
    });

    test('Hard breaks the run', () async {
      await rateRun(<Rating>[Rating.good, Rating.hard]);

      expect((await stateOf(uid))!.cardMode, CardMode.plain.name);
    });

    test('and a Hard behind a Good does not count as a run', () async {
      // The discriminating case for "previous rating was at least Good".
      // `good, hard` exits early on the Hard itself, so the comparison with
      // the previous rating never runs — this is the order that exercises it.
      await rateRun(<Rating>[Rating.hard, Rating.good]);

      expect(
        (await stateOf(uid))!.cardMode,
        CardMode.plain.name,
        reason: 'Hard then Good is not two consecutive Good or Easy',
      );
    });

    test('and a lapse sends it back to plain', () async {
      await rateRun(<Rating>[Rating.good, Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.cloze.name);

      await rateRun(<Rating>[Rating.again]);

      expect(
        (await stateOf(uid))!.cardMode,
        CardMode.plain.name,
        reason: 'a word they just failed is not one to produce from a gap',
      );
    });

    test('it switches on the second, not the third', () async {
      // Off by one here means the learner meets the harder card format a
      // review later than the rule says.
      await rateRun(<Rating>[Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.plain.name);
      await rateRun(<Rating>[Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.cloze.name);
    });

    test('a broken run has to start again', () async {
      await rateRun(<Rating>[Rating.good, Rating.again, Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.plain.name);

      await rateRun(<Rating>[Rating.good]);
      expect((await stateOf(uid))!.cardMode, CardMode.cloze.name);
    });
  });

  group('BR-STATUS-04 — I know it', () {
    test('is a first review rated Easy', () async {
      await rating.markKnown(uid);

      final state = await stateOf(uid);
      expect(state!.stability, closeTo(Fsrs.defaultWeights[3], 0.0001));
      expect(state.status, WordStatus.done.name);
      expect((await logOf(uid)).single.rating, Rating.easy.value);
    });

    test('completes the plan row it came from', () async {
      // The button is for a *new word*, which is a word sitting in today's
      // plan. Leaving the row open puts it in tomorrow's backlog right after
      // the learner said they know it.
      await db.customStatement(
        "INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) "
        "VALUES ('2026-03-02', ?, 'new', 'A1.1')",
        <Object>[uid],
      );

      await rating.markKnown(
        uid,
        planDate: '2026-03-02',
        kind: PlanKind.newWord,
      );

      expect(
        (await db.select(db.planItems).getSingle()).completedAt,
        isNotNull,
      );
    });

    test('and is logged as known, not as daily study', () async {
      // The stats have to tell a word the learner claimed from one they sat
      // down and studied.
      await rating.markKnown(uid);

      expect((await logOf(uid)).single.source, 'known');
    });
  });

  group('the plan row', () {
    setUp(() async {
      await db.customStatement(
        "INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) "
        "VALUES ('2026-03-02', ?, 'new', 'A1.1')",
        <Object>[uid],
      );
    });

    Future<PlanItem> planRow() => (db.select(db.planItems)).getSingle();

    test('is completed when the rating names it', () async {
      await rating.rate(
        uid,
        Rating.good,
        source: ReviewSource.daily,
        planDate: '2026-03-02',
        kind: PlanKind.newWord,
      );

      expect((await planRow()).completedAt, isNotNull);
    });

    test('and is left alone when it does not', () async {
      // A rating from Search or a quiz is not the learner doing today's plan.
      await rating.rate(uid, Rating.good, source: ReviewSource.search);

      expect((await planRow()).completedAt, isNull);
    });

    test("the day's totals go up", () async {
      await rating.rate(
        uid,
        Rating.good,
        source: ReviewSource.daily,
        planDate: '2026-03-02',
        kind: PlanKind.newWord,
        seconds: 12,
      );

      final stats = await (db.select(
        db.dailyStats,
      )..where((t) => t.day.equals('2026-03-02'))).getSingle();
      expect(stats.newDone, 1);
      expect(stats.reviewsDone, 0);
      expect(stats.seconds, 12);
    });
  });

  group('undo', () {
    test('puts a first rating back to no row at all', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);
      expect(await stateOf(uid), isNotNull);

      expect(await rating.undo(), uid);

      expect(
        await stateOf(uid),
        isNull,
        reason: 'a word rated once has no state to go back to',
      );
      expect(await logOf(uid), isEmpty);
    });

    test('restores the exact previous scheduling', () async {
      await rateRun(<Rating>[Rating.good]);
      final before = await stateOf(uid);

      await rating.rate(uid, Rating.again, source: ReviewSource.daily);
      expect((await stateOf(uid))!.lapses, 1);

      await rating.undo();

      final after = await stateOf(uid);
      expect(after!.stability, before!.stability);
      expect(after.difficulty, before.difficulty);
      expect(after.due, before.due);
      expect(after.reps, before.reps);
      expect(after.lapses, before.lapses);
      expect(after.status, before.status);
      expect(after.cardMode, before.cardMode);
      expect(after.lastReview, before.lastReview);
    });

    test('and deletes only its own log row', () async {
      await rateRun(<Rating>[Rating.good, Rating.good]);
      expect(await logOf(uid), hasLength(2));

      await rating.undo();

      expect(await logOf(uid), hasLength(1));
    });

    test('with nothing to undo it says so rather than throwing', () async {
      expect(await rating.undo(), isNull);
    });
  });

  group('BR-STATUS-03 — suspend and resume', () {
    test('suspending keeps the FSRS state', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);
      final before = await stateOf(uid);

      await rating.suspend(uid);

      final after = await stateOf(uid);
      expect(after!.status, WordStatus.suspended.name);
      expect(after.stability, before!.stability);
      expect(after.due, before.due);
    });

    test('and resuming derives the status rather than restoring it', () async {
      // BR-STATUS-02 again: the status is what the stability says, not what
      // it happened to be before the learner paused it.
      await rating.rate(uid, Rating.easy, source: ReviewSource.daily);
      await rating.suspend(uid);

      await rating.resume(uid);

      expect((await stateOf(uid))!.status, WordStatus.done.name);
    });
  });

  group('the clock', () {
    test('a later review counts the days that passed', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);
      now = now.add(const Duration(days: 9));

      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      final log = await logOf(uid);
      expect(log.last.elapsedDays, 9);
    });

    test('#327 an evening review and the next morning count one day', () async {
      now = DateTime(2026, 3, 2, 22, 30);
      await rating.rate(uid, Rating.again, source: ReviewSource.daily);
      now = DateTime(2026, 3, 3, 8);

      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await logOf(uid)).last.elapsedDays, 1);
      expect(
        (await stateOf(uid))!.due,
        isNot('2026-03-04'),
        reason: 'Good grows the card past one day',
      );
    });

    test('and a clock that moved backwards does not go negative', () async {
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);
      now = now.subtract(const Duration(days: 5));

      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await logOf(uid)).last.elapsedDays, 0);
    });

    test('the day it lands on is the local day, not the UTC one', () async {
      // `daily_stats.day` and `word_state.due` are local dates. The instant
      // has to be one where the two calendars disagree, or the assertion
      // passes under `toUtc()` as well — which is exactly what let a planted
      // `toUtc()` survive the first time.
      //
      // Which instant that is depends on the machine's offset, so it is
      // derived rather than hardcoded: just after local midnight east of
      // Greenwich, just before it to the west.
      final offset = DateTime(2026, 3, 3).timeZoneOffset;
      if (offset == Duration.zero) {
        markTestSkipped('the local zone is UTC, so the two never disagree');
        return;
      }

      now = offset.isNegative
          ? DateTime(2026, 3, 3, 23, 30)
          : DateTime(2026, 3, 3, 0, 30);
      expect(
        now.toUtc().day,
        isNot(now.day),
        reason: 'the fixture stopped telling the two calendars apart',
      );

      await rating.rate(uid, Rating.good, source: ReviewSource.daily);

      expect((await stateOf(uid))!.introducedOn, '2026-03-03');
    });
  });
}
