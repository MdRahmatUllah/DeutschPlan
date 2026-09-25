@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show PlanKind, PlanRepository, ReviewSource;
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/quiz_store.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart' hide PlanKind;
import 'package:deutschplan/domain/quiz_builder.dart' show QuizSource;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// Words of one's own in revision and quizzes (#363): `add-word.md`
/// FR-R2-03's *Save and add to revision* and FR-R2-04, over the plan engine,
/// T2's lookup, the rating and the quiz store as they run.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const monday = '2026-03-02';
  const MyWordDraft pfand = (
    article: 'das',
    german: 'Pfand',
    meaning: 'deposit',
    whereSeen: 'Rewe',
    example: 'Ich bekomme das Pfand zurück.',
  );

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late WordRepository words;
  late PlanEngine engine;
  late RatingService rating;
  var now = DateTime(2026, 3, 2, 9);

  setUp(() async {
    now = DateTime(2026, 3, 2, 9);
    directory = Directory.systemTemp.createTempSync('deutschplan_my_words');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    words = WordRepository(db, settings);
    final store = DriftPlanStore(db, settings);
    engine = PlanEngine(store: store, reviseCount: 10, backlogCatchupDays: 30);
    rating = RatingService(db, settings, PlanRepository(db), words, () => now);
    await store.enroll(
      const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 1,
        studyDaysMask: PlanEngine.allDays,
      ),
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

  Future<WordStateData?> state(int id) => (db.select(
    db.wordState,
  )..where((t) => t.wordUid.equals(customUid(id)))).getSingleOrNull();

  Future<List<PlanItem>> rows(int id) => (db.select(
    db.planItems,
  )..where((t) => t.wordUid.equals(customUid(id)))).get();

  Future<int> revise() => words.saveMyWord(pfand, now: now, reviseFrom: monday);

  group('FR-R2-03 Save and add to revision', () {
    test(
      'schedules the word as any word, keyed custom:<id>, due today',
      () async {
        final id = await revise();
        final row = (await state(id))!;
        expect(row.status, 'learning');
        expect(row.introducedOn, monday);
        expect(row.due, monday);
        expect(row.lastReview, isNull, reason: 'not reviewed yet');
        expect(await words.isMyWordInRevision(id), isTrue);
      },
    );

    test('Save alone schedules nothing', () async {
      final id = await words.saveMyWord(pfand, now: now);
      expect(await state(id), isNull);
      expect(await words.isMyWordInRevision(id), isFalse);
    });

    test('with today open, the next Today shows it in Revise, in the step '
        'being studied', () async {
      await engine.openDay(monday);
      final id = await revise();
      final plan = await engine.openDay(monday);
      expect(plan.revise, contains(customUid(id)));
      expect((await rows(id)).single.sublevelCode, 'A1.1');
    });

    test('before today is opened, the day picks it as it is due, and its '
        'other revisions too (BR-PLAN-03)', () async {
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: ContentFixture.strasse,
              status: const Value('learning'),
              stability: const Value(5),
              due: const Value(monday),
              lastReview: const Value('2026-02-25T09:00:00Z'),
            ),
          );
      final id = await revise();
      expect(await rows(id), isEmpty, reason: 'no plan row to open the day');

      final plan = await engine.openDay(monday);
      expect(
        plan.revise,
        unorderedEquals(<String>[ContentFixture.strasse, customUid(id)]),
      );
    });

    test('a word already in revision is left as it is', () async {
      final id = await revise();
      await rating.rate(
        customUid(id),
        Rating.good,
        source: ReviewSource.search,
      );
      final rated = await state(id);
      await words.saveMyWord(pfand, now: now, id: id, reviseFrom: monday);
      expect(await state(id), rated);
    });
  });

  group('FR-R2-03 T2 serves it', () {
    test('as its headword, article and meaning, with its status', () async {
      final id = await revise();
      final found = (await words.find(customUid(id)))!;
      expect(found.word.german, 'Pfand');
      expect(found.word.article, 'das');
      expect(found.word.english, 'deposit');
      expect(found.status, WordStatus.learning);
    });

    test('and rating it schedules it with the same FSRS, then plans it again '
        'when it falls due', () async {
      await engine.openDay(monday);
      final id = await revise();
      await rating.rate(
        customUid(id),
        Rating.good,
        source: ReviewSource.daily,
        planDate: monday,
        kind: PlanKind.revise,
      );
      final row = (await state(id))!;
      expect(row.reps, 1);
      expect(row.lastReview, isNotNull);
      expect(row.due!.compareTo(monday), greaterThan(0));
      expect((await rows(id)).single.completedAt, isNotNull);
      final logged = await (db.select(
        db.reviewLog,
      )..where((t) => t.wordUid.equals(customUid(id)))).get();
      expect(logged, hasLength(1));

      final later = await engine.openDay(row.due!);
      expect(later.revise, contains(customUid(id)));
    });
  });

  group('FR-R2-04 quizzes', () {
    late DriftQuizStore quizzes;
    setUp(() => quizzes = DriftQuizStore(words, settings));

    Future<List<String>> asked(QuizSource source, {String? ref}) async => [
      for (final word in await quizzes.learned(source, ref: ref)) word.uid,
    ];

    test(
      'all learned asks them only with the setting on, and once reviewed',
      () async {
        final id = await revise();
        await settings.write(SettingKeys.quizCustomWords, true);
        expect(
          await asked(QuizSource.allLearned),
          isEmpty,
          reason: 'unreviewed',
        );

        await rating.rate(
          customUid(id),
          Rating.good,
          source: ReviewSource.search,
        );
        final mine = (await quizzes.learned(QuizSource.allLearned)).single;
        expect(mine.uid, customUid(id));
        expect(mine.headword, 'das Pfand');
        expect(mine.english, 'deposit');
        expect(mine.step, 'A1.1', reason: 'the distractors come from it');

        await settings.write(SettingKeys.quizCustomWords, false);
        expect(await asked(QuizSource.allLearned), isEmpty);
      },
    );

    test('never a step, category or compare quiz', () async {
      final id = await revise();
      await rating.rate(
        customUid(id),
        Rating.good,
        source: ReviewSource.search,
      );
      await settings.write(SettingKeys.quizCustomWords, true);
      expect(await asked(QuizSource.stepLearned, ref: 'A1.1'), isEmpty);
      expect(await asked(QuizSource.compareSet, ref: customUid(id)), isEmpty);
    });

    test('and never an exam', () async {
      final id = await revise();
      await rating.rate(
        customUid(id),
        Rating.good,
        source: ReviewSource.search,
      );
      await settings.write(SettingKeys.quizCustomWords, true);
      final pool = await ExamRepository(db).pool('A1.1');
      expect(pool.words.map((w) => w.word.uid), isNot(contains(customUid(id))));
    });
  });

  test('R2 Delete takes its schedule with it and keeps its history', () async {
    await engine.openDay(monday);
    final id = await revise();
    await rating.rate(
      customUid(id),
      Rating.good,
      source: ReviewSource.daily,
      planDate: monday,
      kind: PlanKind.revise,
    );
    final due = (await state(id))!.due!;
    await engine.openDay(due);
    expect(await rows(id), hasLength(2), reason: 'done today, open when due');

    await words.deleteMyWord(id);
    expect(await words.myWord(id), isNull);
    expect(await state(id), isNull);
    expect((await rows(id)).single.planDate, monday, reason: 'the done one');
    final logged = await (db.select(
      db.reviewLog,
    )..where((t) => t.wordUid.equals(customUid(id)))).get();
    expect(logged, hasLength(1));
  });
}
