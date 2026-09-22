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
}
