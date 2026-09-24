@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// `WordRepository`: the course joined to the learner's progress.
///
/// BR-STATUS-01…04. The two rules worth most of these tests are that
/// suspended words are out of everything that teaches (03) and that `done` is
/// derived from stability rather than set by hand (02).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late WordRepository words;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_words');
    final content = ContentFixture.write('${directory.path}/content.db').file;

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );

    settings = SettingsRepository(db);
    await settings.load();
    words = WordRepository(db, settings);
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

  /// Writes a state row through drift's API, not with `customStatement`.
  ///
  /// That matters here: drift decides which streams to re-emit from the
  /// tables a *typed* write touches. A raw statement changes the same rows
  /// and tells it nothing, so the stream tests below would pass or fail for
  /// the wrong reason — and so would the app.
  Future<void> state(
    String uid, {
    String status = 'learning',
    double stability = 0,
    int reps = 1,
    String? due,
    String? lastReview = '2026-01-01T00:00:00Z',
  }) => db
      .into(db.wordState)
      .insertOnConflictUpdate(
        WordStateCompanion.insert(
          wordUid: uid,
          status: Value(status),
          stability: Value(stability),
          reps: Value(reps),
          due: Value(due),
          lastReview: Value(lastReview),
        ),
      );

  group('the join', () {
    test('a word nobody has met comes back as todo, not as missing', () async {
      final step = await words.watchStep('A1.1').first;
      expect(step, hasLength(2));
      expect(step.first.state, isNull);
      expect(step.first.status, WordStatus.todo);
    });

    test('word and state arrive together, in one query', () async {
      await state(ContentFixture.haus, status: 'learning', stability: 2);

      final step = await words.watchStep('A1.1').first;
      final haus = step.firstWhere((w) => w.uid == ContentFixture.haus);
      expect(haus.word.german, 'Haus');
      expect(haus.state, isNotNull);
      expect(haus.status, WordStatus.learning);
    });

    test('a step lists in seq_in_sublevel order', () async {
      final step = await words.watchStep('A1.1').first;
      expect(
        <String>[for (final w in step) w.word.german],
        <String>['Haus', 'Tür'],
      );
    });

    test('a category lists by step, then frequency', () async {
      final byCategory = await words.watchCategory(1).first;
      expect(byCategory, isNotEmpty);
      expect(byCategory.first.word.sublevelCode, 'A1.1');
    });
  });

  group(
    'BR-STATUS-03 — suspended words are out of everything that teaches',
    () {
      test('the learnable list drops them', () async {
        await state(ContentFixture.tuer, status: 'suspended');

        expect(await words.watchLearnableStep('A1.1').first, hasLength(1));
        expect(
          await words.watchStep('A1.1').first,
          hasLength(2),
          reason: 'the Words tab still shows them, greyed',
        );
      });

      test('a suspended word is never due', () async {
        await state(
          ContentFixture.tuer,
          status: 'suspended',
          due: '2020-01-01',
        );
        expect(await words.watchDue('2030-01-01').first, isEmpty);
      });

      test('suspending keeps the FSRS state', () async {
        await state(ContentFixture.haus, stability: 12, reps: 5);
        await words.suspend(ContentFixture.haus);

        final found = await words.find(ContentFixture.haus);
        expect(found!.status, WordStatus.suspended);
        expect(found.state!.stability, 12);
        expect(found.state!.reps, 5);
      });
    },
  );

  group('BR-STATUS-02 — done is derived, never set by hand', () {
    test('stability at the threshold is done', () async {
      await state(ContentFixture.haus, stability: 7);
      expect(await words.refreshStatus(ContentFixture.haus), WordStatus.done);
    });

    test('below it is learning', () async {
      await state(ContentFixture.haus, stability: 6.9);
      expect(
        await words.refreshStatus(ContentFixture.haus),
        WordStatus.learning,
      );
    });

    test('a lapse moves a done word back to learning', () async {
      await state(ContentFixture.haus, status: 'done', stability: 10);
      expect(await words.refreshStatus(ContentFixture.haus), WordStatus.done);

      // Rating Again collapses stability.
      await state(ContentFixture.haus, status: 'done', stability: 0.5);
      expect(
        await words.refreshStatus(ContentFixture.haus),
        WordStatus.learning,
      );
    });

    test('the threshold is the learner setting, read every time', () async {
      await state(ContentFixture.haus, stability: 10);
      expect(await words.refreshStatus(ContentFixture.haus), WordStatus.done);

      // They raise the bar. Every word's status has to follow, with no
      // rebuild and no stored flag to migrate.
      await settings.write(SettingKeys.doneStabilityDays, 30);
      expect(
        await words.refreshStatus(ContentFixture.haus),
        WordStatus.learning,
      );
    });

    test(
      'a word with no reviews is todo whatever its stability says',
      () async {
        await state(
          ContentFixture.haus,
          stability: 99,
          reps: 0,
          lastReview: null,
        );
        expect(await words.refreshStatus(ContentFixture.haus), WordStatus.todo);
      },
    );
  });

  group('resuming', () {
    test('derives the status rather than remembering it', () async {
      // Suspended while done, then the threshold moves. Resuming must give
      // the status the stability earns now, not the one it had.
      await state(ContentFixture.haus, status: 'done', stability: 10);
      await words.suspend(ContentFixture.haus);
      await settings.write(SettingKeys.doneStabilityDays, 30);

      await words.resume(ContentFixture.haus);
      expect(
        (await words.find(ContentFixture.haus))!.status,
        WordStatus.learning,
      );
    });

    test('a word that was never reviewed comes back as todo', () async {
      await state(ContentFixture.haus, reps: 0, lastReview: null);
      await words.suspend(ContentFixture.haus);
      await words.resume(ContentFixture.haus);

      expect((await words.find(ContentFixture.haus))!.status, WordStatus.todo);
    });
  });

  group('the counts the step list draws', () {
    test('add up to the step', () async {
      await state(ContentFixture.haus, status: 'learning');
      final counts = await words.watchStatusCounts('A1.1').first;

      expect(counts.total, 2);
      expect(counts.todo, 1);
      expect(counts.learning, 1);
      expect(counts.done, 0);
      expect(counts.suspended, 0);
    });

    test('a word with no state row counts as todo', () async {
      final counts = await words.watchStatusCounts('A1.1').first;
      expect(counts.todo, 2);
    });
  });

  group('the streams', () {
    test('a rating in one place updates the list in another', () async {
      // The acceptance criterion: no manual invalidation. Today, Learn and the
      // streak all read through these, and a rating in the study session has
      // to reach them.
      final seen = <int>[];
      final subscription = words
          .watchLearnableStep('A1.1')
          .listen((rows) => seen.add(rows.length));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(seen.last, 2);

      await state(ContentFixture.tuer, status: 'suspended');
      await pumpEventQueue();

      expect(seen.last, 1, reason: 'the suspension did not reach the stream');
    });

    test('an open one follows a threshold the learner moves', () async {
      // `.first` builds a new stream every time, so it never sees this: the
      // threshold is a query variable, and a stream left open on a screen
      // would answer with the value it was built with.
      await state(ContentFixture.haus, stability: 10);

      final seen = <WordStatus>[];
      final subscription = words
          .watchWord(ContentFixture.haus)
          .listen((word) => seen.add(word!.status));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(seen.last, WordStatus.done);

      await settings.write(SettingKeys.doneStabilityDays, 30);
      await pumpEventQueue();

      expect(seen.last, WordStatus.learning);
    });

    test('the status counts re-emit too', () async {
      final seen = <int>[];
      final subscription = words
          .watchStatusCounts('A1.1')
          .listen((counts) => seen.add(counts.learning));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await state(ContentFixture.haus, status: 'learning');
      await pumpEventQueue();

      expect(seen.last, 1);
    });
  });

  group('what the lists show', () {
    test('the status is derived, so moving the threshold moves them', () async {
      // The claim that matters: `refreshStatus` only runs after a rating, so
      // if the lists read the stored column, lowering the threshold would
      // change nothing until each word happened to come round again.
      await state(ContentFixture.haus, stability: 10);

      final before = await words.watchStep('A1.1').first;
      expect(
        before.firstWhere((w) => w.uid == ContentFixture.haus).status,
        WordStatus.done,
      );

      await settings.write(SettingKeys.doneStabilityDays, 30);
      final after = await words.watchStep('A1.1').first;
      expect(
        after.firstWhere((w) => w.uid == ContentFixture.haus).status,
        WordStatus.learning,
        reason: 'the list read the cached status',
      );
    });

    test('the counts follow the threshold too', () async {
      await state(ContentFixture.haus, stability: 10);
      expect((await words.watchStatusCounts('A1.1').first).done, 1);

      await settings.write(SettingKeys.doneStabilityDays, 30);
      final counts = await words.watchStatusCounts('A1.1').first;
      expect(counts.done, 0);
      expect(counts.learning, 1);
    });

    test(
      'an introduced word is learning even before its first review',
      () async {
        // `introduce` writes the date and leaves reps at 0. Reading that as
        // never-met put the word back to `todo` and the plan offered it as new
        // again.
        await words.introduce(ContentFixture.haus, today: '2026-01-05');

        final step = await words.watchStep('A1.1').first;
        expect(
          step.firstWhere((w) => w.uid == ContentFixture.haus).status,
          WordStatus.learning,
        );
        expect(
          await words.refreshStatus(ContentFixture.haus),
          WordStatus.learning,
          reason: 'a refresh after any rating would have reset it',
        );
      },
    );
  });

  group('suspending a word nobody has met', () {
    test('works, because word-detail offers it on todo words', () async {
      // There is no word_state row at all, so an UPDATE would match nothing:
      // the chip would flip and the next read would say `todo` again.
      expect((await words.find(ContentFixture.haus))!.state, isNull);

      await words.suspend(ContentFixture.haus);

      final found = await words.find(ContentFixture.haus);
      expect(found!.status, WordStatus.suspended);
      expect(await words.watchLearnableStep('A1.1').first, hasLength(1));
    });

    test('and resuming it puts it back to todo', () async {
      await words.suspend(ContentFixture.haus);
      await words.resume(ContentFixture.haus);

      expect((await words.find(ContentFixture.haus))!.status, WordStatus.todo);
      expect(await words.watchLearnableStep('A1.1').first, hasLength(2));
    });
  });

  test('introducing a word is idempotent', () async {
    await words.introduce(ContentFixture.haus, today: '2026-01-05');
    await words.introduce(ContentFixture.haus, today: '2026-02-09');

    final found = await words.find(ContentFixture.haus);
    expect(found!.state!.introducedOn, '2026-01-05');
    expect(found.status, WordStatus.learning);
  });

  group('FR-L1-01 the course, a row per step', () {
    Future<List<StepProgress>> course() => words.watchStepProgress().first;

    test('in course order, every word to do before anything is met', () async {
      final steps = await course();
      expect(steps.map((step) => step.code), <String>['A1.1', 'A1.2']);
      final first = steps.first;
      expect(first.levelCode, 'A1');
      expect(first.words, 2);
      expect((first.todo, first.learning, first.done), (2, 0, 0));
      expect(first.grammar, 1);
      expect(first.grammarLearned, 0);
      expect(first.passed, isFalse);
      expect(first.active, isFalse);
    });

    test(
      'words by derived status, suspended ones counted but not split',
      () async {
        await state(ContentFixture.haus, stability: 30);
        await state(ContentFixture.tuer, stability: 1);
        await state(ContentFixture.strasse, status: 'suspended', stability: 30);
        final [a11, a12] = await course();
        expect((a11.todo, a11.learning, a11.done), (0, 1, 1));
        expect(a12.words, 1);
        expect((a12.todo, a12.learning, a12.done), (0, 0, 0));
      },
    );

    test('BR-STATUS-02 done follows done_stability_days', () async {
      await state(ContentFixture.haus, stability: 10);
      expect((await course()).first.done, 1);
      await settings.write(SettingKeys.doneStabilityDays, 21);
      expect((await course()).first.done, 0);
    });

    test('a topic with a state row but never learned is not learned', () async {
      await db.customStatement(
        "INSERT INTO grammar_state (grammar_uid, status) VALUES ('g1', 'todo')",
      );
      expect((await course()).first.grammarLearned, 0);
    });

    test('grammar learned, a passed mock, and the active step', () async {
      await db.customStatement(
        "INSERT INTO grammar_state (grammar_uid, status) VALUES ('g1', 'learning')",
      );
      await db.customStatement(
        'INSERT INTO exam_attempts (sublevel_code, seed, started_at, status, '
        "passed) VALUES ('A1.1', 1, '2026-01-01', 'finished', 1), "
        "('A1.2', 1, '2026-01-01', 'in_progress', 1), "
        "('A1.2', 2, '2026-01-01', 'finished', 0)",
      );
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask, completed_on) VALUES ('A1.1', '2026-01-01', 7, 127, "
        "'2026-01-10'), ('A1.2', '2026-01-10', 7, 127, NULL)",
      );
      final [a11, a12] = await course();
      expect(a11.grammarLearned, 1);
      expect(a11.passed, isTrue);
      expect(a12.passed, isFalse, reason: 'in progress or failed');
      expect(a11.active, isFalse, reason: 'its enrollment is completed');
      expect(a12.active, isTrue);
    });

    test('FR-L2-01 the enrollment: its dates, its frozen pace, and the first '
        'mock passed', () async {
      await db.customStatement(
        'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
        "study_days_mask, completed_on) VALUES ('A1.1', '2026-01-01', 10, 31, "
        "'2026-02-10')",
      );
      await db.customStatement(
        'INSERT INTO exam_attempts (sublevel_code, seed, started_at, '
        "finished_at, status, passed) VALUES "
        "('A1.1', 3, '2026-02-01', '2026-02-01T10:00', 'finished', 1), "
        "('A1.1', 2, '2026-02-02', '2026-02-02T10:00', 'finished', 1), "
        "('A1.1', 1, '2026-01-20', '2026-01-20T10:00', 'finished', 0)",
      );
      final [a11, a12] = await course();
      expect(a11.startedOn, '2026-01-01');
      expect(a11.completedOn, '2026-02-10');
      expect((a11.dailyNew, a11.studyDaysMask), (10, 31));
      expect(a11.passedSeed, 3, reason: 'the first passed, not the lowest');
      expect(a11.active, isFalse);
      // Never enrolled: the pace a start would freeze, from Settings.
      expect(
        (a12.startedOn, a12.completedOn, a12.passedSeed),
        (null, null, null),
      );
      expect((a12.dailyNew, a12.studyDaysMask), (7, 127));
    });

    test("a step not started follows Settings' pace, live", () async {
      final seen = <int>[];
      final sub = words.watchStepProgress().listen(
        (steps) => seen.add(steps.first.dailyNew),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await settings.write(SettingKeys.dailyNew, 12);
      await pumpEventQueue();
      expect(seen, <int>[7, 12]);
    });

    test('BR-EXAM-01 unlocked against exam_unlock_percent, live', () async {
      await state(ContentFixture.haus, stability: 1);
      // One open stream across the change, as the Learn tab holds it.
      final seen = <bool>[];
      final sub = words.watchStepProgress().listen(
        (steps) => seen.add(steps.first.unlocked),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, <bool>[false], reason: '1 of 2 introduced, under 90 %');
      await settings.write(SettingKeys.examUnlockPercent, 50);
      await pumpEventQueue();
      expect(seen.last, isTrue);
    });

    test('a rating shows on the map without a refresh', () async {
      final seen = <int>[];
      final sub = words.watchStepProgress().listen(
        (steps) => seen.add(steps.first.learning),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await state(ContentFixture.haus, stability: 1);
      await pumpEventQueue();
      expect(seen, <int>[0, 1]);
    });
  });

  group('FR-L5-01 the categories, from one grouped query', () {
    Future<List<CategoryProgress>> categories() =>
        words.watchCategoryProgress().first;

    setUp(() async {
      // Wohnen keeps Haus; Arbeit takes Tür and Straße; Leer has no words.
      await db.customStatement(
        "INSERT INTO c.categories (id, name) VALUES (2, 'Arbeit'), (3, 'Leer')",
      );
      await db.customStatement(
        'UPDATE c.words SET category_id = 2 WHERE uid IN '
        "('${ContentFixture.tuer}', '${ContentFixture.strasse}')",
      );
    });

    test('the biggest first, and a category with no words left out', () async {
      final shown = await categories();
      expect(shown.map((c) => (c.id, c.name, c.words)), <(int, String, int)>[
        (2, 'Arbeit', 2),
        (1, 'Wohnen', 1),
      ]);
    });

    test(
      'words by derived status, suspended ones counted but not split',
      () async {
        await state(ContentFixture.tuer, stability: 30);
        await state(ContentFixture.strasse, status: 'suspended', stability: 30);
        final [arbeit, wohnen] = await categories();
        expect((arbeit.todo, arbeit.learning, arbeit.done), (0, 0, 1));
        expect(arbeit.words, 2);
        expect((wohnen.todo, wohnen.learning, wohnen.done), (1, 0, 0));
      },
    );

    test('BR-STATUS-02 done follows done_stability_days, live', () async {
      await state(ContentFixture.tuer, stability: 10);
      final seen = <(int, int)>[];
      final sub = words.watchCategoryProgress().listen(
        (shown) => seen.add((shown.first.learning, shown.first.done)),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await settings.write(SettingKeys.doneStabilityDays, 21);
      await pumpEventQueue();
      await state(ContentFixture.strasse, stability: 1);
      await pumpEventQueue();
      expect(seen, <(int, int)>[(0, 1), (1, 0), (2, 0)]);
    });
  });

  test('BR-EXAM-01 unlocked once introduced reaches the percent', () {
    bool unlocks(int introduced, int todo) =>
        StepProgress.unlocks(todo: todo, introduced: introduced, percent: 90);
    expect(unlocks(90, 10), isTrue);
    expect(unlocks(89, 11), isFalse);
    expect(unlocks(0, 0), isFalse, reason: 'an empty step');
  });
}
