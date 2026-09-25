import 'package:deutschplan/domain/answer_check.dart' show Verdict;
import 'package:deutschplan/domain/compare_set.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// W2's sets and their quiz — #142, `docs/04-screens/compare.md`. The sets
/// are content.db's own, trimmed to what each rule reads.
void main() {
  const grund = CompareSet(
    CompareWord(
      uid: 'set-grund',
      german: 'Grund / Ursache / Anlass',
      english: 'reason / cause / trigger',
      step: 'C2.1',
      pos: 'noun',
      register:
          'Anlass = occasion, Ursache = objective cause, Grund = given reason',
      collocations: 'aus diesem Grund; die Ursache ermitteln; der Anlass',
      examples: <CompareExample>[
        (
          german:
              'Der Anlass war eine Beschwerde, die Ursache ein '
              'Strukturproblem, der Grund dafür politisch.',
          english:
              'The trigger was a complaint, the cause a structural problem, '
              'the reason for it political.',
        ),
        (
          german: 'Anlass und Ursache werden oft verwechselt.',
          english: 'Trigger and cause are often confused.',
        ),
      ],
    ),
    <String, CompareWord>{
      'Grund': CompareWord(
        uid: 'uid-grund',
        german: 'Grund',
        english: 'reason',
        step: 'A1.2',
        article: 'der',
        pos: 'noun',
        examples: <CompareExample>[
          (
            german: 'Aus diesem Grund bleibe ich zu Hause.',
            english: "For this reason I'm staying at home.",
          ),
        ],
      ),
      'Ursache': CompareWord(
        uid: 'uid-ursache',
        german: 'Ursache',
        english: 'cause',
        step: 'B2.1',
        article: 'die',
        pos: 'noun',
        collocations: 'die Ursache des Unfalls',
        examples: <CompareExample>[
          (
            german: 'Die Ursache des Feuers ist unklar.',
            english: 'The cause of the fire is unclear.',
          ),
        ],
      ),
      'Anlass': CompareWord(
        uid: 'uid-anlass',
        german: 'Anlass',
        english: 'occasion',
        step: 'B1.1',
        article: 'der',
        pos: 'noun',
        examples: <CompareExample>[
          (
            german: 'Aus Anlass des Jubiläums gab es ein Fest.',
            english: 'There was a party for the anniversary.',
          ),
        ],
      ),
    },
  );

  const circa = CompareSet(
    CompareWord(
      uid: 'set-circa',
      german: 'circa / etwa / rund',
      english: 'approximately (three registers)',
      step: 'B2.1',
      pos: 'adv',
      register: 'ungefähr (spoken), etwa (neutral), circa/rund (written)',
      collocations: 'ca. (written abbreviation); rund + Zahl',
      examples: <CompareExample>[
        (
          german: 'Die Fahrt dauert etwa 40 Minuten.',
          english: 'The journey takes about 40 minutes.',
        ),
        (
          german: 'Rund 200 Personen nahmen teil.',
          english: 'Around 200 people took part.',
        ),
      ],
    ),
    <String, CompareWord>{
      'rund': CompareWord(
        uid: 'uid-rund',
        german: 'rund',
        english: 'round',
        step: 'A1.2',
        pos: 'adj',
        examples: <CompareExample>[
          (german: 'Der Tisch ist rund.', english: 'The table is round.'),
        ],
      ),
    },
  );

  const angst = CompareSet(
    CompareWord(
      uid: 'set-angst',
      german: 'Angst / Furcht / Sorge / Panik',
      english: 'fear (diffuse) / fear (of something specific) / worry / panic',
      step: 'C2.1',
      pos: 'noun',
      register: 'note the different prepositions',
      collocations: 'Angst vor + Dat.; Furcht vor; Sorge um + Akk.',
      examples: <CompareExample>[
        (
          german:
              'Angst ist diffus, Furcht hat ein Objekt, Sorge ist '
              'zukunftsbezogen.',
          english:
              'Angst is diffuse, Furcht has an object, Sorge is '
              'future-oriented.',
        ),
        (
          german: 'Aus Sorge, nicht aus Angst.',
          english: 'Out of concern, not out of fear.',
        ),
      ],
    ),
    <String, CompareWord>{
      'Angst': CompareWord(
        uid: 'uid-angst',
        german: 'Angst',
        english: 'fear',
        step: 'A1.2',
        article: 'die',
        pos: 'noun',
        examples: <CompareExample>[
          (
            german: 'Ich habe Angst vor Hunden.',
            english: "I'm afraid of dogs.",
          ),
        ],
      ),
      'Sorge': CompareWord(
        uid: 'uid-sorge',
        german: 'Sorge',
        english: 'worry / concern',
        step: 'A2.1',
        article: 'die',
        pos: 'noun',
        collocations: 'sich Sorgen machen',
      ),
    },
  );

  group('FR-W2-01 members', () {
    test('FR-W2-01 the headword split on " / ", in order', () {
      expect(compareMemberNames('Grund / Ursache / Anlass'), <String>[
        'Grund',
        'Ursache',
        'Anlass',
      ]);
      expect(compareMembers(angst).map((m) => m.headword), <String>[
        'Angst',
        'Furcht',
        'Sorge',
        'Panik',
      ]);
    });

    test('FR-W2-01 a resolved member takes its word: uid, article, step', () {
      final members = compareMembers(grund);
      expect(members.map((m) => m.uid), <String>[
        'uid-grund',
        'uid-ursache',
        'uid-anlass',
      ]);
      expect(members.map((m) => m.article), <String>['der', 'die', 'der']);
      expect(members.map((m) => m.step), <String>['A1.2', 'B2.1', 'B1.1']);
      expect(members.first.spoken, 'der Grund');
    });

    test('FR-W2-01 an unresolved member has no uid and the set\'s step', () {
      final members = compareMembers(circa);
      expect(members.map((m) => m.uid), <String?>[null, null, 'uid-rund']);
      expect(members.map((m) => m.step), <String>['B2.1', 'B2.1', 'A1.2']);
    });

    test('FR-W2-01 an article the set writes is the article, not the word', () {
      final members = compareMembers(
        const CompareSet(
          CompareWord(
            uid: 's',
            german: 'die Kohle / die Kohlen',
            english: 'dosh / money (slang)',
            step: 'C2.2',
          ),
        ),
      );
      expect(members.map((m) => (m.article, m.headword)), <(String?, String)>[
        ('die', 'Kohle'),
        ('die', 'Kohlen'),
      ]);
    });
  });

  group('FR-W2-02 the cells', () {
    test('FR-W2-02 Meaning: the set\'s English, one part per member', () {
      expect(compareMembers(grund).map((m) => m.meaning), <String>[
        'reason',
        'cause',
        'trigger',
      ]);
      expect(compareMembers(angst).map((m) => m.meaning), <String>[
        'fear (diffuse)',
        'fear (of something specific)',
        'worry',
        'panic',
      ]);
    });

    test('FR-W2-02 Meaning: else the member\'s word\'s; else none', () {
      expect(compareMembers(circa).map((m) => m.meaning), <String?>[
        null,
        null,
        'round',
      ]);
    });

    test('FR-W2-02 Register: the bracketed labels after the member', () {
      expect(compareMembers(circa).map((m) => m.register), <List<String>?>[
        <String>['written'],
        <String>['neutral'],
        <String>['written'],
      ]);
      expect(
        compareMembers(grund).map((m) => m.register),
        everyElement(isNull),
        reason: '"Anlass = occasion" is a note, not a register',
      );
    });

    test('FR-W2-02 Use it when: "member = note" in the register cell', () {
      expect(compareMembers(grund).map((m) => m.useWhen), <String>[
        'given reason',
        'objective cause',
        'occasion',
      ]);
      expect(compareMembers(circa).map((m) => m.useWhen), everyElement(isNull));
    });

    test('FR-W2-02 With: the collocations that name the member', () {
      expect(compareMembers(grund).map((m) => m.withText), <String>[
        'aus diesem Grund',
        'die Ursache ermitteln',
        'der Anlass',
      ]);
      expect(compareMembers(angst).map((m) => m.withText), <String?>[
        'Angst vor + Dat.',
        'Furcht vor',
        'Sorge um + Akk.',
        null,
      ]);
      expect(compareMembers(circa).map((m) => m.withText), <String?>[
        null,
        null,
        'rund + Zahl',
      ], reason: '"ca." is not circa');
    });

    test("FR-W2-02 With: else the member's word's own", () {
      final sorge = compareMembers(
        CompareSet(
          const CompareWord(
            uid: 's',
            german: 'Sorge / Panik',
            english: 'worry / panic',
            step: 'C2.1',
          ),
          <String, CompareWord>{'Sorge': angst.resolved['Sorge']!},
        ),
      ).first;
      expect(sorge.withText, 'sich Sorgen machen');
    });

    test("FR-W2-02 Example: the member's word's, else the set's naming it", () {
      expect(compareMembers(grund).map((m) => m.example?.german), <String>[
        'Aus diesem Grund bleibe ich zu Hause.',
        'Die Ursache des Feuers ist unklar.',
        'Aus Anlass des Jubiläums gab es ein Fest.',
      ]);
      expect(compareMembers(circa).map((m) => m.example?.german), <String?>[
        null,
        'Die Fahrt dauert etwa 40 Minuten.',
        'Der Tisch ist rund.',
      ]);
      final furcht = compareMembers(angst)[1];
      expect(furcht.example?.german, startsWith('Angst ist diffus, Furcht'));
    });

    test('FR-W2-02 a member nothing speaks for has every cell empty', () {
      final panik = compareMembers(angst).last;
      expect(
        (panik.register, panik.withText, panik.example, panik.useWhen),
        (null, null, null, null),
      );
    });
  });

  group('FR-W2-03 Quiz these', () {
    List<QuizItem> quiz(CompareSet set, {int seed = 1, int length = 5}) =>
        compareQuizItems(
          compareMembers(set),
          setUid: set.word.uid,
          seed: seed,
          length: length,
        );

    test('FR-W2-03 each sentence gaps its member; the tiles are the set', () {
      final items = quiz(grund);
      expect(items, hasLength(5), reason: 'five sentences name a member');
      expect(items.map((i) => i.ord), <int>[1, 2, 3, 4, 5]);
      for (final item in items) {
        expect(item.direction, QuizDirection.compare);
        expect(item.tiles, isTrue);
        expect(item.prompt, contains('___'));
        expect(item.options.toSet(), <String>{'Grund', 'Ursache', 'Anlass'});
        expect(item.hint, isNotNull);
      }
      final home = items.singleWhere((i) => i.prompt.startsWith('Aus diesem'));
      expect(home.prompt, 'Aus diesem ___ bleibe ich zu Hause.');
      expect(home.expected, 'Grund');
      expect(home.wordUid, 'uid-grund');
      expect(home.hint, "For this reason I'm staying at home.");
    });

    test('FR-W2-03 a sentence is asked once', () {
      // Five sentences: the set's two name three members and two; gapped
      // at each member they name, they would be eight items.
      expect(quiz(grund, length: 99), hasLength(5));
    });

    test("FR-W2-03 a member with no word rates the set's", () {
      final etwa = quiz(circa).singleWhere((i) => i.expected == 'etwa');
      expect(etwa.prompt, 'Die Fahrt dauert ___ 40 Minuten.');
      expect(etwa.wordUid, 'set-circa');
    });

    test('FR-W2-03 the same seed, the same quiz; up to length', () {
      List<String> prompts(int seed) => [
        for (final i in quiz(grund, seed: seed)) '${i.prompt} ${i.options}',
      ];
      expect(prompts(7), prompts(7));
      expect(
        List<int>.generate(8, (seed) => seed).map(prompts).toSet().length,
        greaterThan(1),
        reason: 'the seed orders it',
      );
      expect(quiz(grund, length: 3), hasLength(3));
    });

    test('FR-W2-03 four tiles at most, the answer among them', () {
      const five = CompareSet(
        CompareWord(
          uid: 's',
          german: 'Anfang / Beginn / Auftakt / Anbruch / Start',
          english: 'a / b / c / d / e',
          step: 'C2.1',
          examples: <CompareExample>[
            (german: 'Zum Auftakt sprach die Ministerin.', english: null),
          ],
        ),
      );
      final item = quiz(five).single;
      expect(item.options, hasLength(4));
      expect(item.options, contains('Auftakt'));
    });

    test('FR-W2-03 no sentence names a member: no quiz', () {
      expect(
        quiz(
          const CompareSet(
            CompareWord(
              uid: 's',
              german: 'obgleich / obschon',
              english: 'although',
              step: 'C2.1',
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('FR-W2-03 the builder asks the set sourceRef names', () async {
      final builder = QuizBuilder(
        _Sets(<String, CompareSet>{'set-grund': grund}),
      );
      final built = await builder.build(
        direction: QuizDirection.compare,
        source: QuizSource.compareSet,
        sourceRef: 'set-grund',
        length: 5,
        seed: 3,
        today: '2026-09-21',
      );
      expect(
        built.items.map((i) => i.prompt),
        quiz(grund, seed: 3).map((i) => i.prompt),
      );
      final missing = await builder.build(
        direction: QuizDirection.compare,
        source: QuizSource.compareSet,
        sourceRef: 'nope',
        length: 5,
        seed: 3,
        today: '2026-09-21',
      );
      expect(missing.items, isEmpty);
    });

    test('FR-W2-03 a tile is the answer or it is not', () {
      final item = quiz(grund).first;
      expect(grade(item, item.expected), Verdict.correct);
      expect(
        grade(item, item.options.firstWhere((o) => o != item.expected)),
        Verdict.wrong,
      );
    });
  });
}

class _Sets implements QuizStore {
  _Sets(this._sets);

  final Map<String, CompareSet> _sets;

  @override
  Future<List<QuizWord>> learned(QuizSource source, {String? ref}) async =>
      const <QuizWord>[];

  @override
  Future<List<QuizWord>> stepWords(String step) async => const <QuizWord>[];

  @override
  Future<CompareSet?> compareSet(String uid) async => _sets[uid];
}
