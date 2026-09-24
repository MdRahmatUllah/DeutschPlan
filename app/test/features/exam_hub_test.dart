@TestOn('vm')
library;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// L10's data, against a real database — #127.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SettingsRepository settings;
  late ExamRepository exams;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.memory();
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

  test('BR-EXAM-04 and FR-L10-04: the pass mark and listening, from '
      'settings, as they change', () async {
    expect((await hub()).passPercent, 60);
    expect((await hub()).listening, isTrue);

    await settings.write(SettingKeys.examPassPercent, 70);
    await settings.write(SettingKeys.listeningQuestions, false);
    await pumpEventQueue();

    expect((await hub()).passPercent, 70);
    expect((await hub()).listening, isFalse);
  });

  test('an attempt begun elsewhere moves the hub without asking', () async {
    expect((await hub()).resume, isEmpty);

    final id = await sit(3);
    await pumpEventQueue();

    expect((await hub()).resume, <int, int>{3: id});
  });
}
