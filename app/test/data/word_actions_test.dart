@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/translation_repository.dart';
import 'package:deutschplan/data/repositories/word_actions.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart'
    show ActiveStep, PlanEngine;
import 'package:deutschplan/services/translation/translator.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// W1's actions (#141): `word-detail.md` FR-W1-01…03 and FR-W1-05, each
/// with the undo FR-W1-04 asks for.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const uid = ContentFixture.haus;
  const today = '2026-03-02';

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late WordActions actions;
  late DriftPlanStore store;
  late RatingService rating;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_actions');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    final words = WordRepository(db, settings);
    store = DriftPlanStore(db, settings);
    rating = RatingService(
      db,
      settings,
      PlanRepository(db),
      words,
      () => DateTime(2026, 3, 2, 9),
    );
    actions = WordActions(db, rating, store);
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

  Future<List<PlanItem>> plan() => db.select(db.planItems).get();
  Future<WordStateData?> state() => (db.select(
    db.wordState,
  )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();

  Future<void> planned(
    String date, {
    String? done,
    String kind = 'new',
    bool skipped = false,
  }) => db
      .into(db.planItems)
      .insert(
        PlanItemsCompanion.insert(
          planDate: date,
          wordUid: uid,
          kind: kind,
          sublevelCode: 'A1.1',
          completedAt: Value(done),
          skipped: Value(skipped ? 1 : 0),
        ),
      );

  Future<List<PlanItem>> open() async => <PlanItem>[
    for (final row in await plan())
      if (row.completedAt == null) row,
  ];

  group('FR-W1-01 Add to today', () {
    test("today's plan gains the word as new, in the active step", () async {
      await db
          .into(db.enrollments)
          .insert(
            EnrollmentsCompanion.insert(
              sublevelCode: 'A1.2',
              startedOn: '2026-03-01',
              dailyNew: 10,
              studyDaysMask: 127,
            ),
          );
      final undo = await actions.addToToday(uid, today: today, step: 'A1.1');
      final rows = await plan();
      expect(rows.single.planDate, today);
      expect(rows.single.kind, 'new');
      expect(rows.single.sublevelCode, 'A1.2');

      await undo();
      expect(await plan(), isEmpty);
    });

    test("with no step under way, the word's own", () async {
      await actions.addToToday(uid, today: today, step: 'A1.1');
      expect((await plan()).single.sublevelCode, 'A1.1');
    });

    test('already there: no second row, and Undo leaves it', () async {
      await planned(today);
      final undo = await actions.addToToday(uid, today: today, step: 'A1.1');
      await undo();
      expect(await plan(), hasLength(1));
    });

    test('a backlog word: its one open row moves to today, and back on '
        'Undo', () async {
      await planned('2026-02-27', skipped: true);
      final undo = await actions.addToToday(uid, today: today, step: 'A1.1');
      final moved = (await open()).single;
      expect(moved.planDate, today);
      expect(moved.skipped, 0, reason: 'added to study, so not skipped');

      await undo();
      final back = (await open()).single;
      expect(back.planDate, '2026-02-27');
      expect(back.skipped, 1);
    });
  });

  group('FR-W1-02 Mark known', () {
    test('BR-STATUS-04 a review rated Easy, logged as known', () async {
      await actions.markKnown(uid, today: today);
      final log = await db.select(db.reviewLog).get();
      expect(log.single.rating, 4);
      expect(log.single.source, 'known');
      expect((await state())!.reps, 1);
    });

    test("closes the word's open plan row, or it would still be served "
        'as new', () async {
      await planned('2026-02-28');
      await actions.markKnown(uid, today: today);
      expect((await plan()).single.completedAt, isNotNull);
    });

    test('closes every open row, and Undo reopens them all; a skipped row '
        'stays skipped', () async {
      await planned('2026-02-27');
      await planned(today, kind: 'revise');
      await planned('2026-02-26', skipped: true);
      final undo = await actions.markKnown(uid, today: today);
      expect((await open()).map((row) => row.planDate), <String>['2026-02-26']);

      await undo();
      expect(
        (await open()).map((row) => row.planDate),
        unorderedEquals(<String>['2026-02-27', today, '2026-02-26']),
      );
    });

    test('FR-W1-04 Undo takes the rating back', () async {
      await planned(today);
      final undo = await actions.markKnown(uid, today: today);
      await undo();
      expect(await state(), isNull);
      expect(await db.select(db.reviewLog).get(), isEmpty);
      expect((await plan()).single.completedAt, isNull);
    });
  });

  group('FR-W1-02 BR-STATUS-03 Suspend and Resume', () {
    test('suspend, and Undo resumes', () async {
      await actions.markKnown(uid, today: today);
      final before = await state();
      final undo = await actions.suspend(uid, today: today);
      expect((await state())!.status, 'suspended');
      await undo();
      expect(await state(), before);
    });

    test('FR-W1-04 a word never met: Undo leaves no row, as before', () async {
      final undo = await actions.suspend(uid, today: today);
      await undo();
      expect(await state(), isNull);
    });

    test("#351 #368 a planned word leaves today's open rows and keeps its "
        'backlog; Undo puts back exactly what went', () async {
      await planned(today);
      await planned(today, kind: 'revise', skipped: true);
      await planned('2026-02-27');
      await planned('2026-02-26', skipped: true);
      await planned('2026-02-20', kind: 'revise', done: '2026-02-20T08:00:00Z');
      final before = await plan();
      final undo = await actions.suspend(uid, today: today);
      expect(
        (await plan()).map((row) => row.planDate),
        unorderedEquals(<String>['2026-02-27', '2026-02-26', '2026-02-20']),
        reason: "the backlog as T4 keeps it, and a done row, history",
      );

      await undo();
      expect(await plan(), unorderedEquals(before));
      expect(await state(), isNull);
    });

    test('#368 Suspend and Resume of a backlog word from an earlier step '
        'leave it in T4', () async {
      await db
          .into(db.enrollments)
          .insert(
            EnrollmentsCompanion.insert(
              sublevelCode: 'A1.2',
              startedOn: '2026-03-01',
              dailyNew: 10,
              studyDaysMask: 127,
            ),
          );
      await planned('2026-02-27');
      await actions.suspend(uid, today: today);
      await actions.resume(uid);
      final backlog = await PlanRepository(db).backlog(today);
      expect(backlog.single.wordUid, uid);
      expect(backlog.single.planDate, '2026-02-27');
    });

    test("#368 today's only revision suspended, the reopened day picks no "
        'others (BR-PLAN-08)', () async {
      final engine = PlanEngine(
        store: store,
        reviseCount: 10,
        backlogCatchupDays: 30,
      );
      await store.enroll(
        const ActiveStep(
          sublevelCode: 'A1.1',
          startedOn: today,
          dailyNew: 1,
          studyDaysMask: PlanEngine.allDays,
        ),
      );
      Future<void> due(String word) => db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: word,
              status: const Value('learning'),
              stability: const Value(5),
              due: const Value(today),
              lastReview: const Value('2026-02-25T09:00:00Z'),
            ),
          );
      await due(ContentFixture.strasse);
      expect((await engine.openDay(today)).revise, <String>[
        ContentFixture.strasse,
      ]);

      await actions.suspend(ContentFixture.strasse, today: today);
      await due(ContentFixture.tuer);
      expect((await engine.openDay(today)).revise, isEmpty);
    });

    test('#351 a rating never resumes a suspended word; the schedule still '
        'moves', () async {
      await actions.markKnown(uid, today: today);
      await actions.suspend(uid, today: today);
      final reps = (await state())!.reps;
      await rating.rate(uid, Rating.good, source: ReviewSource.daily);
      expect((await state())!.status, 'suspended');
      expect((await state())!.reps, reps + 1);
    });

    test('resume, and Undo suspends again', () async {
      await actions.suspend(uid, today: today);
      final undo = await actions.resume(uid);
      expect((await state())!.status, isNot('suspended'));
      await undo();
      expect((await state())!.status, 'suspended');
    });
  });

  group('FR-W1-02 Reset word', () {
    setUp(() async {
      await actions.markKnown(uid, today: today);
    });

    test('its state, its open rows from today on and every new row go; done '
        'and earlier revisions and the review log stay', () async {
      await planned('2026-02-20');
      await planned('2026-02-24', kind: 'revise', done: '2026-02-24T08:00:00Z');
      await planned(today, kind: 'revise', done: '2026-03-02T08:00:00Z');
      await planned('2026-02-28', kind: 'revise');
      await planned('2026-03-05', kind: 'revise');
      await actions.reset(uid, today: today);

      expect(await state(), isNull);
      expect(
        (await plan()).map((row) => row.planDate),
        unorderedEquals(<String>['2026-02-24', today, '2026-02-28']),
      );
      expect(await db.select(db.reviewLog).get(), hasLength(1));
    });

    test(
      'the word can be planned again: it is To do, with no new row',
      () async {
        await planned('2026-02-20', done: '2026-02-20T08:00:00Z');
        await actions.reset(uid, today: today);
        expect(await store.unplannedWords('A1.1', limit: 10), contains(uid));
      },
    );

    test('FR-W1-04 Undo puts back exactly what went', () async {
      await planned('2026-03-05');
      final before = await state();
      final undo = await actions.reset(uid, today: today);
      await undo();
      expect(await state(), before);
      expect((await plan()).single.planDate, '2026-03-05');
    });
  });

  group('FR-W1-03 card mode', () {
    test('writes word_state.card_mode, for a word never met too', () async {
      final undo = await actions.setCardMode(uid, CardMode.cloze);
      expect((await state())!.cardMode, 'cloze');
      expect((await state())!.status, 'todo', reason: 'still To do');
      await undo();
      expect(await state(), isNull, reason: 'never met, so no row, as before');
    });

    test('FR-W1-04 Undo puts back the mode a met word had', () async {
      await actions.markKnown(uid, today: today);
      await actions.setCardMode(uid, CardMode.cloze);
      final undo = await actions.setCardMode(uid, CardMode.plain);
      await undo();
      expect((await state())!.cardMode, 'cloze');
    });

    Future<void> rate(List<Rating> ratings) async {
      for (final r in ratings) {
        await rating.rate(uid, r, source: ReviewSource.daily);
      }
    }

    test('BR-FSRS-06 a card put back to plain stays plain through a run of '
        'Good', () async {
      await rate(<Rating>[Rating.good, Rating.good]);
      expect((await state())!.cardMode, 'cloze', reason: 'the rule');
      await actions.setCardMode(uid, CardMode.plain);
      await rate(<Rating>[Rating.good, Rating.good]);
      expect((await state())!.cardMode, 'plain');
    });

    test('BR-FSRS-06 a card chosen as cloze holds through a lapse', () async {
      await actions.setCardMode(uid, CardMode.cloze);
      await rate(<Rating>[Rating.good, Rating.again]);
      expect((await state())!.cardMode, 'cloze');
    });

    test('FR-W1-04 Undo gives the card back to the rule', () async {
      await rate(<Rating>[Rating.good, Rating.good]);
      final before = await state();
      final undo = await actions.setCardMode(uid, CardMode.cloze);
      await undo();
      expect(await state(), before);
      await rate(<Rating>[Rating.again]);
      expect((await state())!.cardMode, 'plain', reason: 'the rule again');
    });

    test('FR-W1-02 a reset gives the card back to the rule', () async {
      await actions.setCardMode(uid, CardMode.plain);
      await actions.reset(uid, today: today);
      await rate(<Rating>[Rating.good, Rating.good]);
      expect((await state())!.cardMode, 'cloze');
    });
  });

  group('FR-W1-05 translations', () {
    test('asked once per model, then read from translation_cache', () async {
      final translator = _Translator('রাস্তা');
      final repository = TranslationRepository(
        db,
        translator,
        () => DateTime.utc(2026, 3, 2),
      );
      expect(
        await repository.translate('Die Straße', from: 'de', to: 'bn'),
        'রাস্তা',
      );
      expect(
        await repository.translate('Die Straße', from: 'de', to: 'bn'),
        'রাস্তা',
      );
      expect(translator.asked, 1);
    });

    test('no model: nothing, and nothing cached', () async {
      final repository = TranslationRepository(
        db,
        const UnavailableTranslator(),
        () => DateTime.utc(2026, 3, 2),
      );
      expect(await repository.translate('Hallo', from: 'de', to: 'bn'), isNull);
      expect(await db.select(db.translationCache).get(), isEmpty);
    });
  });
}

class _Translator implements Translator {
  _Translator(this.answer);

  final String answer;
  int asked = 0;

  @override
  String get model => 'test';

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    asked++;
    return answer;
  }
}
