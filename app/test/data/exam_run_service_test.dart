import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/exam_run_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// L12's data over a real database (#130).
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ExamRepository exams;
  late ExamRunService service;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    exams = ExamRepository(db);
    service = ExamRunService(
      exams,
      settings,
      () => DateTime.utc(2026, 9, 21, 19),
    );
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  /// An Articles question, a Vocabulary one and a rule recall: 3 points.
  Future<int> sit() => exams.begin(
    sublevelCode: 'A1.1',
    seed: 1,
    startedAt: '2026-09-21T18:40:00Z',
    questions: <ExamQuestion>[
      ExamQuestion.of(
        1,
        const WordQuestion(
          ExamSection.articles,
          'haus',
          prompt: 'Haus',
          expected: 'das',
        ),
      ),
      ExamQuestion.of(
        2,
        const WordQuestion(
          ExamSection.vocabulary,
          'tuer',
          prompt: 'die Tür',
          expected: 'door',
        ),
      ),
      ExamQuestion.of(
        3,
        const GrammarQuestion(
          'g#4',
          RuleRecall(
            question: 'Konjunktiv II',
            options: <String>['polite', 'verb last'],
            answer: 0,
          ),
        ),
      ),
    ],
  );

  Future<ExamAnswer> row(int id, int ord) async =>
      (await exams.answers(id)).singleWhere((a) => a.ord == ord);

  test(
    'FR-L12-01 the paper comes back whole, resuming at the first gap',
    () async {
      final id = await sit();
      await service.answer(id, 1, 'das');
      final paper = (await service.load(id))!;
      expect(
        [for (final q in paper.questions) (q.ord, q.item.section, q.given)],
        [
          (1, ExamSection.articles, 'das'),
          (2, ExamSection.vocabulary, null),
          (3, ExamSection.grammar, null),
        ],
      );
      expect(paper.resumeAt, 1);
      expect(
        (paper.questions[2].item as GrammarQuestion).item,
        isA<RuleRecall>(),
      );
    },
  );

  test('a full paper resumes at the first question', () async {
    final id = await sit();
    for (final (ord, given) in [(1, 'das'), (2, 'door'), (3, '0')]) {
      await service.answer(id, ord, given);
    }
    expect((await service.load(id))!.resumeAt, 0);
  });

  test('an attempt that is not there loads nothing', () async {
    expect(await service.load(99), isNull);
  });

  test('FR-L12-01 an answer and a flag are written in place', () async {
    final id = await sit();
    await service.answer(id, 2, 'door');
    await service.flag(id, 2, flagged: true);
    final written = await row(id, 2);
    expect((written.given, written.flagged), ('door', 1));
    await service.answer(id, 2, null);
    expect((await row(id, 2)).given, isNull, reason: 'cleared is unanswered');
  });

  test('FR-L12-03 run and paused seconds add up apart', () async {
    final id = await sit();
    await service.recordTime(id, running: 10);
    await service.recordTime(id, running: 4, paused: 10);
    final attempt = (await exams.attempt(id))!;
    expect((attempt.durationSec, attempt.pausedSec), (14, 10));
  });

  test('the submit grades as the answers stand, and finishes', () async {
    final id = await sit();
    await service.answer(id, 1, 'das');
    await service.answer(id, 3, '0');
    final score = await service.submit(id);
    expect((score.scorePoints, score.maxPoints), (2.0, 3.0));
    final attempt = (await exams.attempt(id))!;
    expect(
      (attempt.status, attempt.finishedAt, attempt.scorePoints),
      ('finished', '2026-09-21T19:00:00.000Z', 2.0),
    );
  });

  test("the timer follows L11's switch", () async {
    expect(service.timed, isTrue, reason: 'on unless turned off');
    await settings.write(SettingKeys.examTimer, false);
    expect(service.timed, isFalse);
  });
}
