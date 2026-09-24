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

  test('a topic with no example practises its rule', () {
    const strategy = GrammarSource(
      uid: 'lesen',
      topic: 'Exam strategy: Lesen',
      rule:
          "Read the questions first, underline key words. Don't translate "
          'every word.',
      exampleDe: '—',
      exampleEn: '—',
      watchOut: 'Time per Teil is tight.',
      tags: <String>['gap-fill', 'pick-the-form'],
      levelCode: 'A2',
    );
    final items = generateItems(strategy, seed: 2);
    expect(items.length, greaterThanOrEqualTo(3));
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

  test("a closed word class's wrong forms are its other members", () {
    for (final seed in <int>[1, 2, 3]) {
      final sein = first<PickTheForm>(
        generateItems(
          one('Wir sind aus Bangladesch.', rule: 'sind'),
          seed: seed,
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
      generateItems(one('Die Wohnung ist neu.', rule: 'die'), seed: 1),
    );
    expect(pick.answer, 'Die');
    for (final option in pick.options) {
      expect(option[0], option[0].toUpperCase(), reason: option);
    }
  });

  test("the gap's word without its punctuation", () {
    final gap = first<GapFill>(
      generateItems(one('Wie heißen Sie?', rule: 'Sie'), seed: 1),
    );
    expect(gap.answer, 'Sie');
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

    test('there are 182', () => expect(rows, hasLength(182)));

    test('each yields 3–5 items of at least two types, every one sound', () {
      final problems = <String>[];
      for (final row in rows) {
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
          seed: practiceSeed(source.uid, '2026-09-21'),
          siblings: siblingsByLevel[source.levelCode]!,
        );
        final types = items.map((item) => item.runtimeType).toSet();
        final name = source.topic;
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
  });
}
