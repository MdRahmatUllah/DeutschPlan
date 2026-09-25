import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/domain/compare_set.dart';
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

  /// The set word whose German is [german].
  Future<CompareSet> set(String german) async {
    final row = await db
        .customSelect(
          'SELECT uid FROM words WHERE german = ?',
          variables: [Variable<String>(german)],
        )
        .getSingle();
    return (await dao.compareSet(row.read<String>('uid')))!;
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

  test(
    'FR-W2-01 circa / etwa / rund: only rund is a word of its own',
    () async {
      final circa = await set('circa / etwa / rund');
      expect(circa.resolved.keys, <String>['rund']);
      final members = compareMembers(circa);
      expect(members.map((m) => m.register), <List<String>>[
        <String>['written'],
        <String>['neutral'],
        <String>['written'],
      ]);
      expect(members.last.withText, 'rund + Zahl');
    },
  );

  test(
    'FR-W2-01 no noun for a member in lower case, nothing for an affix',
    () async {
      final prima = await set('prima / super / klasse');
      expect(
        prima.resolved.containsKey('klasse'),
        isFalse,
        reason: 'klasse (great) is not die Klasse (class)',
      );
      final voll = await set('Präfix voll- / durch- / über-');
      expect(voll.resolved, isEmpty, reason: 'durch- is not durch');
    },
  );

  test("FR-W2-01 the set's own step first, then the course's order", () async {
    final get = await set('bekommen / erhalten / beziehen / zuteilwerden');
    expect(get.resolved['bekommen']!.step, 'C2.1', reason: 'not A1.1');
    expect(get.resolved['erhalten']!.step, 'A2.1', reason: 'not B2.1');
  });

  test('a uid that is not in the course: null', () async {
    expect(await dao.compareSet('nope'), isNull);
  });
}
