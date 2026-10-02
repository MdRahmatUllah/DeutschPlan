import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/domain/documents/matcher.dart';

import '../db/content_fixture.dart' show realContent, tempDir;

const String letter =
    'Der Vermieter schickt die Kündigung. Die Kündigung kommt pünktlich. '
    'Bitte überweisen Sie die Miete. Ich rufe einen Taxifahrer.';

void main() {
  late AppDatabase db;
  late DocumentRepository documents;
  late Map<String, String> uid;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
    );
    documents = DocumentRepository(db, () => DateTime.utc(2026, 10, 2, 9));
    uid = <String, String>{
      for (final row in await ContentDao(db).lemmaWords().get())
        row.german: row.uid,
    };
    // A learner in A2.1 who knows «überweisen», has had «pünktlich» planned,
    // and keeps «Wasserzähler» as a word of their own.
    await db.customStatement(
      "INSERT INTO enrollments (sublevel_code, started_on, daily_new, "
      "study_days_mask) VALUES ('A2.1', '2026-09-01', 10, 127)",
    );
    await db.customStatement(
      "INSERT INTO word_state (word_uid, status) VALUES "
      "('${uid['überweisen']}', 'done')",
    );
    await db.customStatement(
      "INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) "
      "VALUES ('2026-09-02', '${uid['pünktlich']}', 'new', 'A1.1')",
    );
    await db.customStatement(
      "INSERT INTO custom_words (created_at, german, meaning) VALUES "
      "('2026-09-03', 'Wasserzähler', 'water meter')",
    );
    // «Miete», a course word of an earlier step, also kept as their own.
    await db.customStatement(
      "INSERT INTO custom_words (created_at, german, meaning, matched_uid) "
      "VALUES ('2026-09-04', 'Miete', 'rent', '${uid['Miete']}')",
    );
  });

  tearDown(() => db.close());

  test('#1230: the matcher reads every word to learn, and the learner as they '
      'stand', () async {
    final input = await documents.matcherInput();
    expect(input.entries.length, input.course.length);
    expect(input.course, contains(uid['Kündigung']));
    expect(input.learner.activeStepOrder, 3, reason: 'A2.1 is step 3');
    expect(input.learner.level, 'A2');
    expect(input.learner.status[uid['überweisen']], 'done');
    expect(input.learner.everPlanned, contains(uid['pünktlich']));
    expect(input.learner.mine, contains('wasserzaehler'));
    expect(input.learner.mineUids, <String>{uid['Miete']!});
  });

  test('#1230 BR-DOC-03 FR-D2-07: a document\'s words are matched in an '
      'isolate and saved, one row per lemma and sentence', () async {
    final id = await documents.create(
      title: 'Letter',
      source: 'paste',
      body: letter,
    );
    final match = (await documents.match(id))!;
    String classOf(String surface) =>
        match.words.singleWhere((w) => w.surface == surface).docClass.name;
    expect(classOf('Vermieter'), DocClass.probablyKnown.name);
    expect(classOf('pünktlich'), DocClass.newInCourse.name);
    expect(
      classOf('Kündigung'),
      DocClass.newInCourse.name,
      reason: 'A2.1, the active step',
    );
    expect(classOf('überweisen'), DocClass.known.name);
    expect(classOf('Taxifahrer'), DocClass.outside.name);
    final miete = match.words.singleWhere((w) => w.surface == 'Miete');
    expect(miete.mine, isTrue);
    expect(
      miete.docClass,
      DocClass.newInCourse,
      reason: 'mine: never probably known',
    );

    final rows = await db.select(db.documentWords).get();
    final kuendigung = rows.where((r) => r.lemmaKey == uid['Kündigung']);
    expect(kuendigung.map((r) => r.sentence), <String>[
      'Der Vermieter schickt die Kündigung.',
      'Die Kündigung kommt pünktlich.',
    ]);
    expect((await documents.document(id))!.wordCount, match.words.length);
  });

  test('#1230 BR-DOC-04: Add marks the word and keeps its sentence once; a '
      'second run keeps what was added', () async {
    final id = await documents.create(
      title: 'Letter',
      source: 'paste',
      body: letter,
    );
    await documents.match(id);
    final key = uid['Kündigung']!;
    for (var i = 0; i < 2; i++) {
      await documents.recordAdd(
        documentId: id,
        lemmaKey: key,
        wordKey: key,
        sentence: 'Die Kündigung kommt pünktlich.',
      );
    }
    expect(await documents.added(id), <String>{key});
    final contexts = await db.select(db.wordContexts).get();
    expect(contexts, hasLength(1));
    expect(contexts.single.documentId, id);

    // Learnt since: the rerun takes the new class, and keeps the add.
    await db.customStatement(
      "INSERT INTO word_state (word_uid, status) VALUES ('$key', 'learning')",
    );
    await documents.match(id);
    expect(await documents.added(id), <String>{key});
    final rows = await (db.select(
      db.documentWords,
    )..where((w) => w.lemmaKey.equals(key))).get();
    expect(rows.map((r) => r.class$).toSet(), <String>{'known'});
    expect(rows.every((r) => r.added == 1), isTrue);
  });

  test('#1295 FR-D3-01: the list, newest first, counts each added lemma '
      'once, and follows an add', () async {
    final older = await documents.create(
      title: 'Old',
      source: 'pdf',
      body: letter,
    );
    final newer = await documents.create(
      title: 'New',
      source: 'paste',
      body: letter,
    );
    await documents.match(newer);
    final lists = documents.watchAll();
    expect((await lists.first).map((e) => e.document.title), <String>[
      'New',
      'Old',
    ]);
    final key = uid['Kündigung']!;
    // Twice, two sentences: one lemma added.
    for (final sentence in <String>[
      'Der Vermieter schickt die Kündigung.',
      'Die Kündigung kommt pünktlich.',
    ]) {
      await documents.recordAdd(
        documentId: newer,
        lemmaKey: key,
        wordKey: key,
        sentence: sentence,
      );
    }
    final now = await documents.watchAll().first;
    expect(now.first.added, 1);
    expect(now.last.document.id, older);
    expect(now.last.added, 0);
  });

  test('#1295: rename', () async {
    final id = await documents.create(
      title: 'Letter',
      source: 'paste',
      body: letter,
    );
    await documents.rename(id, 'Kündigung');
    expect((await documents.document(id))!.title, 'Kündigung');
  });

  test('#1295 FR-D3-02 BR-DOC-05: delete takes the document, what it found '
      'and its photos; the words and their sentences stay', () async {
    final support = tempDir('sogda_docs');
    final id = await documents.create(
      title: 'Letter',
      source: 'photo',
      body: letter,
    );
    await documents.match(id);
    final key = uid['Kündigung']!;
    await documents.recordAdd(
      documentId: id,
      lemmaKey: key,
      wordKey: key,
      sentence: 'Die Kündigung kommt pünktlich.',
    );
    final photos = Directory('${support.path}/documents/$id')
      ..createSync(recursive: true);
    File('${photos.path}/page-1.jpg')
        .writeAsBytesSync(List<int>.filled(1000, 1));
    expect(await documents.imageBytes(support: support), 1000);

    await documents.delete(id, support: support);
    expect(await documents.document(id), isNull);
    expect(await db.select(db.documentWords).get(), isEmpty);
    final context = (await db.select(db.wordContexts).get()).single;
    expect(context.wordKey, key, reason: 'the sentence stays with its word');
    expect(context.documentId, isNull);
    expect(photos.existsSync(), isFalse);
    expect(await documents.imageBytes(support: support), 0);
  });

  test('#1230: a document that is gone has nothing to match', () async {
    expect(await documents.match(404), isNull);
  });
}
