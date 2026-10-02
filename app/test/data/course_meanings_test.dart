import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/grammar_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/text_norm.dart' show meaningKey;
import 'package:sogda/features/learn/categories_screen.dart';
import 'package:sogda/features/learn/step_words.dart';
import 'package:sogda/features/study/study_screen.dart';
import 'package:sogda/router/routes.dart';
import 'package:sqlite3/sqlite3.dart';

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

  test('#1081 CourseMeanings reads every word in every shipped language '
      'beyond English and Bangla, once', () async {
    final dao = await open(russian: true);
    final meanings = await loadCourseMeanings(dao);
    // #1096: English's and Bangla's are the word's own columns.
    expect(meanings.meaning(ContentFixture.haus, 'en'), isNull);
    expect(meanings.meaning(ContentFixture.haus, 'bn'), isNull);
    expect(meanings.meaning(ContentFixture.haus, 'ru'), 'дом');
    expect(meanings.pronunciation(ContentFixture.strasse, 'ru'), 'штрАсэ');
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
        'ru': (meaning: 'дом', pronunciation: 'хАус'),
      },
    });
    String? guide(MeaningChoice choice, {bool bangla = true}) =>
        Meanings(choice, course).pronunciation(word, bangla: bangla)?.text;

    expect(guide(const MeaningChoice('en', 'bn')), 'হাউস', reason: 'en none');
    expect(guide(const MeaningChoice('en', 'bn'), bangla: false), isNull);
    expect(guide(const MeaningChoice('en')), isNull, reason: 'no Bangla');
    expect(guide(const MeaningChoice('ru', 'bn')), 'хАус');
    // #1122: the guide says whose it is, so its key is that language's.
    expect(
      Meanings(
        const MeaningChoice('en', 'bn'),
        course,
      ).pronunciation(word, bangla: true)?.lang,
      'bn',
      reason: "the second's guide, where the first has none",
    );
    expect(
      Meanings(
        const MeaningChoice('ru', 'bn'),
        course,
      ).pronunciation(word, bangla: true)?.lang,
      'ru',
    );
    expect(guide(const MeaningChoice('bn', 'ru'), bangla: false), 'хАус');

    // #1150, the owner: with English's guide in the course, an English +
    // Bangla learner keeps Bangla's while its switch is on and reads
    // English's with it off; English alone reads English's.
    const withEnglish = CourseMeanings(<String, Map<String, WordMeaningText>>{
      'haus': <String, WordMeaningText>{
        'en': (meaning: 'house', pronunciation: 'HOWSS'),
      },
    });
    PronGuide? inEnglish(MeaningChoice choice, {bool bangla = true}) =>
        Meanings(choice, withEnglish).pronunciation(word, bangla: bangla);
    expect(inEnglish(const MeaningChoice('en', 'bn')), (
      lang: 'bn',
      text: 'হাউস',
    ));
    expect(inEnglish(const MeaningChoice('en', 'bn'), bangla: false), (
      lang: 'en',
      text: 'HOWSS',
    ));
    expect(inEnglish(const MeaningChoice('en')), (lang: 'en', text: 'HOWSS'));
    expect(inEnglish(const MeaningChoice('bn', 'en')), (
      lang: 'bn',
      text: 'হাউস',
    ));
    expect(inEnglish(const MeaningChoice('bn', 'en'), bangla: false), (
      lang: 'en',
      text: 'HOWSS',
    ), reason: "the second's, where the first shows none");
  });

  test('#1119 the whole course loads its meanings once, quickly, with two '
      'languages beyond English and Bangla: about 10,500 rows', () async {
    // The shipped course, Russian and Polish for every word (#1100); English's
    // rows are its guides, Bangla's none (#1096).
    final course = File('assets/db/content.db')
        .copySync('${tempDir('sogda_course_ru_pl').path}/content.db');
    final raw = sqlite3.open(course.path);
    final uids = [
      for (final row in raw.select('SELECT uid FROM words'))
        row['uid'] as String,
    ];
    raw.close();
    var meanings = CourseMeanings.none;
    final best = await fastestOf(3, () async {
      // A database of its own each time: the load is kept per database.
      final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(course)}' AS c",
      );
      meanings = await loadCourseMeanings(ContentDao(db));
      await db.close();
    });
    // ignore: avoid_print
    print(
      '#1119 CourseMeanings: ${meanings.length} words in '
      '${best.inMilliseconds} ms',
    );
    expect(uids.length, greaterThan(5000));
    expect(
      uids.where((uid) => meanings.meaningsOf(uid).keys.toSet().length != 2),
      isEmpty,
      reason: 'every word in Russian and Polish',
    );
    expect(best, lessThan(const Duration(milliseconds: 500)));
  });

  test("#775 a meaning's comma is Russian's own: «что» finds «что», not "
      'every «…, что»', () async {
    const course = CourseMeanings(<String, Map<String, WordMeaningText>>{
      'indem': <String, WordMeaningText>{
        'ru': (meaning: 'тем, что / благодаря тому, что', pronunciation: null),
      },
      'was': <String, WordMeaningText>{
        'ru': (meaning: 'что', pronunciation: null),
      },
    });
    expect((await course.find('ru', meaningKey('что'))).exact, <String>['was']);
    expect((await course.find('ru', meaningKey('тем, что'))).exact, <String>[
      'indem',
    ]);
  });

  test('#1121 finding a word by its meaning in a language stays fast at '
      'course scale', () async {
    // 5,600 words, as the course has, each with a Russian meaning of two
    // alternatives.
    final texts = <String, Map<String, WordMeaningText>>{
      for (var i = 0; i < 5600; i++)
        'w$i': <String, WordMeaningText>{
          'ru': (meaning: 'слово$i / значение номер $i', pronunciation: null),
        },
    };
    final course = CourseMeanings(texts);
    // #1160: the first search keys on an isolate, and one spawn under
    // `flutter test -j 2` load took over 500 ms. A course of its own each
    // run keys afresh, and the fastest of three is the keying's own time.
    final first = await fastestOf(
      3,
      () => CourseMeanings(texts).find('ru', 'слово42'),
    );
    final again = await fastestOf(5, () => course.find('ru', 'значение'));
    // ignore: avoid_print
    print(
      '#1121 find: first ${first.inMilliseconds} ms, then '
      '${again.inMicroseconds} us',
    );
    expect((await course.find('ru', meaningKey('Слово42'))).exact, <String>[
      'w42',
    ]);
    expect((await course.find('ru', 'значение')).startsWith, hasLength(5600));
    expect(first, lessThan(const Duration(milliseconds: 500)), reason: 'keyed');
    expect(again, lessThan(const Duration(milliseconds: 50)));
  });

  test("#1150 #1082 an English learner's guide is the course's English one; "
      "a Bangla learner's is the word's own, the course unread", () async {
    final dao = await open();
    await dao.attachedDatabase.customStatement(
      'INSERT INTO c.word_meanings (word_uid, lang, meaning, pronunciation) '
      "VALUES ('${ContentFixture.haus}', 'en', 'house', 'HOWSS')",
    );
    await dao.attachedDatabase.customStatement(
      "UPDATE c.words SET pron_bn = 'হাউস' "
      "WHERE uid = '${ContentFixture.haus}'",
    );
    final settings = SettingsRepository(dao.attachedDatabase);
    await settings.load();
    addTearDown(settings.dispose);
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(dao.attachedDatabase),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    final haus = await dao.wordByUid(ContentFixture.haus).getSingle();
    Future<Meanings> meanings(MeaningChoice choice) async {
      await writeMeaningChoice(settings, choice);
      await pumpEventQueue();
      return container.read(meaningsLoadedProvider.future);
    }

    expect(
      (await meanings(const MeaningChoice('en')))
          .pronunciation(haus, bangla: true),
      (lang: 'en', text: 'HOWSS'),
    );
    // The owner (#1150): Bangla's while its switch is on, English's off.
    final both = await meanings(const MeaningChoice('en', 'bn'));
    expect(both.pronunciation(haus, bangla: true), (lang: 'bn', text: 'হাউস'));
    expect(both.pronunciation(haus, bangla: false), (
      lang: 'en',
      text: 'HOWSS',
    ));
    expect(
      (await meanings(const MeaningChoice('bn'))).course,
      same(CourseMeanings.none),
      reason: "Bangla's meaning and guide are the word's own row",
    );
  });

  test('#1128 the category names follow the primary meaning language: '
      "English's are the course's own, and a language without a name keeps "
      'it', () async {
    final dao = await open(russian: true);
    final settings = SettingsRepository(dao.attachedDatabase);
    await settings.load();
    addTearDown(settings.dispose);
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(dao.attachedDatabase),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    Future<String> wohnen() async =>
        (await container.read(categoryNamesProvider.future)).of('Wohnen');
    Future<List<String>> chips() async => <String>[
      for (final c in await container.read(
        stepCategoriesProvider('A1.1').future,
      ))
        c.name,
    ];

    expect(await wohnen(), 'Wohnen', reason: 'English first: no read');
    expect(await chips(), <String>['Wohnen']);
    await writeMeaningChoice(settings, const MeaningChoice('ru', 'en'));
    await pumpEventQueue();
    expect(await wohnen(), 'Жильё');
    expect(await chips(), <String>['Жильё'], reason: "L2's chips");
    final cards = container.listen(categoriesProvider, (_, _) {});
    addTearDown(cards.close);
    expect(
      <String>[
        for (final c in await container.read(categoriesProvider.future)) c.name,
      ],
      <String>['Жильё'],
      reason: "L5's cards and L6's title",
    );
    expect(
      await container.read(
        studyCategoryProvider(
          const SessionArgs(
            blocks: <SessionBlock>[
              SessionBlock(SessionBlockKind.newWords, <String>[
                ContentFixture.haus,
              ]),
            ],
          ),
        ).future,
      ),
      'Жильё',
      reason: "T2's new-words banner",
    );
    expect(
      (await container.read(categoryNamesProvider.future)).of('Reisen'),
      'Reisen',
      reason: 'a category the language has no name for',
    );
    await writeMeaningChoice(settings, const MeaningChoice('bn'));
    await pumpEventQueue();
    expect(await wohnen(), 'Wohnen', reason: 'no Bangla names');
  });

  test('#1081 a course without Russian has none', () async {
    final dao = await open();
    final meanings = await loadCourseMeanings(dao);
    expect(meanings.meaning(ContentFixture.haus, 'ru'), isNull);
    expect(
      meanings.meaning(ContentFixture.haus, 'en'),
      isNull,
      reason: "#1096: English is the word's own row, not the course's table",
    );
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

  test("#154 FR-W1-05 inLang: whether a line is the language's own, not "
      "English's in its place", () async {
    final dao = await open(russian: true);
    Future<List<bool>> own(String lang) async => [
      for (final e
          in await dao.examplesForWordIn(ContentFixture.haus, lang).get())
        e.inLang,
    ];
    expect(await own('ru'), <bool>[true, false]);
    expect(await own('bn'), <bool>[false, false], reason: 'no Bangla lines');
    expect(await own('en'), <bool>[
      false,
      false,
    ], reason: "English is the line's own column, not the table's");
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
    expect(
      await topics('en'),
      isEmpty,
      reason: "#1096: English's are grammar_topics' own",
    );
    expect(await topics('bn'), isEmpty);
  });
}
