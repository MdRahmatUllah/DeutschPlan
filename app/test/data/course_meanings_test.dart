import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/grammar_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/settings_repository.dart';

import '../db/content_fixture.dart';
import '../timing.dart';

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

  test("#1077 #1081 the guide is the first language's, else the second's; "
      "Bangla's only while its switch is on", () {
    const word = Word(
      kind: 'vocab',
      uid: 'haus',
      sublevelCode: 'A1.1',
      levelCode: 'A1',
      seq: 1,
      seqInSublevel: 1,
      german: 'Haus',
      english: 'house',
      bangla: 'বাড়ি',
      pronBn: 'হাউস',
      searchKey: 'haus',
      searchKeyAlt: 'haus',
    );
    const course = CourseMeanings(<String, Map<String, WordMeaningText>>{
      'haus': <String, WordMeaningText>{
        'ru': (meaning: 'дом', pronunciation: 'хаус'),
      },
    });
    String? guide(MeaningChoice choice, {bool bangla = true}) =>
        Meanings(choice, course).pronunciation(word, bangla: bangla);

    expect(guide(const MeaningChoice('en', 'bn')), 'হাউস', reason: 'en none');
    expect(guide(const MeaningChoice('en', 'bn'), bangla: false), isNull);
    expect(guide(const MeaningChoice('en')), isNull, reason: 'no Bangla');
    expect(guide(const MeaningChoice('ru', 'bn')), 'хаус');
    expect(guide(const MeaningChoice('bn', 'ru'), bangla: false), 'хаус');
  });

  test('#1119 the whole shipped course loads its meanings once, quickly: '
      'about 10,500 rows today, twice that with two more languages', () async {
    final course = realContent();
    var rows = 0;
    final best = await fastestOf(3, () async {
      // A database of its own each time: the load is kept per database.
      final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(course)}' AS c",
      );
      final meanings = await loadCourseMeanings(ContentDao(db));
      rows = meanings.length;
      await db.close();
    });
    // ignore: avoid_print
    print('#1119 CourseMeanings: $rows words in ${best.inMilliseconds} ms');
    expect(rows, greaterThan(5000));
    expect(best, lessThan(const Duration(milliseconds: 500)));
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

  test("#1081 a word's tips, each its language's speakers' own", () async {
    final dao = await open(russian: true);
    Future<Map<String, String>> tips(String uid) async => {
      for (final t in await dao.wordTipsFor(uid).get()) t.lang: t.tip,
    };
    expect(await tips(ContentFixture.strasse), <String, String>{
      'en': 'Straße is die, not der.',
      'bn': 'Straße হলো die।',
    });
    expect(await tips(ContentFixture.tuer), <String, String>{
      'ru': 'die Tür — женский род, как «дверь».',
    });
  });

  test('#1081 a grammar topic reads in the primary language, English where '
      'it has none', () async {
    final dao = await open(russian: true);
    final settings = SettingsRepository(dao.attachedDatabase);
    await settings.load();
    addTearDown(settings.dispose);
    final grammar = GrammarRepository(dao.attachedDatabase, settings);
    Future<String?> topic() async => (await grammar.find('g1'))?.topic.topic;

    expect(await topic(), 'Wortstellung im Hauptsatz', reason: 'en + bn');
    // An open screen's stream follows the change.
    final watched = <String?>[];
    final watching = grammar
        .watchTopic('g1')
        .listen((t) => watched.add(t?.topic.topic));
    addTearDown(watching.cancel);
    await pumpEventQueue();
    await writeMeaningChoice(settings, const MeaningChoice('ru', 'en'));
    expect(await topic(), 'Порядок слов');
    expect(
      (await grammar.step('A1.1')).single.topic.rule,
      'Глагол стоит вторым.',
    );
    await pumpEventQueue();
    expect(watched.last, 'Порядок слов');
    await writeMeaningChoice(settings, const MeaningChoice('bn'));
    expect(await topic(), 'Wortstellung im Hauptsatz', reason: 'no Bangla');
  });

  test('#1081 the grammar topics in a language', () async {
    final dao = await open(russian: true);
    Future<Map<String, String>> topics(String lang) async => {
      for (final r in await dao.grammarTranslationsIn(lang).get())
        r.grammarUid: r.topic,
    };
    expect(await topics('ru'), <String, String>{'g1': 'Порядок слов'});
    expect(await topics('en'), <String, String>{
      'g1': 'Wortstellung im Hauptsatz',
    });
    expect(await topics('bn'), isEmpty);
  });
}
