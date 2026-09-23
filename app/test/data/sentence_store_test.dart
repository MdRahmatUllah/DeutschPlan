import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/sentence_store.dart';
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// The sentence picker's drift side — #80.
void main() {
  late Directory directory;
  late AppDatabase db;
  late DriftSentenceStore store;
  const today = '2026-09-21';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_sentences');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    store = DriftSentenceStore(db);
    // Haus and Tür learned; Straße suspended.
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on) VALUES
  ('${ContentFixture.haus}', 'learning', '2026-09-01'),
  ('${ContentFixture.tuer}', 'done', '2026-09-01'),
  ('${ContentFixture.strasse}', 'suspended', '2026-09-01')
''');
  });

  tearDown(() async {
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  Future<Set<(String, int)>> candidates({int gap = 14}) async =>
      <(String, int)>{
        for (final c in await store.candidates(today, gapDays: gap))
          (c.wordUid, c.ord),
      };

  test("candidates are learned words' examples, not suspended ones", () async {
    expect(await candidates(), <(String, int)>{
      (ContentFixture.haus, 1),
      (ContentFixture.haus, 2),
      (ContentFixture.tuer, 1),
    });
  });

  test('a sentence shown within the gap is left out', () async {
    await db.customStatement(
      "INSERT INTO sentence_log (word_uid, ord, shown_on) VALUES "
      "('${ContentFixture.haus}', 1, '2026-09-10')",
    );
    expect(await candidates(), isNot(contains((ContentFixture.haus, 1))));
    expect(await candidates(), contains((ContentFixture.haus, 2)));
  });

  test('and back once the gap has passed', () async {
    // Shown on the 7th: fourteen days before the 21st, so not within them.
    await db.customStatement(
      "INSERT INTO sentence_log (word_uid, ord, shown_on) VALUES "
      "('${ContentFixture.haus}', 1, '2026-09-07')",
    );
    expect(await candidates(), contains((ContentFixture.haus, 1)));
    expect(
      await candidates(gap: 15),
      isNot(contains((ContentFixture.haus, 1))),
    );
  });

  test('the learned keys are the search keys', () async {
    expect(await store.learnedKeys(), <String>{'haus', 'tuer'});
  });

  test('what is recorded reads back in order, with its sentence', () async {
    final picked = <SentenceCandidate>[
      const SentenceCandidate(wordUid: ContentFixture.tuer, ord: 1, german: ''),
      const SentenceCandidate(wordUid: ContentFixture.haus, ord: 2, german: ''),
    ];
    await store.record(today, picked);

    final shown = await store.shownOn(today);
    expect(shown, picked);
    expect(shown.first.german, 'Die Tür ist offen.');
    expect(await store.shownOn('2026-09-22'), isEmpty);
  });

  test("today's rated count follows the ratings", () async {
    await store.record(today, <SentenceCandidate>[
      const SentenceCandidate(wordUid: ContentFixture.tuer, ord: 1, german: ''),
      const SentenceCandidate(wordUid: ContentFixture.haus, ord: 1, german: ''),
    ]);
    final counts = <int>[];
    final subscription = store.watchRated(today).listen(counts.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await db.customUpdate(
      "UPDATE sentence_log SET self_rating = 3 "
      "WHERE word_uid = '${ContentFixture.tuer}'",
      updates: <TableInfo<Table, Object?>>{db.sentenceLog},
    );
    await pumpEventQueue();

    expect(counts, <int>[0, 1]);
  });
}
