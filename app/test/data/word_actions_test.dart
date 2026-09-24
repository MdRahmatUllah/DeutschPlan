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
    actions = WordActions(
      db,
      RatingService(
        db,
        settings,
        PlanRepository(db),
        words,
        () => DateTime(2026, 3, 2, 9),
      ),
      DriftPlanStore(db, settings),
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

  Future<List<PlanItem>> plan() => db.select(db.planItems).get();
  Future<WordStateData?> state() => (db.select(
    db.wordState,
  )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();

  Future<void> planned(String date, {String? done}) => db
      .into(db.planItems)
      .insert(
        PlanItemsCompanion.insert(
          planDate: date,
          wordUid: uid,
          kind: 'new',
          sublevelCode: 'A1.1',
          completedAt: Value(done),
        ),
      );

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
      final undo = await actions.suspend(uid);
      expect((await state())!.status, 'suspended');
      await undo();
      expect((await state())!.status, 'todo');
    });

    test('resume, and Undo suspends again', () async {
      await actions.suspend(uid);
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

    test('its state and its plan rows from today on go; done rows, earlier '
        'rows and the review log stay', () async {
      await planned('2026-02-20');
      await planned(today, done: '2026-03-02T08:00:00Z');
      await planned('2026-03-05');
      await actions.reset(uid, today: today);

      expect(await state(), isNull);
      expect(
        (await plan()).map((row) => row.planDate),
        unorderedEquals(<String>['2026-02-20', today]),
      );
      expect(await db.select(db.reviewLog).get(), hasLength(1));
    });

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
      expect((await state())!.cardMode, 'plain');
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
