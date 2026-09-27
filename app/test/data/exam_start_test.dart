@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/learn/exam_intro_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// FR-L10-03's *Begin exam*, over the real course — #129.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ExamRepository exams;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
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

  test('FR-L10-03 Begin exam keeps the timer for L12, and a second tap '
      'waits', () async {
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

  test('#671 Begin exam over an unfinished attempt deletes its '
      'recording', () async {
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    final models = ModelRepository(settings, support: tempDir('sg_rec'));
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        modelRepositoryProvider.overrideWithValue(models),
      ],
    );
    addTearDown(container.dispose);
    container.listen(examStartProvider, (_, _) {});
    Future<File> recorded(int id) async {
      final file = await models.recordingFor(id);
      await file.parent.create(recursive: true);
      return file..writeAsStringSync('aac');
    }

    final replaced = await recorded(await start(1));
    final other = await recorded(await start(2));
    await container
        .read(examStartProvider.notifier)
        .begin('A2.1', 1, timer: true);

    expect(replaced.existsSync(), isFalse, reason: 'begin abandoned it');
    expect(other.existsSync(), isTrue, reason: "another mock's, resumable");
  });

  test("FR-L10-03 Begin exam asks in the learner's meaning language", () async {
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

  test('BR-EXAM-02 a paper drawn again replaces the old one in what later '
      'mocks avoid', () async {
    await start(1);
    final redrawn = await rows(await start(1, listening: false));

    expect((await exams.satRefs('A2.1'))[1], <String>{
      for (final r in redrawn) r.itemRef!,
    });
  });

  group('with settings', () {
    late SettingsRepository settings;
    late ProviderContainer container;

    setUp(() async {
      settings = SettingsRepository(db);
      await settings.load();
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
    });

    test('FR-L10-03 a start that fails leaves the timer as it was', () async {
      container.listen(examStartProvider, (_, _) {});

      // Seed 4 is no mock: the draw refuses it.
      await expectLater(
        container
            .read(examStartProvider.notifier)
            .begin('A2.1', 4, timer: false),
        throwsRangeError,
      );
      expect(settings.read(SettingKeys.examTimer), isTrue);
    });

    test('L11 follows the settings it shows', () async {
      container.listen(examIntroProvider('A2.1', 1), (_, _) {});
      Future<ExamIntro> intro() =>
          container.read(examIntroProvider('A2.1', 1).future);
      expect((await intro()).passPercent, 60);

      await settings.write(SettingKeys.examPassPercent, 70);
      await settings.write(SettingKeys.listeningQuestions, false);
      await settings.write(SettingKeys.examTimerDefault, false);
      await pumpEventQueue();

      final now = await intro();
      expect(now.passPercent, 70);
      expect(now.listening, isFalse);
      expect(now.timer, isFalse);
    });
  });
}
