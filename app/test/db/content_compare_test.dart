import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/domain/compare_set.dart';
import 'package:deutschplan/domain/quiz_builder.dart' show QuizItem;
import 'package:drift/drift.dart' show DatabaseConnection, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final get = await set('bekommen / erhalten / beziehen / zuteilwerden');
    expect(get.resolved['bekommen']!.step, 'C2.1', reason: 'not A1.1');
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

  test('a uid that is not in the course: null', () async {
    expect(await dao.compareSet('nope'), isNull);
  });
}
