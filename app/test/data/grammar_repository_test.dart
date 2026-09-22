@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show WordStatus;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// `GrammarRepository`. BR-FSRS-05 gives grammar the same FSRS fields as
/// words, so this mirrors `WordRepository` — including deriving the status
/// rather than caching it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late GrammarRepository grammar;

  const topicUid = 'g1';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_grammar');
    final content = ContentFixture.write('${directory.path}/content.db').file;

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    grammar = GrammarRepository(db, settings);
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

  Future<void> practise({
    int items = 4,
    int correct = 4,
    double stability = 3,
    String due = '2026-03-10',
    String at = '2026-03-04T09:00:00Z',
  }) => grammar.recordPractice(
    uid: topicUid,
    result: PracticeResult(items: items, correct: correct, practisedAt: at),
    stability: stability,
    difficulty: 5,
    due: due,
    lapses: 0,
  );

  /// The cached `grammar_state.status`. Only `suspended` is read back by the
  /// queries, but the column carries a real status and a stale one would
  /// surface the day anything reads it directly.
  Future<String?> storedStatus() async {
    final row = await (db.select(
      db.grammarState,
    )..where((t) => t.grammarUid.equals(topicUid))).getSingleOrNull();
    return row?.status;
  }

  group('the step list', () {
    test('a topic nobody has practised is todo', () async {
      final step = await grammar.watchStep('A1.1').first;
      expect(step, hasLength(1));
      expect(step.single.status, WordStatus.todo);
      expect(step.single.state, isNull);
    });

    test('the tags the item generator reads come with it', () async {
      final step = await grammar.watchStep('A1.1').first;
      expect(step.single.tags, containsAll(<String>['gap-fill', 'word-order']));
    });

    test('it lists in teaching order', () async {
      final step = await grammar.watchStep('A1.1').first;
      expect(step.single.topic.seq, 1);
    });
  });

  group('recording a practice run', () {
    test('logs it and reschedules, together', () async {
      await practise();

      expect(await grammar.watchPractice(topicUid).first, hasLength(1));
      final found = await grammar.find(topicUid);
      expect(found!.state!.due, '2026-03-10');
      expect(found.state!.reps, 1);
    });

    test('reps accumulate across runs', () async {
      await practise(at: '2026-03-04T09:00:00Z');
      await practise(at: '2026-03-05T09:00:00Z');
      expect((await grammar.find(topicUid))!.state!.reps, 2);
    });

    test('the history is newest first', () async {
      await practise(at: '2026-03-04T09:00:00Z', correct: 4);
      await practise(at: '2026-03-05T09:00:00Z', correct: 2);

      final history = await grammar.watchPractice(topicUid).first;
      expect(history.first.practisedAt, '2026-03-05T09:00:00Z');
      expect(history.first.correct, 2);
    });

    test('a suspended topic stays suspended', () async {
      // Finishing a run the learner had already started does not un-suspend
      // the topic they chose to pause.
      await grammar.suspend(topicUid);
      await practise();
      expect((await grammar.find(topicUid))!.status, WordStatus.suspended);
    });
  });

  group('the rating grammar-practice.md specifies', () {
    test('all correct is Good', () {
      expect(
        const PracticeResult(items: 4, correct: 4, practisedAt: 'x').rating,
        3,
      );
    });

    test('one wrong is Hard', () {
      expect(
        const PracticeResult(items: 4, correct: 3, practisedAt: 'x').rating,
        2,
      );
    });

    test('more than one wrong is Again', () {
      expect(
        const PracticeResult(items: 4, correct: 2, practisedAt: 'x').rating,
        1,
      );
      expect(
        const PracticeResult(items: 4, correct: 0, practisedAt: 'x').rating,
        1,
      );
    });
  });

  group('due topics', () {
    test('are what the plan engine asks for', () async {
      await practise(due: '2026-03-06');
      expect(await grammar.watchDue('2026-03-06').first, hasLength(1));
      expect(await grammar.watchDue('2026-03-05').first, isEmpty);
    });

    test('a suspended topic is never due', () async {
      await practise(due: '2026-03-06');
      await grammar.suspend(topicUid);
      expect(await grammar.watchDue('2026-03-31').first, isEmpty);
    });

    test('a topic never practised is not due', () async {
      expect(await grammar.watchDue('2030-01-01').first, isEmpty);
    });
  });

  group('the derived status', () {
    test('follows the threshold the learner sets', () async {
      await practise(stability: 10);
      expect((await grammar.find(topicUid))!.status, WordStatus.done);

      await settings.write(SettingKeys.doneStabilityDays, 30);
      expect((await grammar.find(topicUid))!.status, WordStatus.learning);
    });

    test('a practised topic is never todo', () async {
      await practise(stability: 0.1);
      expect((await grammar.find(topicUid))!.status, WordStatus.learning);
    });
  });

  group('suspending', () {
    test('works on a topic with no state row', () async {
      expect((await grammar.find(topicUid))!.state, isNull);

      await grammar.suspend(topicUid);
      expect((await grammar.find(topicUid))!.status, WordStatus.suspended);
    });

    test('resuming derives rather than remembering', () async {
      // Asserted on the stored column, not on `find`: the CASE derives
      // everything but `suspended`, so a resume that wrote back the old
      // status would read correctly and still leave the cache wrong.
      await practise(stability: 10);
      expect(await storedStatus(), WordStatus.done.wire);

      await grammar.suspend(topicUid);
      await settings.write(SettingKeys.doneStabilityDays, 30);

      await grammar.resume(topicUid);
      expect(await storedStatus(), WordStatus.learning.wire);
      expect((await grammar.find(topicUid))!.status, WordStatus.learning);
    });

    test('resuming an unpractised topic gives todo', () async {
      await grammar.suspend(topicUid);
      await grammar.resume(topicUid);
      expect(await storedStatus(), WordStatus.todo.wire);
      expect((await grammar.find(topicUid))!.status, WordStatus.todo);
    });
  });

  test('the stream re-emits when a run is recorded', () async {
    final seen = <WordStatus>[];
    final subscription = grammar
        .watchTopic(topicUid)
        .listen((topic) => seen.add(topic!.status));
    addTearDown(subscription.cancel);

    await pumpEventQueue();
    expect(seen.last, WordStatus.todo);

    await practise(stability: 10);
    await pumpEventQueue();

    expect(seen.last, WordStatus.done);
  });
}
