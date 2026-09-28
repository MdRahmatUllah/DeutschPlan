@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/grammar_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// #639, BR-STATUS-02: `done` is stability ≥ `done_stability_days`. Dart
/// states it once, in [statusForStability]; drift has no shared SQL
/// fragment, so every query that derives a status states it too. These hold
/// the SQL to the Dart, one stability exactly at the threshold.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('#639 BR-STATUS-02 every SQL statement of the rule is >= for done, '
      '< for learning', () {
    var found = 0;
    for (final file in Directory('lib/data/db').listSync().whereType<File>()) {
      if (!file.path.endsWith('.drift')) continue;
      final text = file.readAsStringSync();
      for (final match in RegExp(r'(\S+)\s+:doneAfter\b').allMatches(text)) {
        found++;
        expect(match[1], anyOf('>=', '<'), reason: '${file.path}: ${match[0]}');
      }
    }
    expect(found, greaterThan(0), reason: 'no query read');
  });

  group('#639 BR-STATUS-02 the SQL and the Dart agree at the threshold', () {
    late Directory directory;
    late AppDatabase db;
    late SettingsRepository settings;
    late WordRepository words;
    late GrammarRepository grammar;

    setUp(() async {
      directory = tempDir('sogda_done_rule');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      words = WordRepository(db, settings);
      grammar = GrammarRepository(db, settings);
    });

    tearDown(() async {
      await settings.dispose();
      await db.close();
    });

    // Haus exactly at the threshold, Tür just under, Straße just over.
    const stabilities = <String, double>{
      ContentFixture.haus: 7,
      ContentFixture.tuer: 6.99,
      ContentFixture.strasse: 7.01,
    };

    test('words: each status, and the counts', () async {
      final days = settings.read(SettingKeys.doneStabilityDays);
      expect(days, 7);
      for (final MapEntry(key: uid, value: stability) in stabilities.entries) {
        await db
            .into(db.wordState)
            .insert(
              WordStateCompanion.insert(
                wordUid: uid,
                status: const Value('learning'),
                stability: Value(stability),
                reps: const Value(1),
              ),
            );
      }
      WordStatus dart(String uid) =>
          statusForStability(stabilities[uid]!, days);
      (int, int) counts(Iterable<String> uids) => (
        uids.where((uid) => dart(uid) == WordStatus.learning).length,
        uids.where((uid) => dart(uid) == WordStatus.done).length,
      );
      const a11 = <String>[ContentFixture.haus, ContentFixture.tuer];

      for (final uid in stabilities.keys) {
        expect((await words.find(uid))!.status, dart(uid), reason: uid);
        expect(
          words.derivedStatus((await words.find(uid))!.state!),
          dart(uid),
          reason: uid,
        );
      }
      for (final word in await words.watchStep('A1.1').first) {
        expect(word.status, dart(word.word.uid), reason: word.word.uid);
      }

      final step = await words.statusCounts('A1.1');
      expect((step.learning, step.done), counts(a11));

      final progress = <String, StepProgress>{
        for (final p in await words.watchStepProgress().first) p.code: p,
      };
      expect((progress['A1.1']!.learning, progress['A1.1']!.done), counts(a11));

      final category = (await words.watchCategoryProgress().first).single;
      expect((category.learning, category.done), counts(stabilities.keys));
    });

    test('grammar: the stored status and the derived one', () async {
      final days = settings.read(SettingKeys.doneStabilityDays);
      for (final stability in stabilities.values) {
        await grammar.recordPractice(
          uid: 'g1',
          result: const PracticeResult(
            items: 4,
            correct: 4,
            practisedAt: '2026-03-04T09:00:00Z',
          ),
          stability: stability,
          difficulty: 5,
          due: '2026-03-10',
          reps: 1,
          lapses: 0,
          today: '2026-03-04',
        );
        final expected = statusForStability(stability, days);
        final found = (await grammar.find('g1'))!;
        expect(found.status, expected, reason: 'SQL at $stability');
        expect(found.state!.status, expected.wire, reason: 'Dart $stability');
      }
    });
  });
}
