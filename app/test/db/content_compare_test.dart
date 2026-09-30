import 'package:drift/drift.dart' show DatabaseConnection, Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/quiz_store.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/compare_set.dart';
import 'package:sogda/domain/quiz_builder.dart' show QuizItem;
import 'package:sogda/features/words/compare_screen.dart';

import 'content_fixture.dart';

/// W2's sets over the real course (#142): `ContentDao.compareSet`.
void main() {
  late AppDatabase db;
  late ContentDao dao;

  setUpAll(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(realContent())}' AS c",
    );
    dao = ContentDao(db);
  });
  tearDownAll(() => db.close());

  Future<String> uidOf(String german) async =>
      (await db
              .customSelect(
                'SELECT uid FROM words WHERE german = ?',
                variables: [Variable<String>(german)],
              )
              .getSingle())
          .read<String>('uid');

  /// The set word whose German is [german].
  Future<CompareSet> set(String german) async =>
      (await dao.compareSet(await uidOf(german)))!;

  /// Every set in the course with its members and a quiz of all it asks.
  Future<List<(CompareSet, List<CompareMember>, List<QuizItem>)>>
  everySet() async {
    final rows = await db
        .customSelect("SELECT uid FROM words WHERE german LIKE '% / %'")
        .get();
    return <(CompareSet, List<CompareMember>, List<QuizItem>)>[
      for (final row in rows)
        if (await dao.compareSet(row.read<String>('uid')) case final set?)
          (
            set,
            compareMembers(set),
            compareQuizItems(
              compareMembers(set),
              setUid: set.word.uid,
              seed: 1,
              length: 99,
            ),
          ),
    ];
  }

  test(
    'FR-W2-01 Grund / Ursache / Anlass: every member is a course word',
    () async {
      final grund = await set('Grund / Ursache / Anlass');
      expect(grund.word.examples, isNotEmpty);
      expect(grund.resolved.keys, <String>['Grund', 'Ursache', 'Anlass']);
      // #870: the cloze finds a member by them too, "Gründe".
      expect(grund.resolved['Grund']!.forms, 'Gründe');
      expect(
        grund.resolved.values.map((w) => (w.article, w.german)),
        <(String?, String)>[
          ('der', 'Grund'),
          ('die', 'Ursache'),
          ('der', 'Anlass'),
        ],
      );
      expect(grund.resolved['Ursache']!.examples, isNotEmpty);

      final members = compareMembers(grund);
      expect(members.map((m) => m.meaning), <String>[
        'reason',
        'cause',
        'trigger',
      ]);
      expect(members.map((m) => m.useWhen), <String>[
        'given reason',
        'objective cause',
        'occasion',
      ]);
    },
  );

  test('FR-W2-01 circa / etwa / rund: no member is a word of its own, as '
      '"rund" there is not the adjective "round"', () async {
    final circa = await set('circa / etwa / rund');
    expect(circa.resolved, isEmpty);
    final members = compareMembers(circa);
    expect(members.map((m) => m.register), <List<String>>[
      <String>['written'],
      <String>['neutral'],
      <String>['written'],
    ]);
    expect(members.last.withText, 'rund + Zahl');
    expect(members.last.example?.german, 'Rund 200 Personen nahmen teil.');
  });

  test('FR-W2-01 a member is a word of the set\'s part of speech', () async {
    final eben = await set('eben / halt');
    expect(eben.resolved, isEmpty, reason: 'the particle, not Eben (adv)');
    for (final (set, _, _) in await everySet()) {
      for (final word in set.resolved.values) {
        if (set.word.pos == 'phrase') continue;
        expect(word.pos, set.word.pos, reason: '${word.german} in a set');
      }
    }
  });

  test(
    'FR-W2-01 a member is not a homograph of another part of speech',
    () async {
      final prima = await set('prima / super / klasse');
      expect(
        prima.resolved.containsKey('klasse'),
        isFalse,
        reason: 'klasse (great) is not die Klasse (class)',
      );
    },
  );

  test('FR-W1-06 word formation is no set to compare', () async {
    for (final german in <String>[
      'Präfix voll- / durch- / über-',
      'Adjektive auf -bar / -lich / -sam',
      'erfolgreich — Wortbildung -reich / -voll',
    ]) {
      expect(await dao.compareSet(await uidOf(german)), isNull, reason: german);
    }
    expect(await everySet(), hasLength(60 - 7));
  });

  test("FR-W2-01 the set's own step first, then the course's order", () async {
    // #921 teaches each word in one step, so the rule is shown on twins: A1.1's
    // "bekommen" in the set's step, C2.1, and A2.1's "erhalten" in B2.1.
    await db.customStatement(
      'CREATE TEMP TABLE twin AS SELECT * FROM c.words '
      "WHERE german IN ('bekommen', 'erhalten')",
    );
    await db.customStatement(
      "UPDATE twin SET uid = 'twin-' || german, seq = seq + 100000, "
      "sublevel_code = CASE german WHEN 'bekommen' THEN 'C2.1' ELSE 'B2.1' END",
    );
    await db.customStatement('INSERT INTO c.words SELECT * FROM twin');
    addTearDown(() async {
      await db.customStatement("DELETE FROM c.words WHERE uid LIKE 'twin-%'");
      await db.customStatement('DROP TABLE twin');
    });
    final get = await set('bekommen / erhalten / beziehen / zuteilwerden');
    expect(get.resolved['bekommen']!.uid, 'twin-bekommen', reason: 'not A1.1');
    expect(get.resolved['erhalten']!.step, 'A2.1', reason: 'not B2.1');
  });

  test('FR-W2-03 no item names another member: its name would give the '
      'answer away', () async {
    var items = 0;
    for (final (set, members, quiz) in await everySet()) {
      for (final item in quiz) {
        items++;
        for (final other in members) {
          if (other.headword == item.expected) continue;
          expect(
            other.gapIn(item.prompt),
            isNull,
            reason:
                '${set.word.german}: "${item.prompt}" names ${other.headword}',
          );
        }
      }
    }
    expect(items, greaterThan(50), reason: 'the course still asks plenty');
  });

  test('FR-W2-03 a sentence two members name is skipped or answered right; '
      'its Example is the member it is about', () async {
    final quizzes = <String, List<QuizItem>>{
      for (final (set, _, quiz) in await everySet()) set.word.german: quiz,
    };
    for (final (german, sentence, answer) in <(String, String, String)>[
      ('Liebe / Lieber …', 'Tom, danke für deine Nachricht.', 'Lieber'),
      ('eben erst / gerade erst', 'Bericht ist gerade', 'gerade erst'),
      ('ja wohl / doch wohl', 'Das kann doch', 'doch wohl'),
    ]) {
      for (final item in quizzes[german]!) {
        final original = item.prompt.replaceFirst('___', item.expected);
        if (!original.contains(sentence)) continue;
        expect(item.expected, answer, reason: item.prompt);
      }
    }
    final lieber = compareMembers(await set('Liebe / Lieber …')).last;
    expect(lieber.example?.german, 'Lieber Tom, danke für deine Nachricht.');
  });

  test('#1120 in Russian: a word and its sentences in Russian where the '
      'course has them, English where not; English and Bangla as '
      'before', () async {
    final (set, _, _) = (await everySet()).firstWhere(
      (s) =>
          s.$1.resolved.length >= 2 &&
          s.$1.resolved.values.first.examples.isNotEmpty,
    );
    final member = set.resolved.values.first;
    final other = set.resolved.values.last;
    // This test's own rows, over whatever the course ships (#1149 ships
    // Russian, #1161): the set and one member in Russian, and the other
    // member without, so its English still stands in.
    await db.customStatement(
      'INSERT OR REPLACE INTO c.word_meanings (word_uid, lang, meaning) '
      "VALUES ('${set.word.uid}', 'ru', 'набор'), "
      "('${member.uid}', 'ru', 'слово')",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO c.word_example_translations '
      "(word_uid, ord, lang, translation) VALUES ('${member.uid}', 1, 'ru', "
      "'Перевод.')",
    );
    await db.customStatement(
      'DELETE FROM c.word_meanings '
      "WHERE word_uid = '${other.uid}' AND lang = 'ru'",
    );

    final russian = (await dao.compareSet(set.word.uid, lang: 'ru'))!;
    expect(russian.word.english, 'набор');
    final word = russian.resolved.values.firstWhere((w) => w.uid == member.uid);
    expect(word.english, 'слово');
    expect(word.examples.first.english, 'Перевод.');
    expect(
      russian.resolved.values.firstWhere((w) => w.uid == other.uid).english,
      other.english,
      reason: 'no Russian: its English',
    );
    for (final lang in <String>['en', 'bn']) {
      final same = (await dao.compareSet(set.word.uid, lang: lang))!;
      expect(same.word.english, set.word.english, reason: lang);
      expect(
        same.resolved.values.first.examples.first.english,
        member.examples.first.english,
        reason: lang,
      );
    }

    // W2 and its quiz read it in the learner's first language.
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    await writeMeaningChoice(settings, const MeaningChoice('ru', 'en'));
    final store = DriftQuizStore(WordRepository(db, settings), settings, dao);
    expect((await store.compareSet(set.word.uid))!.word.english, 'набор');
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    final watching = container.listen(
      compareViewProvider(set.word.uid),
      (_, _) {},
    );
    addTearDown(watching.close);
    final view = (await container.read(
      compareViewProvider(set.word.uid).future,
    ))!;
    expect(
      view.members.firstWhere((m) => m.uid == member.uid).meaning,
      'слово',
    );

    // An open W2 follows a switch in M3, as W1 does.
    await writeMeaningChoice(settings, const MeaningChoice('en'));
    await pumpEventQueue();
    final english = (await container.read(
      compareViewProvider(set.word.uid).future,
    ))!;
    expect(
      english.members.firstWhere((m) => m.uid == member.uid).meaning,
      isNot('слово'),
    );
  });

  test('a uid that is not in the course: null', () async {
    expect(await dao.compareSet('nope'), isNull);
  });
}
