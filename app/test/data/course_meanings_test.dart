import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/course_meanings.dart';

import '../db/content_fixture.dart';

/// #1081: the meaning languages #1080 ships, read from `content.db`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<ContentDao> open({bool russian = false}) async {
    final content = ContentFixture.write(
      '${tempDir('sg_meanings').path}/content.db',
      russian: russian,
    ).file;
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    return ContentDao(db);
  }

  test('#1081 the course lists its languages in order, each named in '
      'itself', () async {
    final dao = await open(russian: true);
    final languages = await dao.courseLanguageList().get();
    expect(
      [for (final l in languages) (l.code, l.ownName)],
      <(String, String)>[('en', 'English'), ('bn', 'বাংলা'), ('ru', 'Русский')],
    );
  });

  test('#1081 CourseMeanings reads every word in every shipped language, '
      'once', () async {
    final dao = await open(russian: true);
    final meanings = await loadCourseMeanings(dao);
    expect(meanings.meaning(ContentFixture.haus, 'en'), 'house');
    expect(meanings.meaning(ContentFixture.haus, 'bn'), 'বাড়ি');
    expect(meanings.meaning(ContentFixture.haus, 'ru'), 'дом');
    expect(meanings.pronunciation(ContentFixture.strasse, 'ru'), 'штра́сэ');
    expect(meanings.pronunciation(ContentFixture.haus, 'en'), isNull);
    expect(meanings.meaning(ContentFixture.haus, 'pl'), isNull);
    expect(
      meanings.meaning('custom-1', 'en'),
      isNull,
      reason: 'not the course',
    );
    expect(
      await loadCourseMeanings(dao),
      same(meanings),
      reason: 'read once per database',
    );
  });

  test('#1081 a course without Russian has none', () async {
    final dao = await open();
    final meanings = await loadCourseMeanings(dao);
    expect(meanings.meaning(ContentFixture.haus, 'ru'), isNull);
    expect(meanings.meaning(ContentFixture.haus, 'en'), 'house');
  });

  test("#1081 a word's examples in a language, English where it has none "
      '(Bangla, #598)', () async {
    final dao = await open(russian: true);
    Future<List<String?>> lines(String lang) async => [
      for (final e
          in await dao.examplesForWordIn(ContentFixture.haus, lang).get())
        e.translation,
    ];
    expect(await lines('ru'), <String?>['Дом большой.', null]);
    expect(await lines('bn'), <String?>['The house is big.', null]);
    expect(await lines('en'), <String?>['The house is big.', null]);
  });

  test("#1081 a word's tips are its language's speakers' own", () async {
    final dao = await open(russian: true);
    Future<List<String>> tips(String uid, String lang) =>
        dao.tipsForWordIn(uid, lang).get();
    expect(await tips(ContentFixture.strasse, 'bn'), <String>[
      'Straße হলো die।',
    ]);
    expect(await tips(ContentFixture.strasse, 'ru'), isEmpty);
    expect(await tips(ContentFixture.tuer, 'ru'), <String>[
      'die Tür — женский род, как «дверь».',
    ]);
  });

  test('#1081 a grammar topic in each language it ships in', () async {
    final dao = await open(russian: true);
    final rows = await dao.grammarTranslationsFor('g1').get();
    expect(
      {for (final r in rows) r.lang: r.topic},
      <String, String>{'en': 'Wortstellung im Hauptsatz', 'ru': 'Порядок слов'},
    );
  });
}
