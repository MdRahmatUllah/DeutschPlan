@TestOn('vm')
library;

import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The grammar practice generator — #82, `grammar-practice.md`.
void main() {
  const konjunktiv = GrammarSource(
    uid: 'konj2',
    topic: 'Konjunktiv II – Höflichkeit',
    rule: 'könnte / würde + infinitive at the end of the sentence.',
    exampleDe: 'Könnten Sie mir bitte helfen? Ich hätte gern einen Kaffee.',
    exampleEn: "Could you help me, please? I'd like a coffee.",
    watchOut: '„Kann ich …?“ is fine with friends. With strangers, use könnte.',
    tags: <String>['gap-fill', 'pick-the-form', 'subjunctive'],
    levelCode: 'A2',
  );

  const weil = GrammarSource(
    uid: 'weil',
    topic: 'Nebensätze mit weil',
    rule: 'weil sends the conjugated verb to the end.',
    exampleDe: 'Ich lerne Deutsch, weil ich in München arbeite.',
    exampleEn: 'I learn German because I work in Munich.',
    watchOut: 'Not: weil ich arbeite in München.',
    tags: <String>['gap-fill', 'pick-the-form', 'nebensatz'],
    levelCode: 'A2',
  );

  T first<T extends GrammarItem>(List<GrammarItem> items) =>
      items.whereType<T>().first;

  test('gap fill blanks the form the rule names, not a word of watch out', () {
    const one = GrammarSource(
      uid: 'konj2',
      topic: 'Konjunktiv II – Höflichkeit',
      rule: 'könnte / würde + infinitive at the end of the sentence.',
      // "beschreiben" is longer, but the rule names könnte.
      exampleDe: 'Könnten Sie mir den Weg beschreiben?',
      exampleEn: 'Could you describe the way to me?',
      watchOut: '„Kann ich …?“ is fine with friends.',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A2',
    );
    final gap = first<GapFill>(generateItems(one, seed: 1));
    expect(gap.answer, 'Könnten');
    expect(gap.before, isEmpty);
    expect(gap.after, 'Sie mir den Weg beschreiben?');
    expect(gap.translation, 'Could you describe the way to me?');
  });

  test("watch out's English never picks the gap: not \"Ich\" for its "
      '„Kann ich …?“', () {
    const coffee = GrammarSource(
      uid: 'coffee',
      topic: 'Konjunktiv II – Höflichkeit',
      rule: 'könnte / würde + infinitive at the end of the sentence.',
      exampleDe: 'Ich hätte gern einen Kaffee.',
      exampleEn: "I'd like a coffee.",
      watchOut: '„Kann ich …?“ is fine with friends.',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A2',
    );
    for (final seed in <int>[1, 2, 3]) {
      expect(
        first<GapFill>(generateItems(coffee, seed: seed)).answer,
        isNot('Ich'),
      );
    }
  });

  test('FR-L15-01 #386 a topic with no example practises its rule, by gap '
      'fills alone: a form of an English word to pick is no German', () {
    const strategy = GrammarSource(
      uid: 'lesen',
      topic: 'Exam strategy: Lesen',
      rule:
          'Read the questions first. Underline key words. '
          "Don't translate every word.",
      exampleDe: '—',
      exampleEn: '—',
      watchOut: 'Time per Teil is tight.',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A2',
    );
    final items = generateItems(strategy, seed: 2);
    expect(items, hasLength(3), reason: 'one per sentence of the rule');
    expect(items, everyElement(isA<GapFill>()));
    for (final gap in items.whereType<GapFill>()) {
      expect(gap.answer, isNot('—'));
      expect(gap.translation, isEmpty);
    }
  });

  GrammarSource one(String sentence, {String rule = ''}) => GrammarSource(
    uid: sentence,
    topic: 'T',
    rule: rule,
    exampleDe: sentence,
    exampleEn: 'x',
    watchOut: 'y',
    tags: const <String>['gap-fill', 'pick-the-form'],
    levelCode: 'A1',
  );

  /// #330: *Pick the form* asks in another sentence than the gap fill's,
  /// here the course's.
  CourseText saying(String sentence) => CourseText(
    sentences: <({String german, String english})>[
      (german: sentence, english: ''),
    ],
  );

  test("a closed word class's wrong forms are its other members", () {
    for (final seed in <int>[1, 2, 3]) {
      final sein = first<PickTheForm>(
        generateItems(
          one('Wir sind aus Bangladesch.', rule: 'sind'),
          seed: seed,
          course: saying('Sie sind zu Hause.'),
        ),
      );
      expect(sein.answer, 'sind');
      expect(
        sein.options.where((o) => o != 'sind'),
        everyElement(
          isIn(<String>['bin', 'bist', 'ist', 'seid', 'war', 'waren']),
        ),
      );
      final dass = first<PickTheForm>(
        generateItems(
          one('Ich glaube, dass es regnet.', rule: 'dass'),
          seed: seed,
          course: saying('Er sagt, dass er kommt.'),
        ),
      );
      expect(dass.options, containsAll(<String>['dass']));
      expect(
        dass.options.where((o) => o != 'dass'),
        everyElement(isIn(<String>['das', 'was'])),
      );
    }
  });

  test('a capital stays a capital: Die → Das, not das', () {
    final pick = first<PickTheForm>(
      generateItems(
        one('Die Wohnung ist neu.', rule: 'die'),
        seed: 1,
        course: saying('Die Miete ist hoch.'),
      ),
    );
    expect(pick.answer, 'Die');
    for (final option in pick.options) {
      expect(option[0], option[0].toUpperCase(), reason: option);
    }
  });

  test('FR-L15-01 #330 a pronoun is the gap only where the topic is about '
      'it', () {
    GrammarSource about(String title) => GrammarSource(
      uid: title,
      topic: title,
      rule: 'Ich: the prefix an- goes to the end.',
      exampleDe: 'Ich rufe dich an.',
      exampleEn: "I'll call you.",
      watchOut: '',
      tags: const <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A1',
    );
    GapFill gap(String title) =>
        first<GapFill>(generateItems(about(title), seed: 1));
    expect(gap('Separable verbs').answer, 'an');
    expect(gap('Ich and du').answer, 'Ich');
  });

  test('FR-L15-01 #330 wartest never gets warteen: its wrong forms are the '
      "course's", () {
    final course = CourseText(
      texts: const <String>['warten wartet · hat gewartet', 'Ich warte.'],
      sentences: const <({String german, String english})>[
        (german: 'Wie lange wartest du schon?', english: ''),
      ],
    );
    for (final seed in <int>[1, 2, 3]) {
      final pick = first<PickTheForm>(
        generateItems(
          one('Worauf wartest du?', rule: 'warten auf'),
          seed: seed,
          course: course,
        ),
      );
      expect(pick.answer, 'wartest');
      expect(pick.before, 'Wie lange');
      expect(
        pick.options,
        everyElement(isIn(<String>['wartest', 'warte', 'wartet', 'warten'])),
      );
    }
  });

  test('FR-L15-01 #386 a sentence whose word is part of another token is '
      "passed over, not a crash: 'konnte/könnte'", () {
    final course = CourseText(
      sentences: const <({String german, String english})>[
        (german: 'Mutter/Mütter, konnte/könnte – Euro–Taka.', english: ''),
      ],
    );
    expect(
      () => generateItems(
        one('Er konnte nicht kommen.', rule: 'konnte'),
        seed: 1,
        course: course,
      ),
      returnsNormally,
    );
    expect(course.sentencesWith('konnte'), isEmpty);
    expect(course.sentencesWith('Euro'), isEmpty);
  });

  test('FR-L15-01 #386 a question word is no choice: "[Wo] kann man hier '
      'parken?" takes wann and warum too', () {
    for (final seed in <int>[1, 2, 3]) {
      final items = generateItems(
        one('Wo kann man hier parken?', rule: 'wo'),
        seed: seed,
        course: saying('Wo wohnst du?'),
      );
      for (final pick in items.whereType<PickTheForm>()) {
        expect(pick.answer, isNot('Wo'));
      }
    }
  });

  test('FR-L15-01 #406 sentences end at a sentence, not at an ordinal\'s dot '
      'or between two forms', () {
    List<({String german, String? english})> pairs(String de, String en) =>
        examplePairs(de, en);
    expect(
      pairs(
        'Heute ist der 17. September. Am dritten Oktober ist frei.',
        'Today is 17 September. 3 October is a holiday.',
      ),
      <({String german, String? english})>[
        (
          german: 'Heute ist der 17. September.',
          english: 'Today is 17 September.',
        ),
        (
          german: 'Am dritten Oktober ist frei.',
          english: '3 October is a holiday.',
        ),
      ],
    );
    expect(
      pairs(
        'Der Chef sagte, dass er morgen komme / kommt.',
        "The boss said he'd come tomorrow.",
      ).map((pair) => pair.german),
      <String>['Der Chef sagte, dass er morgen komme / kommt.'],
    );
    expect(
      pairs(
        'Wie heißen Sie? / Wie heißt du?',
        "What's your name? / What's your name?",
      ).map((pair) => pair.german),
      <String>['Wie heißen Sie?', 'Wie heißt du?'],
    );
    // German does not end a sentence before a number, which follows an
    // abbreviation; English does, and after a year's dot.
    for (final german in <String>[
      'Ansprüche bestehen, wenn die Voraussetzungen des § 5 Abs. 2 vorliegen.',
      'Die Stadt hat ca. 230 Brücken.',
      'Siehe S. 12 und Nr. 5.',
    ]) {
      expect(pairs(german, 'x').map((pair) => pair.german), <String>[german]);
    }
    expect(
      pairs(
        'Das Büro wurde 1990 gebaut. Es ist geschlossen.',
        'The office was built in 1990. The office is closed.',
      ),
      <({String german, String? english})>[
        (
          german: 'Das Büro wurde 1990 gebaut.',
          english: 'The office was built in 1990.',
        ),
        (german: 'Es ist geschlossen.', english: 'The office is closed.'),
      ],
    );
  });

  test('FR-L15-01 #406 a wrong form is the answer\'s own word\'s: not '
      '"bitter" for bitte, "heiß" for heißt, "sprecher" for spreche', () {
    final course = CourseText(
      words: const <({String german, String? forms})>[
        (german: 'bitte', forms: null),
        (german: 'bitter', forms: null),
        (german: 'heißen', forms: 'heißt · hat geheißen'),
        (german: 'heiß', forms: null),
        (german: 'sprechen', forms: 'spricht · hat gesprochen'),
        (german: 'Sprecher', forms: 'Sprecher'),
      ],
      sentences: const <({String german, String english})>[
        (german: 'Ich heiße Anna.', english: ''),
        (german: 'Heute ist es heißer.', english: ''),
        (german: 'Ich spreche Deutsch.', english: ''),
      ],
    );
    expect(course.sameWord('heißt', 'heißen'), isTrue, reason: 'listed');
    expect(course.sameWord('heißen', 'heiße'), isTrue, reason: 'a verb ending');
    expect(course.sameWord('heißt', 'heiß'), isFalse, reason: 'the adjective');
    expect(course.sameWord('heißen', 'heißer'), isFalse, reason: "heiß's -er");
    expect(course.sameWord('bitte', 'bitter'), isFalse);
    expect(course.sameWord('spreche', 'sprechen'), isTrue);
    expect(
      course.sameWord('spreche', 'sprecher'),
      isFalse,
      reason: 'the course writes Sprecher, a noun',
    );
    expect(course.knows('Sprecher'), isTrue);
    expect(course.knows('sprecher'), isFalse);
    expect(
      CourseText.none.sameWord('bitte', 'bitter'),
      isTrue,
      reason: 'no course: any form',
    );
  });

  test('FR-L15-01 #406 a made-up wrong form is none the course writes, never '
      'another word: "Bitte!" is offered neither Bitter nor Bitten', () {
    final course = CourseText(
      words: const <({String german, String? forms})>[
        (german: 'bitte', forms: null),
        (german: 'bitter', forms: null),
        (german: 'bitten', forms: 'bittet · hat gebeten'),
      ],
    );
    for (var seed = 1; seed <= 20; seed++) {
      final pick = first<PickTheForm>(
        generateItems(one('Bitte!'), seed: seed, course: course),
      );
      expect(pick.answer, 'Bitte', reason: 'no real wrong form: made-up ones');
      expect(pick.options, hasLength(3), reason: '$seed');
      expect(pick.options, isNot(contains('Bitter')), reason: '$seed');
      expect(pick.options, isNot(contains('Bitten')), reason: '$seed');
    }
  });

  test("FR-L15-01 #406 a word's forms are its headword's: not a phrase's, "
      "a separable verb's under its base's, and none of a word two write "
      'alike', () {
    final course = CourseText(
      words: const <({String german, String? forms})>[
        (german: 'wissen', forms: 'weiß · hat gewusst'),
        (german: 'weiß', forms: null),
        (german: 'leiden', forms: 'leidet · hat gelitten'),
        (german: 'Es tut mir leid', forms: null),
        (german: 'sprechen', forms: 'spricht · hat gesprochen'),
        (german: 'ansprechen', forms: 'spricht an · hat angesprochen'),
        (german: 'warten', forms: 'wartet · hat gewartet'),
        (german: 'alt', forms: 'älter · am ältesten'),
        (german: 'aufräumen', forms: 'räumt auf · hat aufgeräumt'),
      ],
      texts: const <String>['Sprich! Ich leide. Warten Sie. weiße weißes'],
    );
    expect(course.sameWord('weiß', 'weiße'), isFalse, reason: 'the colour');
    expect(course.sameWord('weiß', 'gewusst'), isFalse, reason: 'wissen');
    expect(course.formsOf('weiß'), <String>['weiß']);
    expect(course.sameWord('leide', 'leid'), isFalse, reason: 'a phrase');
    expect(
      course.formsOf('leide'),
      unorderedEquals(<String>['leiden', 'leidet', 'gelitten']),
    );
    expect(
      course.formsOf('Sprich'),
      unorderedEquals(<String>['sprechen', 'spricht', 'gesprochen']),
      reason: 'the er form less -t; not ansprechen, nor its "an"',
    );
    expect(course.sameWord('Sprich', 'spricht'), isTrue);
    expect(
      course.formsOf('Warten'),
      unorderedEquals(<String>['warten', 'wartet', 'gewartet']),
    );
    expect(
      course.formsOf('älter'),
      unorderedEquals(<String>['alt', 'älter', 'ältesten']),
      reason: 'not "am"',
    );
    expect(
      course.formsOf('räumt'),
      unorderedEquals(<String>['aufräumen', 'räumt', 'aufgeräumt']),
      reason: 'not "auf"',
    );
    expect(CourseText.none.formsOf('warten'), isEmpty);
  });

  test("FR-L15-01 #406 Pick the form offers the answer's own forms, never a "
      'made-up one: "Wartet" for Warten, "Spricht" for Sprich', () {
    final course = CourseText(
      words: const <({String german, String? forms})>[
        (german: 'warten', forms: 'wartet · hat gewartet'),
        (german: 'sprechen', forms: 'spricht · hat gesprochen'),
        (german: 'ansprechen', forms: 'spricht an · hat angesprochen'),
        (german: 'bitte', forms: null),
        (german: 'hier', forms: null),
        (german: 'langsam', forms: null),
      ],
      texts: const <String>['Warten Sie bitte hier. Sprich langsam!'],
    );
    const imperative = GrammarSource(
      uid: 'imperative',
      topic: 'Imperative',
      rule: 'du: stem without -st (Komm! Nimm!); ihr: Kommt!; Sie: Kommen Sie!',
      exampleDe: 'Warten Sie bitte hier. Sprich langsam!',
      exampleEn: 'Please wait here. Speak slowly!',
      watchOut: 'e→i also in the imperative (sprich, nimm, iss).',
      tags: <String>['gap-fill', 'pick-the-form', 'verb-form'],
      levelCode: 'A1',
    );
    final picks = <PickTheForm>[
      for (var seed = 1; seed <= 6; seed++)
        ...generateItems(
          imperative,
          seed: seed,
          course: course,
        ).whereType<PickTheForm>(),
    ];
    expect(picks.map((pick) => pick.answer).toSet(), <String>{
      'Warten',
      'Sprich',
    });
    for (final pick in picks) {
      expect(
        pick.options.where((option) => option != pick.answer),
        everyElement(
          isIn(<String>[
            'Wartet',
            'Gewartet',
            'Sprechen',
            'Spricht',
            'Gesprochen',
          ]),
        ),
      );
    }
  });

  test('FR-L15-01 #406 a separable prefix is its verb\'s where it closes the '
      'clause: "an" of "rufe … an", not of "an der Ecke"', () {
    expect(
      first<GapFill>(
        generateItems(
          one('Ich rufe dich morgen an.', rule: 'anrufen'),
          seed: 1,
        ),
      ).answer,
      'an',
    );
    expect(
      first<GapFill>(
        generateItems(one('Wir warten an der Ecke.', rule: 'anrufen'), seed: 1),
      ).answer,
      isNot('an'),
    );
  });

  test('FR-L15-01 #406 a gap fill filling in keeps a translation: the '
      "whole example's where the two don't split alike", () {
    const three = GrammarSource(
      uid: 'three',
      topic: 'T',
      rule: 'lernen',
      exampleDe: 'Ich lerne Deutsch. Du lernst Englisch. Er lernt Spanisch.',
      exampleEn: 'I learn German, you English and he Spanish.',
      watchOut: '',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A1',
    );
    final gaps = generateItems(three, seed: 1).whereType<GapFill>().toList();
    expect(gaps, hasLength(2), reason: 'the gap fill and the one filling in');
    for (final gap in gaps) {
      expect(gap.translation, three.exampleEn);
    }
  });

  test('FR-L15-01 #406 a contraction is its preposition in a topic about '
      'prepositions: "vom" for the rule\'s von, not "ins" for an English '
      '"in"', () {
    GrammarSource tagged(String sentence, String rule, String tag) =>
        GrammarSource(
          uid: sentence,
          topic: 'T',
          rule: rule,
          exampleDe: sentence,
          exampleEn: 'x',
          watchOut: 'y',
          tags: <String>['gap-fill', 'pick-the-form', tag],
          levelCode: 'B1',
        );
    expect(
      first<GapFill>(
        generateItems(
          tagged('Es hängt vom Wetter ab.', 'von + dative', 'preposition'),
          seed: 1,
        ),
      ).answer,
      'vom',
    );
    expect(
      first<GapFill>(
        generateItems(
          tagged(
            'Gestern ging er ins Kino.',
            'The verb comes second in a main clause.',
            'word-order',
          ),
          seed: 1,
        ),
      ).answer,
      isNot('ins'),
    );
  });

  test('FR-L15-01 #406 a form the rule names is a wrong form only of its own '
      'word: bitte is offered neither bitter nor bitten', () {
    final course = CourseText(
      words: const <({String german, String? forms})>[
        (german: 'bitte', forms: null),
        (german: 'bitter', forms: null),
        (german: 'bitten', forms: 'bittet · hat gebeten'),
        (german: 'warten', forms: 'wartet · hat gewartet'),
      ],
      sentences: const <({String german, String english})>[
        (german: 'Komm bitte mit.', english: ''),
        (german: 'Ich warte hier.', english: ''),
      ],
    );
    for (final seed in <int>[1, 2, 3]) {
      for (final pick in generateItems(
        one('Warten Sie bitte hier.', rule: 'bitte, bitter, bitten'),
        seed: seed,
        course: course,
      ).whereType<PickTheForm>()) {
        expect(pick.options, isNot(contains('bitter')), reason: '$seed');
        expect(pick.options, isNot(contains('bitten')), reason: '$seed');
      }
    }
  });

  test("the gap's word without its punctuation", () {
    final gap = first<GapFill>(
      generateItems(one('Wo wohnt Anna?', rule: 'Anna'), seed: 1),
    );
    expect(gap.answer, 'Anna');
    expect(gap.after, '?');
  });

  test('pick the form: the answer and two other forms', () {
    final pick = first<PickTheForm>(generateItems(konjunktiv, seed: 1));
    expect(pick.options, hasLength(3));
    expect(pick.options, contains(pick.answer));
    expect(pick.options.toSet(), hasLength(3));
  });

  test("spot the error, for a topic about forms: one word wrong, its "
      'correction the original', () {
    final spot = first<SpotTheError>(generateItems(konjunktiv, seed: 1));
    expect(spot.tokens[spot.wrong], isNot(spot.correction));
  });

  test('order the sentence, for word-order topics only', () {
    final items = generateItems(weil, seed: 3);
    final order = first<OrderTheSentence>(items);
    expect(order.chips, unorderedEquals(order.answer));
    expect(order.chips, isNot(orderedEquals(order.answer)));
    expect(
      generateItems(konjunktiv, seed: 3).whereType<OrderTheSentence>(),
      isEmpty,
    );
  });

  test('rule recall at C1/C2, with the sibling rules as wrong options', () {
    const c1 = GrammarSource(
      uid: 'c1',
      topic: 'Nominalstil',
      rule: 'Turn verbs into nouns in formal writing. Use genitive links.',
      exampleDe: 'Nach der Prüfung der Unterlagen folgt die Entscheidung.',
      exampleEn: 'After the documents are checked, the decision follows.',
      watchOut: 'Too many nouns make a text hard to read.',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'C1',
    );
    final recall = first<RuleRecall>(
      generateItems(
        c1,
        seed: 5,
        siblings: <String>[
          'Konjunktiv I reports speech.',
          'Participles can stand as adjectives.',
          'Modal particles soften a statement.',
        ],
      ),
    );
    expect(recall.options, hasLength(4));
    expect(
      recall.options[recall.answer],
      'Turn verbs into nouns in formal writing.',
    );
    // A label is not an option: the sentence it opens is.
    final labelled = first<RuleRecall>(
      generateItems(
        const GrammarSource(
          uid: 'c2',
          topic: 'Gehobener Stil',
          rule:
              'Features: nominal style, genitive, participles. Use sparingly.',
          exampleDe: 'Die Entscheidung des Gerichts ist endgültig.',
          exampleEn: "The court's decision is final.",
          watchOut: 'Too formal for a chat.',
          tags: <String>['gap-fill', 'pick-the-form'],
          levelCode: 'C2',
        ),
        seed: 5,
        siblings: <String>[
          'Features: short sentences.',
          'Features: short sentences.',
          'Austria: Jänner for Januar.',
          'Hören: note key words.',
          'Sprechen: plan the talk.',
        ],
      ),
    );
    expect(
      labelled.options[labelled.answer],
      'Features: nominal style, genitive, participles.',
    );
    expect(labelled.options.toSet(), hasLength(4));
    // Below C1 there is no recall, siblings or not.
    expect(
      generateItems(
        konjunktiv,
        seed: 5,
        siblings: <String>['a.', 'b.', 'c.'],
      ).whereType<RuleRecall>(),
      isEmpty,
    );
  });

  test('FR-L15-01 seeded per topic and day: the same all day', () {
    final seed = practiceSeed('konj2', '2026-09-21');
    expect(practiceSeed('konj2', '2026-09-21'), seed);
    expect(practiceSeed('konj2', '2026-09-22'), isNot(seed));
    String shape(List<GrammarItem> items) => items
        .map(
          (item) => switch (item) {
            PickTheForm(:final options) => options.join('|'),
            GapFill(:final answer) => answer,
            _ => item.runtimeType.toString(),
          },
        )
        .join(' ');
    expect(
      shape(generateItems(konjunktiv, seed: seed)),
      shape(generateItems(konjunktiv, seed: seed)),
    );
  });

  test('BR-FSRS-05: all right Good, one wrong Hard, more Again', () {
    expect(practiceRating(items: 5, correct: 5), 3);
    expect(practiceRating(items: 5, correct: 4), 2);
    expect(practiceRating(items: 5, correct: 3), 1);
    expect(practiceRating(items: 3, correct: 0), 1);
  });

  group('every topic in the real course', () {
    final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
    tearDownAll(db.close);
    final rows = db.select(
      'SELECT uid, topic, rule, example_de, example_en, watch_out, tags, '
      'level_code FROM grammar_topics ORDER BY level_code, seq',
    );
    final siblingsByLevel = <String, List<String>>{};
    for (final row in rows) {
      (siblingsByLevel[row['level_code'] as String] ??= <String>[]).add(
        row['rule'] as String,
      );
    }

    // #330, the issue's probe: what the course says, as the app loads it
    // (`course_text.dart`), and every item as L15 would ask it.
    final course = CourseText(
      words: <({String german, String? forms})>[
        for (final row in db.select('SELECT german, forms FROM words'))
          (german: row['german'] as String, forms: row['forms'] as String?),
      ],
      texts: <String>[for (final row in rows) row['example_de'] as String],
      sentences: <({String german, String english})>[
        for (final row in db.select(
          'SELECT german, english FROM word_examples ORDER BY word_uid, ord',
        ))
          (
            german: row['german'] as String,
            english: row['english'] as String? ?? '',
          ),
      ],
    );
    test('there are 182', () => expect(rows, hasLength(182)));

    test('FR-L15-01 each yields 3–5 items of at least two types, every one '
        'sound, with the course and without it, on thirty days', () {
      final problems = <String>[];
      // Thirty days, not one: #386's crash was 3 topic-days in 21,840.
      for (final (row, known, day) in <(Row, CourseText?, String)>[
        for (var d = 1; d <= 30; d++)
          for (final row in rows) ...<(Row, CourseText?, String)>[
            (row, null, '2026-10-${d.toString().padLeft(2, '0')}'),
            (row, course, '2026-10-${d.toString().padLeft(2, '0')}'),
          ],
      ]) {
        final source = GrammarSource(
          uid: row['uid'] as String,
          topic: row['topic'] as String,
          rule: row['rule'] as String,
          exampleDe: row['example_de'] as String,
          exampleEn: row['example_en'] as String,
          watchOut: row['watch_out'] as String,
          tags: (row['tags'] as String).split(','),
          levelCode: row['level_code'] as String,
        );
        final items = generateItems(
          source,
          seed: practiceSeed(source.uid, day),
          siblings: siblingsByLevel[source.levelCode]!,
          course: known,
        );
        final types = items.map((item) => item.runtimeType).toSet();
        final name = '${source.topic} ($day)';
        // With no German example: its English rule's gap fills, and the
        // rule recall at C1/C2, but no form of an English word (#386).
        if (!(row['example_de'] as String).contains(RegExp('[A-Za-z]'))) {
          if (!types.contains(GapFill) || types.contains(PickTheForm)) {
            problems.add('$name: $types for a rule in English');
          }
          continue;
        }
        if (items.length < 3 || items.length > 5) {
          problems.add('$name: ${items.length} items');
        }
        if (types.length < 2) problems.add('$name: ${types.length} type');
        if (!types.contains(GapFill) || !types.contains(PickTheForm)) {
          problems.add('$name: no gap fill or pick-the-form');
        }
        final tags = source.tags.toSet();
        if (tags.intersection(errorTags).isNotEmpty &&
            !types.contains(SpotTheError)) {
          problems.add('$name: tagged for errors, no spot-the-error');
        }
        if ((source.levelCode == 'C1' || source.levelCode == 'C2') &&
            !types.contains(RuleRecall)) {
          problems.add('$name: C1/C2 without rule recall');
        }
        for (final item in items) {
          switch (item) {
            case GapFill(:final answer):
              if (answer.trim().isEmpty) problems.add('$name: empty gap');
            case PickTheForm(:final options, :final answer):
              if (options.length != 3 ||
                  options.toSet().length != 3 ||
                  !options.contains(answer)) {
                problems.add('$name: options $options for $answer');
              }
            case SpotTheError(:final tokens, :final wrong, :final correction):
              if (tokens[wrong] == correction) {
                problems.add('$name: the error is the right word');
              }
            case OrderTheSentence(:final chips, :final answer):
              if (chips.length != answer.length) {
                problems.add('$name: chips lost a word');
              }
            case RuleRecall(:final options, :final answer):
              if (options.length != 4 ||
                  options.toSet().length != 4 ||
                  answer < 0 ||
                  options.any((option) => option.endsWith(':'))) {
                problems.add('$name: recall $options');
              }
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    GrammarSource source(Row row) => GrammarSource(
      uid: row['uid'] as String,
      topic: row['topic'] as String,
      rule: row['rule'] as String,
      exampleDe: row['example_de'] as String,
      exampleEn: row['example_en'] as String,
      watchOut: row['watch_out'] as String,
      tags: (row['tags'] as String).split(','),
      levelCode: row['level_code'] as String,
    );
    List<GrammarItem> practised(Row row) => generateItems(
      source(row),
      seed: practiceSeed(row['uid'] as String, '2026-09-24'),
      siblings: siblingsByLevel[row['level_code']]!,
      course: course,
    );
    String sentence(String before, String answer, String after) =>
        '$before $answer $after'.replaceAll(RegExp(r'\s+'), '');

    // Anything the course writes counts, its rules and *watch out* too.
    final known = <String>{
      for (final row in db.select('SELECT german, forms FROM words'))
        for (final word in words('${row['german']} ${row['forms'] ?? ''}'))
          word.toLowerCase(),
      for (final row in db.select('SELECT german FROM word_examples'))
        for (final word in words(row['german'] as String)) word.toLowerCase(),
      for (final row in rows)
        for (final word in words(
          '${row['rule']} ${row['example_de']} ${row['watch_out']}',
        ))
          word.toLowerCase(),
    };

    test('FR-L15-01 #330 a wrong form is German the course uses: at most 5 % '
        'are not', () {
      final unknown = <String>[];
      var all = 0;
      for (final row in rows) {
        for (final pick in practised(row).whereType<PickTheForm>()) {
          for (final option in pick.options.where((o) => o != pick.answer)) {
            all++;
            if (!known.contains(option.toLowerCase())) unknown.add(option);
          }
        }
      }
      expect(
        unknown.length / all,
        lessThanOrEqualTo(0.05),
        reason: '${unknown.length} of $all: ${unknown.join(', ')}',
      );
    });

    test('FR-L15-01 #330 pick the form never asks the gap fill\'s '
        'sentence again', () {
      // A topic with no example ("—") practises its rule, in English: when
      // that is one sentence, there is no other to ask in.
      final again = <String>[
        for (final row in rows)
          if (practised(row) case final items
              when (row['example_de'] as String).contains(RegExp('[A-Za-z]')))
            for (final pick in items.whereType<PickTheForm>())
              for (final gap in items.whereType<GapFill>())
                if (sentence(pick.before, pick.answer, pick.after) ==
                    sentence(gap.before, gap.answer, gap.after))
                  row['topic'] as String,
      ];
      expect(again, isEmpty, reason: again.join('\n'));
    });

    List<GrammarItem> itemsOn(Row row, String day) => generateItems(
      source(row),
      seed: practiceSeed(row['uid'] as String, day),
      siblings: siblingsByLevel[row['level_code']]!,
      course: course,
    );
    Iterable<(Row, List<GrammarItem>)> thirtyDays() sync* {
      for (var d = 1; d <= 30; d++) {
        final day = '2026-10-${d.toString().padLeft(2, '0')}';
        for (final row in rows) {
          yield (row, itemsOn(row, day));
        }
      }
    }

    /// An item's sentence as the learner reads it, the gap filled.
    String sentenceOf(String before, String answer, String after) => <String>[
      if (before.isNotEmpty) before,
      if (after.isEmpty || RegExp('^[A-Za-zÄÖÜäöüß0-9„]').hasMatch(after))
        '$answer $after'.trim()
      else
        '$answer$after',
    ].join(' ');

    test('FR-L15-01 #406 no item is a fragment: not cut at an ordinal\'s '
        'dot, an abbreviation\'s, nor at " / "', () {
      final fragments = <String>[
        for (final (row, items) in thirtyDays())
          for (final item in items)
            if (switch (item) {
                  GapFill(:final before, :final answer, :final after) =>
                    sentenceOf(before, answer, after),
                  PickTheForm(:final before, :final answer, :final after) =>
                    sentenceOf(before, answer, after),
                  _ => null,
                }
                case final sentence?
                // Cut at " / ": "kommt." Cut at an ordinal: "Heute ist der
                // 17." where the example goes on "September. …". Cut after
                // an abbreviation: "2 vorliegen." of "§ 5 Abs. 2 vorliegen."
                when (RegExp('^[0-9]').hasMatch(sentence) &&
                        (row['example_de'] as String).contains(' $sentence')) ||
                    (RegExp('^[a-zäöüß]').hasMatch(sentence) &&
                        (row['example_de'] as String).contains(
                          '/ $sentence',
                        )) ||
                    (RegExp(r'[0-9]\.$').hasMatch(sentence) &&
                        RegExp('${RegExp.escape(sentence)} [A-ZÄÖÜ]')
                            .hasMatch(row['example_de'] as String)))
              '${row['topic']}: $sentence',
      ];
      expect(fragments.toSet(), isEmpty, reason: fragments.toSet().join('\n'));
    });

    test('FR-L15-01 #406 every gap fill has its translation where the '
        'example has one', () {
      final missing = <String>[
        for (final (row, items) in thirtyDays())
          if ((row['example_en'] as String).contains(RegExp('[A-Za-z]')) &&
              (row['example_de'] as String).contains(RegExp('[A-Za-z]')))
            for (final gap in items.whereType<GapFill>())
              if (gap.translation.isEmpty)
                '${row['topic']}: ${gap.before} ___ ${gap.after}',
      ];
      expect(missing.toSet(), isEmpty, reason: missing.toSet().join('\n'));
    });

    test("FR-L15-01 #406 the probe's wrong forms of another word are gone", () {
      const others = <(String, String)>{
        ('bitte', 'bitter'),
        ('heißt', 'heiß'),
        ('spreche', 'sprecher'),
        ('sich', 'sicher'),
        ('sich', 'sicht'),
        ('weiß', 'weiße'),
        ('weiß', 'weißes'),
        ('leide', 'leid'),
      };
      final found = <String>[
        for (final (row, items) in thirtyDays())
          for (final pick in items.whereType<PickTheForm>())
            for (final option in pick.options)
              if (others.contains((pick.answer.toLowerCase(), option)))
                '${row['topic']}: ${pick.answer} → $option',
      ];
      expect(found.toSet(), isEmpty, reason: found.toSet().join('\n'));
    });

    test('FR-L15-01 #406 made-up wrong forms come last, after any borrowed '
        'sentence with real ones: none over thirty days', () {
      final made = <String>[
        for (final (row, items) in thirtyDays())
          for (final pick in items.whereType<PickTheForm>())
            for (final option in pick.options)
              if (!words(option)
                  .every((word) => known.contains(word.toLowerCase())))
                '${row['topic']}: ${pick.answer} → $option',
      ];
      expect(made.toSet(), isEmpty, reason: made.toSet().join('\n'));
    });

    test('FR-L15-01 #330 the gap practises the rule: the prefix, the time, '
        'the case', () {
      Row topic(String name) => rows.firstWhere((row) => row['topic'] == name);
      Set<String> gaps(String name) => <String>{
        for (var day = 1; day <= 9; day++)
          for (final gap in generateItems(
            source(topic(name)),
            seed: practiceSeed(topic(name)['uid'] as String, '2026-09-0$day'),
            course: course,
          ).whereType<GapFill>())
            gap.answer,
      };
      // Pick the form borrows a sentence for the best of the gap's words,
      // the longer of two alike (#386): the case-marked possessive, not
      // "für [das] Fenster".
      Set<String> picks(String name) => <String>{
        for (var day = 1; day <= 9; day++)
          for (final pick in generateItems(
            source(topic(name)),
            seed: practiceSeed(topic(name)['uid'] as String, '2026-09-0$day'),
            course: course,
          ).whereType<PickTheForm>())
            pick.answer,
      };
      expect(
        picks('Genitive'),
        everyElement(isIn(<String>['meines', 'meinem'])),
      );
      // #406: the contraction of the rule's *von*, the prefix of its
      // *abhängen*, or *um* of *sich bewerben um* — not "Wetter".
      expect(
        gaps('Verbs with fixed prepositions (B1 list)'),
        everyElement(isIn(<String>['vom', 'ab', 'um'])),
      );
      expect(
        gaps('Separable verbs'),
        everyElement(isIn(<String>['ein', 'an'])),
      );
      expect(
        gaps('Clock time & dates'),
        everyElement(isIn(<String>['am', 'um', 'halb'])),
      );
      expect(gaps('Genitive'), everyElement(isIn(<String>['meines', 'des'])));
    });
  });
}

/// A text's words, as the generator splits them.
Iterable<String> words(String text) =>
    RegExp(r"[A-Za-zÄÖÜäöüß'-]+")
        .allMatches(text)
        .map((match) => match.group(0)!);
