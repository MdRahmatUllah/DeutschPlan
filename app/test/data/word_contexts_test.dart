import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';

void main() {
  late AppDatabase db;
  late WordRepository words;

  setUp(() async {
    db = AppDatabase.memory();
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    words = WordRepository(db, settings);
  });

  Future<void> sentence(String key, String text, String at, {int? doc}) =>
      db.customStatement(
        'INSERT INTO word_contexts (word_key, sentence, document_id, '
        'created_at) VALUES (?, ?, ?, ?)',
        <Object?>[key, text, doc, at],
      );

  test("#1232 a word's own sentences, newest first, each with its document's "
      'title; a deleted document leaves the sentence (BR-DOC-05)', () async {
    await db.customStatement(
      "INSERT INTO documents (id, title, source, created_at, body) VALUES "
      "(1, 'Mietvertrag', 'paste', '2026-09-20T08:00:00Z', 'x'), "
      "(2, 'Brief', 'share', '2026-09-21T08:00:00Z', 'y')",
    );
    await sentence(
      'uid-strasse',
      'Die Straße war gesperrt.',
      '2026-09-20T08:00:00Z',
      doc: 1,
    );
    await sentence(
      'uid-strasse',
      'Wir wohnen hier.',
      '2026-09-21T08:00:00Z',
      doc: 2,
    );
    await sentence(
      'uid-haus',
      'Das Haus ist alt.',
      '2026-09-22T08:00:00Z',
      doc: 2,
    );
    await sentence('custom:3', 'Mein Pfand.', '2026-09-22T08:00:00Z');

    expect(await words.contextsFor('uid-strasse'), <OwnSentence>[
      (sentence: 'Wir wohnen hier.', document: 'Brief'),
      (sentence: 'Die Straße war gesperrt.', document: 'Mietvertrag'),
    ]);
    expect(await words.contextsFor('custom:3'), <OwnSentence>[
      (sentence: 'Mein Pfand.', document: null),
    ], reason: 'a word of my own has its sentences too (FR-D2-06)');

    await db.customStatement('PRAGMA foreign_keys = ON');
    await db.customStatement('DELETE FROM documents WHERE id = 2');
    expect(await words.contextsFor('uid-strasse'), <OwnSentence>[
      (sentence: 'Wir wohnen hier.', document: null),
      (sentence: 'Die Straße war gesperrt.', document: 'Mietvertrag'),
    ]);
    expect(await words.contextsFor('uid-none'), isEmpty);
  });
}
