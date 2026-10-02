import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/domain/documents/matcher.dart';

import '../db/content_fixture.dart' show realContent;

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
    expect(classOf('überweisen'), DocClass.known.name);
    expect(classOf('Taxifahrer'), DocClass.outside.name);

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

    await documents.match(id);
    expect(await documents.added(id), <String>{key});
  });

  test('#1230: a document that is gone has nothing to match', () async {
    expect(await documents.match(404), isNull);
  });
}
