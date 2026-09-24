@TestOn('vm')
library;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// L10's data, against a real database — #127.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SettingsRepository settings;
  late ExamRepository exams;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.memory();
    // The real course: the hub asks the generator whether a paper reuses.
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    exams = ExamRepository(db);
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    container.listen(examHubProvider('A1.2'), (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
  });

  Future<int> sit(int seed, {String? step}) => exams.begin(
    sublevelCode: step ?? 'A1.2',
    seed: seed,
    startedAt: '2026-09-2${seed}T08:00:00Z',
    questions: const <ExamQuestion>[
      ExamQuestion(ord: 1, section: 'articles', prompt: '{}', expected: 'die'),
    ],
  );

  Future<ExamHub> hub() => container.read(examHubProvider('A1.2').future);

  test('FR-L10-02 finished scores, unfinished attempts to resume', () async {
    // Another step's attempt first, and it is not this hub's; it also keeps
    // the attempt ids apart from the seeds.
    await sit(3, step: 'A2.1');
    final one = await sit(1);
    await exams.finish(
      attemptId: one,
      finishedAt: '2026-09-21T08:30:00Z',
      score: const ExamScore(scorePoints: 36, maxPoints: 48, passed: true),
    );
    final two = await sit(2);
    await pumpEventQueue();

    final view = await hub();
    expect(view.seeds.single.seed, 1);
    expect(view.seeds.single.bestPercent, 75);
    expect(view.seeds.single.everPassed, isTrue);
    expect(view.resume, <int, int>{2: two});
  });

  test('BR-EXAM-01, BR-EXAM-04 and FR-L10-04: the unlock threshold, the '
      'pass mark and listening, from settings, as they change', () async {
    container.listen(examRulesProvider, (_, _) {});
    ExamRules rules() => container.read(examRulesProvider);
    expect(rules(), (passPercent: 60, unlockPercent: 90, listening: true));

    await settings.write(SettingKeys.examPassPercent, 70);
    await settings.write(SettingKeys.listeningQuestions, false);
    await settings.write(SettingKeys.examUnlockPercent, 80);
    await pumpEventQueue();

    expect(rules(), (passPercent: 70, unlockPercent: 80, listening: false));
  });

  test('FR-L10-04 listening off draws the papers again; the pass mark '
      'does not', () async {
    var built = 0;
    container.listen(examHubProvider('A1.2'), (_, next) {
      if (next.hasValue) built++;
    });
    await hub();
    final before = built;

    await settings.write(SettingKeys.examPassPercent, 70);
    await pumpEventQueue();
    await hub();
    expect(built, before);

    await settings.write(SettingKeys.listeningQuestions, false);
    await pumpEventQueue();
    await hub();
    expect(built, greaterThan(before));
  });

  test('BR-EXAM-02 eleven topics for twelve slots: Mock 3 shares', () async {
    // A1.2 has 11 grammar topics; B2.1 has 20.
    expect((await hub()).reused, <int>{3});
    container.listen(examHubProvider('B2.1'), (_, _) {});
    expect(
      (await container.read(examHubProvider('B2.1').future)).reused,
      isEmpty,
    );
  });

  test('BR-EXAM-02 two stored papers that share a topic both say so', () async {
    Future<void> store(int seed, String ref) => exams.begin(
      sublevelCode: 'A1.2',
      seed: seed,
      startedAt: '2026-09-2${seed}T08:00:00Z',
      questions: <ExamQuestion>[
        ExamQuestion(ord: 1, section: 'grammar', prompt: '{}', itemRef: ref),
      ],
    );
    await store(1, 'topic#0');
    await store(2, 'topic#1');
    await pumpEventQueue();

    // Mock 3, drawn against them, has eleven fresh topics for four slots.
    expect((await hub()).reused, <int>{1, 2});
  });

  test('an attempt begun elsewhere moves the hub without asking', () async {
    expect((await hub()).resume, isEmpty);

    final id = await sit(3);
    await pumpEventQueue();

    expect((await hub()).resume, <int, int>{3: id});
  });
}
