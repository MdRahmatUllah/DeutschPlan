@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/quiz_store.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// `DriftQuizStore`: the quiz builder's view of the course (#81).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late DriftQuizStore store;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_quiz');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    store = DriftQuizStore(WordRepository(db, settings));
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

  Future<void> state(String uid, String status, {double stability = 3}) => db
      .into(db.wordState)
      .insertOnConflictUpdate(
        WordStateCompanion.insert(
          wordUid: uid,
          status: Value(status),
          stability: Value(stability),
          reps: const Value(2),
          lastReview: const Value('2026-09-10T21:30:00Z'),
        ),
      );

  Set<String> uids(List<QuizWord> words) => {for (final w in words) w.uid};

  test('nothing learned, nothing to quiz', () async {
    expect(await store.learned(QuizSource.allLearned), isEmpty);
  });

  group('BR-QUIZ-01 the sources, over learned words only', () {
    setUp(() async {
      await state(ContentFixture.haus, 'learning');
      await state(ContentFixture.tuer, 'suspended'); // BR-STATUS-03
      await state(ContentFixture.strasse, 'done', stability: 30);
    });

    test('all learned: learning and done, never suspended', () async {
      expect(uids(await store.learned(QuizSource.allLearned)), {
        ContentFixture.haus,
        ContentFixture.strasse,
      });
    });

    test("a step's learned words", () async {
      expect(uids(await store.learned(QuizSource.stepLearned, ref: 'A1.1')), {
        ContentFixture.haus,
      });
      expect(await store.learned(QuizSource.stepLearned), isEmpty);
    });

    test("a category's learned words", () async {
      expect(uids(await store.learned(QuizSource.category, ref: '1')), {
        ContentFixture.haus,
        ContentFixture.strasse,
      });
      expect(await store.learned(QuizSource.category, ref: '2'), isEmpty);
    });

    test(
      'a compare set: the uids listed, still only the learned ones',
      () async {
        final set = '${ContentFixture.haus}, ${ContentFixture.tuer}';
        expect(uids(await store.learned(QuizSource.compareSet, ref: set)), {
          ContentFixture.haus,
        });
      },
    );

    test('a word carries what the builder asks and ranks on', () async {
      final haus = (await store.learned(QuizSource.allLearned))
          .firstWhere((w) => w.uid == ContentFixture.haus);
      expect(
        (haus.german, haus.article, haus.pos, haus.english, haus.step),
        ('Haus', 'das', 'noun', 'house', 'A1.1'),
      );
      expect(haus.bangla, isNotEmpty);
      expect(haus.stability, 3);
      expect(
        haus.lastReview,
        '2026-09-10',
        reason: 'the instant, cut to its day',
      );
    });
  });

  test("a step's pool is every word of it, whatever its status", () async {
    await state(ContentFixture.tuer, 'suspended');
    final pool = await store.stepWords('A1.1');
    expect(pool.map((w) => w.uid), [ContentFixture.haus, ContentFixture.tuer]);
    expect(await store.stepWords('Z9.9'), isEmpty);
  });

  test('the builder over the store: a quiz of the learned words', () async {
    await state(ContentFixture.haus, 'learning');
    await state(ContentFixture.strasse, 'learning');
    final quiz = await QuizBuilder(store).build(
      direction: QuizDirection.enDe,
      source: QuizSource.allLearned,
      length: 10,
      seed: 3,
      today: '2026-09-21',
    );
    expect(quiz.items.map((i) => i.wordUid).toSet(), {
      ContentFixture.haus,
      ContentFixture.strasse,
    });
    final haus = quiz.items.firstWhere((i) => i.wordUid == ContentFixture.haus);
    expect((haus.prompt, haus.expected), ('house', 'das Haus'));
    // The fixture's whole course is three words: the tiles are the other two.
    expect(haus.options.toSet(), {'das Haus', 'die Tür', 'die Straße'});
  });
}
