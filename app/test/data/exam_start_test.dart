@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/learn/exam_intro_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// FR-L10-03's *Begin exam*, over the real course — #129.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ExamRepository exams;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(File('assets/db/content.db'))}' AS c",
    );
    exams = ExamRepository(db);
  });

  tearDown(() => db.close());

  Future<int> start(int seed, {bool listening = true}) => exams.start(
    step: 'A2.1',
    seed: seed,
    listening: listening,
    bangla: false,
    startedAt: '2026-09-2${seed}T08:00:00Z',
  );

  Future<List<ExamAnswer>> rows(int id) => exams.answersFor(id).get();
  String key(String ref) => ref.split('#').first;

  test('FR-L10-03 a first sitting draws the paper and pre-inserts every '
      'row', () async {
    final id = await start(1);

    final paper = await rows(id);
    expect(paper, hasLength(42));
    expect(paper.map((r) => r.ord), List<int>.generate(42, (i) => i + 1));
    expect(await exams.nextQuestion(id), 1);
  });

  test(
    'BR-EXAM-02 a retake is the same mock, whatever changed since',
    () async {
      final first = await rows(await start(1));
      // A word the paper never asked is suspended in between: a paper drawn
      // again would come out different.
      final asked = <String>{for (final r in first) key(r.itemRef!)};
      final unasked = (await exams.pool('A2.1')).words
          .map((w) => w.word.uid)
          .firstWhere((uid) => !asked.contains(uid));
      await db
          .into(db.wordState)
          .insert(
            WordStateCompanion.insert(
              wordUid: unasked,
              status: const Value('suspended'),
            ),
          );
      final again = await rows(await start(1));

      expect(again.map((r) => r.prompt), first.map((r) => r.prompt));
      expect(again.map((r) => r.itemRef), first.map((r) => r.itemRef));
    },
  );

  test('FR-L10-04 a retake after listening went off leaves it out', () async {
    await start(1);
    final again = await rows(await start(1, listening: false));

    expect(again.where((r) => r.section == 'listening'), isEmpty);
    expect(again, hasLength(42));
  });

  test('BR-EXAM-02 a new mock shares nothing with one already sat', () async {
    final one = await rows(await start(1));
    final two = await rows(await start(2, listening: false));

    expect(
      two
          .map((r) => key(r.itemRef!))
          .toSet()
          .intersection(one.map((r) => key(r.itemRef!)).toSet()),
      isEmpty,
    );
  });

  test('Begin exam keeps the timer for L12, and a second tap waits', () async {
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 21, 8)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(examStartProvider, (_, _) {});
    final start = container.read(examStartProvider.notifier);

    final first = start.begin('A2.1', 1, timer: false);
    final second = await start.begin('A2.1', 1, timer: false);
    final id = await first;

    expect(second, isNull);
    expect(id, isNotNull);
    expect(settings.read(SettingKeys.examTimer), isFalse);
    expect(
      (await (db.select(
        db.examAttempts,
      )..where((t) => t.id.equals(id!))).getSingle()).startedAt,
      '2026-09-21T08:00:00.000Z',
    );
    expect(container.read(examStartProvider), isFalse);
  });

  test("Begin exam asks in the learner's meaning language", () async {
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    await settings.write(SettingKeys.meaningLanguage, MeaningLanguage.bangla);
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    container.listen(examStartProvider, (_, _) {});

    final id = await container
        .read(examStartProvider.notifier)
        .begin('A2.1', 1, timer: true);

    final vocabulary = (await rows(id!))
        .where((r) => r.section == 'vocabulary');
    // Bengali script in what Vocabulary expects.
    expect(
      vocabulary.where((r) => RegExp(r'[ঀ-৿]').hasMatch(r.expected!)),
      isNotEmpty,
    );
  });
}
