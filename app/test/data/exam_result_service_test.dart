import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/exam_result_service.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/plan_repository.dart';
import 'package:sogda/data/repositories/rating_service.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// L13's data over a real database (#135): the result, the rubric re-grade
/// and the missed words into revision.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late ExamRepository exams;
  late ExamResultService service;
  late ModelRepository models;

  setUp(() async {
    directory = tempDir('sogda_results');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    exams = ExamRepository(db);
    DateTime now() => DateTime(2026, 9, 21, 19);
    final words = WordRepository(db, settings);
    models = ModelRepository(settings, support: directory);
    service = ExamResultService(
      exams,
      settings,
      RatingService(db, settings, PlanRepository(db), words, now),
      words,
      models,
    );
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  /// Haus's article, Tür's meaning and a Writing task: 1 + 1 + 4 points.
  Future<int> sit(String startedAt) => exams.begin(
    sublevelCode: 'A1.1',
    seed: 1,
    startedAt: startedAt,
    questions: <ExamQuestion>[
      ExamQuestion.of(
        1,
        const WordQuestion(
          ExamSection.articles,
          ContentFixture.haus,
          prompt: 'Haus',
          expected: 'das',
        ),
      ),
      ExamQuestion.of(
        2,
        const WordQuestion(
          ExamSection.vocabulary,
          ContentFixture.tuer,
          prompt: 'die Tür',
          expected: 'door',
        ),
      ),
      ExamQuestion.of(
        3,
        const WritingTask(
          'w',
          level: 'A1',
          category: 'Wohnen',
          targets: <String>['Haus', 'Tür'],
          minWords: 5,
          connectors: <String>[],
        ),
      ),
    ],
  );

  Future<int> finished(String at, {required String haus}) async {
    final id = await sit(at);
    await exams.answer(attemptId: id, ord: 1, given: haus);
    await exams.answer(attemptId: id, ord: 2, given: 'window');
    await exams.answer(
      attemptId: id,
      ord: 3,
      given: 'Das Haus hat eine rote Tür und ein großes Fenster.',
    );
    await exams.grade(id, passPercent: 60, finishedAt: at);
    return id;
  }

  test('FR-L13-01 the result, with the previous finished attempt and its '
      'number', () async {
    final first = await finished('2026-09-19T10:00:00Z', haus: 'der');
    final second = await finished('2026-09-20T10:00:00Z', haus: 'das');
    await sit('2026-09-21T10:00:00Z'); // unfinished: not a comparison

    final result = (await service.result(second))!;
    expect(result.attempt.id, second);
    expect(result.rows.map((r) => r.ord), <int>[1, 2, 3]);
    expect(result.rows.first.points, 1, reason: 'Haus, das');
    expect(result.previous?.attempt.id, first);
    expect(result.previous?.number, 1);
    expect(result.passPercent, 60);

    expect((await service.result(first))!.previous, isNull);
  });

  test('FR-L13-01 the missed words: word items under their point', () async {
    final id = await finished('2026-09-20T10:00:00Z', haus: 'der');
    final result = (await service.result(id))!;
    expect(missedWords(result.rows), <String>[
      ContentFixture.haus,
      ContentFixture.tuer,
    ], reason: 'the Writing task is not a word');
  });

  test('FR-L13-02 only words the plan has introduced go to revision', () async {
    await db
        .into(db.wordState)
        .insert(
          WordStateCompanion.insert(
            wordUid: ContentFixture.haus,
            introducedOn: const Value('2026-09-10'),
          ),
        );
    final id = await finished('2026-09-20T10:00:00Z', haus: 'der');
    expect((await service.result(id))!.missed, <String>[ContentFixture.haus]);
  });

  group('FR-L13-02 #642 the missed words go to revision once per attempt', () {
    Future<void> introduce() async {
      for (final uid in <String>[ContentFixture.haus, ContentFixture.tuer]) {
        await db
            .into(db.wordState)
            .insert(
              WordStateCompanion.insert(
                wordUid: uid,
                introducedOn: const Value('2026-09-10'),
              ),
            );
      }
    }

    test('added, they are not offered again on a later visit', () async {
      await introduce();
      final id = await finished('2026-09-20T10:00:00Z', haus: 'der');
      final before = (await service.result(id))!;
      expect(before.missed, <String>[ContentFixture.haus, ContentFixture.tuer]);
      expect(before.added, 0);

      await service.addToRevision(before.missed, today: '2026-09-21');

      final after = (await service.result(id))!;
      expect(after.missed, isEmpty);
      expect(after.added, 2);
    });

    test('a later attempt that misses them offers them again', () async {
      await introduce();
      final first = await finished('2026-09-20T10:00:00Z', haus: 'der');
      await service.addToRevision(
        (await service.result(first))!.missed,
        today: '2026-09-21',
      );
      // Rated at the clock's 2026-09-21 19:00; this one finishes after.
      final later = await finished('2026-09-23T10:00:00Z', haus: 'der');

      final result = (await service.result(later))!;
      expect(result.missed, <String>[ContentFixture.haus, ContentFixture.tuer]);
      expect(result.added, 0);
    });
  });

  test(
    "FR-L13-01 another step's attempt and the finish order, not the id",
    () async {
      final later = await finished('2026-09-20T10:00:00Z', haus: 'das');
      final earlier = await finished('2026-09-18T10:00:00Z', haus: 'der');
      await exams.begin(
        sublevelCode: 'A1.2',
        seed: 1,
        startedAt: '2026-09-19T10:00:00Z',
        questions: <ExamQuestion>[
          ExamQuestion.of(
            1,
            const WordQuestion(
              ExamSection.articles,
              ContentFixture.strasse,
              prompt: 'Straße',
              expected: 'die',
            ),
          ),
        ],
      );
      final result = (await service.result(later))!;
      expect(result.previous?.attempt.id, earlier);
      expect(result.previous?.number, 1);
    },
  );

  test('FR-L12S-04 a recording deleted from L13 zeros Speaking', () async {
    final id = await sit('2026-09-20T10:00:00Z');
    final file = File('${directory.path}/rec.m4a')..writeAsStringSync('x');
    await exams.answer(attemptId: id, ord: 3, given: file.path);
    await service.deleteRecording(id, 3, file.path);
    expect(file.existsSync(), isFalse);
    expect((await service.result(id))!.rows.last.given, isNull);
  });

  test('FR-L12S-04 #891 a delete from L13 whose write fails keeps the '
      'recording', () async {
    final id = await sit('2026-09-20T10:00:00Z');
    final file = File('${directory.path}/rec.m4a')..writeAsStringSync('x');
    await exams.answer(attemptId: id, ord: 3, given: file.path);
    // The disk refuses the answer's write.
    await db.customStatement(
      'CREATE TRIGGER no_write BEFORE UPDATE ON exam_answers '
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );

    await expectLater(
      service.deleteRecording(id, 3, file.path),
      throwsA(anything),
    );
    expect(file.existsSync(), isTrue, reason: 'the answer still names it');
  });

  test("#688 DA-6 FR-L12S-04 L13 reads a Speaking answer as this phone's "
      'file, and as not recorded once the file is gone', () async {
    final id = await exams.begin(
      sublevelCode: 'A1.1',
      seed: 2,
      startedAt: '2026-09-20T10:00:00Z',
      questions: <ExamQuestion>[
        ExamQuestion.of(
          1,
          const SpeakingTask('s', level: 'A1', category: null, seconds: 60),
        ),
      ],
    );
    await exams.answer(
      attemptId: id,
      ord: 1,
      given: ModelRepository.recordingName(id),
    );
    expect(
      (await service.result(id))!.rows.single.given,
      isNull,
      reason: 'no file: the sheet offers no ticks and no delete',
    );

    final file = await models.recordingFor(id);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('aac');
    expect((await service.result(id))!.rows.single.given, file.path);

    await service.deleteRecording(id, 1, file.path);
    expect(file.existsSync(), isFalse);
  });

  test('FR-L13-03 a rubric tick grades the paper again', () async {
    final id = await finished('2026-09-20T10:00:00Z', haus: 'das');
    final before = (await exams.attempt(id))!;

    await service.rubric(id, 3, <bool>[true, true]);

    final after = (await exams.attempt(id))!;
    expect(after.scorePoints, before.scorePoints + 2, reason: '1 a tick');
    expect(after.finishedAt, before.finishedAt, reason: "still the submit's");
    expect(after.status, 'finished');
    final row = (await service.result(id))!.rows.last;
    expect(row.rubric, <bool>[true, true]);
  });

  test('FR-L13-02 the missed words rated Again with source exam, due '
      'tomorrow', () async {
    await service.addToRevision(<String>[
      ContentFixture.haus,
      ContentFixture.tuer,
    ], today: '2026-09-21');

    final log = await db.select(db.reviewLog).get();
    expect(log.map((r) => (r.wordUid, r.rating, r.source)), <Object>[
      (ContentFixture.haus, 1, 'exam'),
      (ContentFixture.tuer, 1, 'exam'),
    ]);
    final states = await db.select(db.wordState).get();
    expect(states.map((s) => s.due).toSet(), <String>{'2026-09-22'});
  });

  test('FR-L13-02 #717 Add missed words to revision that fails half way '
      'saves nothing, so a retry rates no word twice', () async {
    // The second rating's review_log insert fails, as a full disk would.
    await db.customStatement(
      'CREATE TEMP TRIGGER fail_rating BEFORE INSERT ON review_log '
      'WHEN (SELECT count(*) FROM review_log) >= 1 '
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    final uids = <String>[ContentFixture.haus, ContentFixture.tuer];

    await expectLater(
      service.addToRevision(uids, today: '2026-09-21'),
      throwsA(anything),
    );
    expect(await db.select(db.reviewLog).get(), isEmpty);
    expect(await db.select(db.wordState).get(), isEmpty);
    expect(await db.select(db.dailyStats).get(), isEmpty);
    expect(await db.select(db.undoStack).get(), isEmpty, reason: '#871');

    await db.customStatement('DROP TRIGGER fail_rating');
    await service.addToRevision(uids, today: '2026-09-21');
    final log = await db.select(db.reviewLog).get();
    expect([for (final r in log) r.wordUid], uids, reason: 'each once');
  });
}
