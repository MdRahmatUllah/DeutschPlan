import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// The bundled course, copied once per test process, for a test that
/// ATTACHes it (#331). `flutter test` runs files in parallel processes, and
/// two of them committing with the same file attached fail now and then
/// with "database is locked". The copy is 8 MB and left in the temp folder.
File realContent() => _realContent ??= () {
  final dir = Directory.systemTemp.createTempSync('deutschplan_course');
  return File('assets/db/content.db').copySync('${dir.path}/content.db');
}();
File? _realContent;

/// Builds a content.db for tests, from the same DDL the pipeline uses.
///
/// The real database is produced by `make content` from four Excel workbooks
/// that are not in this repository, and it is a binary asset. Neither belongs
/// in a Dart test — but the *schema* does, so the DDL is read from
/// `tools/content_schema.sql` and `tools/content_fts.sql` rather than
/// restated. A test against a hand-written CREATE TABLE would pass on a
/// schema the pipeline does not produce.
///
/// The rows are invented and few. What they have to be is *shaped* right:
/// umlauts, a word with no translation on its second example, a Bangla
/// meaning, and two steps.
class ContentFixture {
  ContentFixture._(this.file);

  final File file;

  static final Directory _tools = Directory('../tools');

  /// Writes a content.db at [path] and returns it.
  static ContentFixture write(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    file.parent.createSync(recursive: true);

    final db = sqlite3.open(path);
    try {
      db.execute(File('${_tools.path}/content_schema.sql').readAsStringSync());
      db.execute(File('${_tools.path}/content_fts.sql').readAsStringSync());
      _fill(db);
    } finally {
      db.close();
    }
    return ContentFixture._(file);
  }

  /// Every uid the fixture writes, so a test can name one without a query.
  static const String haus = 'uid-haus';
  static const String tuer = 'uid-tuer';
  static const String strasse = 'uid-strasse';
  static const String version = '202601011200';

  static void _fill(Database db) {
    db.execute('''
      INSERT INTO levels (code, ord, name, exam_target) VALUES
        ('A1', 1, 'Beginner', 'Goethe-Zertifikat A1'),
        ('A2', 2, 'Elementary', 'Goethe-Zertifikat A2');

      INSERT INTO sublevels (code, level_code, ord, word_count, grammar_count)
      VALUES
        ('A1.1', 'A1', 1, 2, 1),
        ('A1.2', 'A1', 2, 1, 0);

      INSERT INTO categories (id, name, description) VALUES
        (1, 'Wohnen', 'Words about the home');
    ''');

    // Umlauts on purpose: the search keys and the FTS tokenizer are what
    // these tests are about.
    _word(db, haus, 'A1.1', 1, 'das', 'Haus', 'house', 'বাড়ি', 'haus', 'haus');
    _word(db, tuer, 'A1.1', 2, 'die', 'Tür', 'door', 'দরজা', 'tuer', 'tur');
    _word(
      db,
      strasse,
      'A1.2',
      1,
      'die',
      'Straße',
      'street',
      'রাস্তা',
      'strasse',
      'strasse',
    );

    db.execute('''
      INSERT INTO word_examples (word_uid, ord, german, english) VALUES
        ('$haus', 1, 'Das Haus ist groß.', 'The house is big.'),
        ('$haus', 2, 'Ich sehe das Haus.', NULL),
        ('$tuer', 1, 'Die Tür ist offen.', 'The door is open.'),
        ('$strasse', 1, 'Die Straße ist lang.', 'The street is long.');

      INSERT INTO grammar_topics
        (uid, sublevel_code, level_code, seq, source_week, topic, rule,
         example_de, example_en, watch_out, tags)
      VALUES
        ('g1', 'A1.1', 'A1', 1, 1, 'Wortstellung im Hauptsatz',
         'The verb is second.', 'Ich gehe heute.', 'I am going today.',
         'Not "Heute ich gehe".', 'gap-fill,pick-the-form,v2,word-order');

      INSERT INTO skill_prompts (level_code, ord, prompt) VALUES
        ('A1', 1, 'Introduce yourself in three sentences.');

      INSERT INTO interference_tips (word_uid, tip_en, tip_bn) VALUES
        ('$strasse', 'Straße is die, not der.', 'Straße হলো die।');

      INSERT INTO meta ("key", value) VALUES
        ('content_version', '$version'),
        ('built_at', '2026-01-01T12:00:00Z'),
        ('sources', '["fixture"]'),
        ('word_count', '3'),
        ('sublevel_week_boundaries', '{"A1.2": 4}');

      INSERT INTO words_fts (uid, german, english, bangla, search_key)
        SELECT uid, german, english, bangla, search_key FROM words;
      INSERT INTO words_trigram (uid, german, english, search_key)
        SELECT uid, german, english, search_key FROM words;
      INSERT INTO examples_fts (word_uid, german, english)
        SELECT word_uid, german, english FROM word_examples;
    ''');
  }

  static void _word(
    Database db,
    String uid,
    String step,
    int seqInStep,
    String article,
    String german,
    String english,
    String bangla,
    String key,
    String alt,
  ) {
    db.execute(
      'INSERT INTO words (uid, sublevel_code, level_code, seq, '
      'seq_in_sublevel, article, german, pos, english, bangla, freq, '
      'category_id, source_week, search_key, search_key_alt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        uid,
        step,
        step.split('.').first,
        seqInStep,
        seqInStep,
        article,
        german,
        'noun',
        english,
        bangla,
        3,
        1,
        1,
        key,
        alt,
      ],
    );
  }
}
