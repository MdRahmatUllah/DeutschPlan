import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/exam_result_service.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
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

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_results');
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
    service = ExamResultService(
      exams,
      settings,
      RatingService(db, settings, PlanRepository(db), words, now),
      words,
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

  test('FR-L13-03 a rubric tick grades the paper again', () async {
    final id = await finished('2026-09-20T10:00:00Z', haus: 'das');
    final before = (await exams.attempt(id))!;

    await service.rubric(id, 3, <bool>[true, true]);

    final after = (await exams.attempt(id))!;
    expect(after.scorePoints, before.scorePoints + 1, reason: '0.5 a tick');
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
}
