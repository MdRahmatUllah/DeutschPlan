import 'dart:convert';

import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/exam_grading.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// `exam_grading.dart` — #84.
void main() {
  WordQuestion word(ExamSection section, String expected, {String? prompt}) =>
      WordQuestion(section, 'w', prompt: prompt ?? 'x', expected: expected);

  const writing = WritingTask(
    'writing:1',
    level: 'A1',
    category: 'Wohnen',
    targets: <String>[
      'Heizung',
      'Vermieter',
      'kaputt',
      'reparieren',
      'kalt',
      'seit',
      'dringend',
      'Wohnung',
      'bitte',
      'Termin',
    ],
    minWords: 30,
    connectors: <String>['und'],
  );
  const speaking = SpeakingTask(
    'speaking:1',
    level: 'A1',
    category: 'Wohnen',
    seconds: 60,
  );
  String ticks(List<bool> ticks) => jsonEncode(ticks);

  group('BR-ANS-01…04 every item through answer_check', () {
    test('Vocabulary: any listed meaning; a typo is almost', () {
      final item = word(ExamSection.vocabulary, 'flat, apartment');
      expect(verdictFor(item, 'apartment'), Verdict.correct);
      expect(verdictFor(item, 'apartmnet'), Verdict.almost);
      expect(verdictFor(item, 'house'), Verdict.wrong);
    });

    test('Reverse: the article optional, a wrong one is wrong', () {
      final item = word(ExamSection.reverse, 'die Wohnung');
      expect(verdictFor(item, 'Wohnung'), Verdict.correct);
      expect(verdictFor(item, 'die Wohnung'), Verdict.correct);
      expect(verdictFor(item, 'der Wohnung'), Verdict.wrongArticle);
    });

    test('Articles: exactly', () {
      final item = word(ExamSection.articles, 'die');
      expect(verdictFor(item, 'die'), Verdict.correct);
      expect(verdictFor(item, 'der'), Verdict.wrong);
    });

    test('Word forms and Listening: the German, umlauts spelled out', () {
      expect(
        verdictFor(word(ExamSection.wordForms, 'Häuser'), 'Haeuser'),
        Verdict.correct,
      );
      expect(
        verdictFor(word(ExamSection.listening, 'die Tür'), 'Tuer'),
        Verdict.correct,
      );
    });

    test('Gap fill: the form the sentence uses', () {
      const gap = GapQuestion(
        'r',
        before: 'Zwei ',
        after: ' liegen hier.',
        answer: 'Rechnungen',
        translation: '',
      );
      expect(verdictFor(gap, 'Rechnungen'), Verdict.correct);
      expect(verdictFor(gap, 'Rechnung'), Verdict.wrong);
      // Checked as German: an umlaut may be spelled out.
      const umlaut = GapQuestion(
        'h',
        before: 'Die ',
        after: ' sind alt.',
        answer: 'Häuser',
        translation: '',
      );
      expect(verdictFor(umlaut, 'Haeuser'), Verdict.correct);
      // And, as German answers are, with its article or without.
      expect(verdictFor(gap, 'die Rechnungen'), Verdict.correct);
    });

    test('Grammar: a gap is checked as German, the rest exactly', () {
      const gap = GrammarQuestion(
        'g#0',
        GapFill(before: 'Ich ', after: '.', answer: 'gehe', translation: ''),
      );
      const order = GrammarQuestion(
        'g#1',
        OrderTheSentence(
          chips: <String>['gehe', 'Ich'],
          answer: <String>['Ich', 'gehe'],
        ),
      );
      const spot = GrammarQuestion(
        'g#2',
        SpotTheError(
          tokens: <String>['Ich', 'geht'],
          wrong: 1,
          correction: 'gehe',
        ),
      );
      expect(verdictFor(gap, 'GEHE'), Verdict.correct);
      expect(verdictFor(order, 'Ich gehe'), Verdict.correct);
      expect(verdictFor(order, 'gehe Ich'), Verdict.wrong);
      expect(verdictFor(spot, '1'), Verdict.correct);
      expect(verdictFor(spot, '0'), Verdict.wrong);
    });

    test('BR-ANS-04 points: correct 1, almost 0.5, the rest 0', () {
      final item = word(ExamSection.vocabulary, 'flat, apartment');
      expect(itemPoints(item, given: 'flat'), 1);
      expect(itemPoints(item, given: 'apartmnet'), 0.5);
      expect(itemPoints(item, given: 'house'), 0);
      expect(itemPoints(item), 0);
      expect(itemPoints(item, given: '  '), 0);
      expect(
        itemPoints(
          word(ExamSection.reverse, 'die Wohnung'),
          given: 'der Wohnung',
        ),
        0,
      );
    });
  });

  group('Writing', () {
    test('FR-L12W-01 a target counts in any form that starts with it', () {
      expect(
        targetsUsed('Die Heizungen sind kaputt.', <String>[
          'Heizung',
          'kaputt',
        ]),
        <String>['Heizung', 'kaputt'],
      );
      expect(targetsUsed('Die Tuer ist zu.', <String>['Tür']), <String>['Tür']);
      expect(targetsUsed('Es ist warm.', <String>['kalt']), isEmpty);
    });

    test('FR-L12W-01 a verb in any person, an umlaut plural, a hyphenated '
        'word', () {
      expect(
        targetsUsed(
          'Er bringt die Anzüge in die Werkstätten. Sie hört nichts. '
          'Wir wandern mit SIM-Karten.',
          <String>[
            'bringen',
            'Anzug',
            'Werkstatt',
            'hören',
            'wandern',
            'SIM-Karte',
          ],
        ),
        <String>[
          'bringen',
          'Anzug',
          'Werkstatt',
          'hören',
          'wandern',
          'SIM-Karte',
        ],
      );
    });

    test('FR-L12W-01 an umlaut in the target must be there: schon is not '
        'schön', () {
      expect(targetsUsed('Das ist schon gut.', <String>['schön']), isEmpty);
      expect(targetsUsed('Wir backen Kuchen.', <String>['Küche']), isEmpty);
      expect(targetsUsed('Der Turm ist hoch.', <String>['Tür']), isEmpty);
      expect(targetsUsed('Die Tür ist zu.', <String>['Tür']), <String>['Tür']);
    });

    test('FR-L12W-03 #388 one word counts for one target: Beweise is Beweis '
        'or beweisen, not both', () {
      const targets = <String>['beweisen', 'Richter', 'Beweis'];
      expect(
        targetsUsed('Der Richter sah die Beweise.', targets),
        hasLength(2),
      );
      expect(
        targetsUsed('Die Beweise, die Beweise!', targets),
        hasLength(1),
        reason: 'the same word twice is one word',
      );
      expect(targetsUsed('Die Beweise beweisen es.', targets), <String>[
        'beweisen',
        'Beweis',
      ], reason: 'two words, two targets');
      // The matching, not first come: Beweis takes "beweist" first, but
      // beweisen can have nothing else, so Beweis moves to the compound.
      expect(
        targetsUsed('Er beweist die Beweisaufnahme.', <String>[
          'Beweis',
          'beweisen',
        ]),
        <String>['Beweis', 'beweisen'],
      );
    });

    test('FR-L12W-01 #396 among matchings as large, a word lights the target '
        'of its case', () {
      expect(
        targetsUsed('Die Beweise waren klar.', <String>['beweisen', 'Beweis']),
        <String>['Beweis'],
      );
      expect(
        targetsUsed('Wir beweisen es.', <String>['Beweis', 'beweisen']),
        <String>['beweisen'],
      );
      // Never at the count's cost: the capital word goes where it must.
      expect(
        targetsUsed('Beweise sind Beweise.', <String>['beweisen']),
        <String>['beweisen'],
      );
    });

    test('#388 a word family is one target', () {
      expect(sameTargetFamily('Beweis', 'beweisen'), isTrue);
      expect(sameTargetFamily('Klage', 'klagen'), isTrue);
      // By the umlaut-free key, as the chips find them.
      expect(sameTargetFamily('Zahl', 'zählen'), isTrue);
      expect(sameTargetFamily('Arzt', 'Ärztin'), isTrue);
      expect(sameTargetFamily('Brot', 'Brötchen'), isTrue);
      expect(sameTargetFamily('Richter', 'Beweis'), isFalse);
    });

    test('the connectors a text uses: whole words, case aside, two words '
        'only together', () {
      const connectors = <String>['und', 'aber', 'dass', 'ohne dass'];
      expect(
        connectorsUsed('Aber ich weiß, dass es geht, und ohne dass du', [
          ...connectors,
        ]),
        connectors,
      );
      // "Unden" is not und, and "ohne … dass" apart is not ohne dass.
      expect(connectorsUsed('Unden ohne Geld, dass', connectors), <String>[
        'dass',
      ]);
      expect(connectorsUsed('', connectors), isEmpty);
    });

    test('FR-L12W-01 only a verb ending follows a verb\'s stem', () {
      for (final (text, target) in <(String, String)>[
        ('Das ist sehr gut.', 'sehen'),
        ('Das gehört mir.', 'gehen'),
        ('Gerade eben.', 'gern'),
        ('Es liegt unter dem Tisch.', 'unten'),
      ]) {
        expect(targetsUsed(text, <String>[target]), isEmpty, reason: target);
      }
      expect(
        targetsUsed('Die Tür war offene Sache. Ich sagte es.', <String>[
          'offen',
          'sagen',
        ]),
        <String>['offen', 'sagen'],
      );
    });

    test(
      'FR-L12W-01 a stem is never under three letters: sein is not seit',
      () {
        expect(targetsUsed('Seit Montag.', <String>['sein']), isEmpty);
        expect(targetsUsed('Ich war nicht da.', <String>['tun']), isEmpty);
        // "oben" would cut to "ob", and find "Obst".
        expect(targetsUsed('Ich esse Obst.', <String>['oben']), isEmpty);
      },
    );

    test('FR-L12W-01 a noun keeps its ending: Laden is not Ladung', () {
      expect(targetsUsed('Die Ladung ist schwer.', <String>['Laden']), isEmpty);
      // Cut, "Wagen" would take a verb's ending: "wage" (I dare).
      expect(targetsUsed('Ich wage es.', <String>['Wagen']), isEmpty);
      expect(targetsUsed('Zwei Läden.', <String>['Laden']), <String>['Laden']);
    });

    test('FR-L12W-02 a word is letters and digits, hyphens and apostrophes '
        'inside', () {
      expect(textWords("E-Mail, geht's, seit 2020!"), <String>[
        'E-Mail',
        "geht's",
        'seit',
        '2020',
      ]);
    });

    String text({required int targets, required int words}) {
      final used = writing.targets.take(targets).toList();
      return <String>[
        ...used,
        for (var i = used.length; i < words; i++) 'Wort',
      ].join(' ');
    }

    test('FR-L12W-03 one point for 6 targets, one for the minimum length', () {
      expect(writingAppPoints(writing, text(targets: 6, words: 30)), 2);
      expect(writingAppPoints(writing, text(targets: 5, words: 30)), 1);
      expect(writingAppPoints(writing, text(targets: 6, words: 29)), 1);
      expect(writingAppPoints(writing, text(targets: 5, words: 29)), 0);
    });

    test('FR-L12W-03 and a rubric of 2 × 0.5', () {
      final full = text(targets: 6, words: 30);
      expect(itemPoints(writing, given: full), 2);
      expect(
        itemPoints(writing, given: full, rubric: ticks([true, false])),
        2.5,
      );
      expect(itemPoints(writing, given: full, rubric: ticks([true, true])), 3);
      // Only the two ticks Writing has count, whatever the list holds.
      expect(
        itemPoints(writing, given: full, rubric: ticks([true, true, true])),
        3,
      );
    });

    test('FR-L12W-03 no text, no rubric points', () {
      expect(itemPoints(writing, rubric: ticks([true, true])), 0);
      expect(itemPoints(writing, given: '  ', rubric: ticks([true, true])), 0);
      expect(
        itemPoints(writing, given: 'kurz', rubric: ticks([true, true])),
        1,
      );
    });
  });

  test('FR-L12S-03 Speaking: its rubric, 4 × 1', () {
    const recording = 'recordings/7.m4a';
    expect(itemPoints(speaking, given: recording), 0);
    expect(
      itemPoints(
        speaking,
        given: recording,
        rubric: ticks([true, true, false, true]),
      ),
      3,
    );
    expect(
      itemPoints(
        speaking,
        given: recording,
        rubric: ticks([true, true, true, true]),
      ),
      4,
    );
  });

  test('FR-L12S-01, FR-L12S-04 no recording, no points', () {
    final all = ticks([true, true, true, true]);
    expect(itemPoints(speaking, rubric: all), 0);
    expect(itemPoints(speaking, given: '', rubric: all), 0);
  });

  group('BR-EXAM-04 the paper', () {
    /// A paper of [right] right Vocabulary answers out of 40, and Writing
    /// and Speaking left undone.
    PaperScore paper(int right) =>
        scorePaper(<({ExamItem item, String? given, String? rubric})>[
          for (var i = 0; i < 40; i++)
            (
              item: word(ExamSection.vocabulary, 'house'),
              given: i < right ? 'house' : 'door',
              rubric: null,
            ),
          (item: writing, given: null, rubric: null),
          (item: speaking, given: null, rubric: null),
        ], passPercent: 60);

    test('the points add up, out of 48', () {
      final score = paper(30);
      expect(score.total, 30);
      expect(score.max, 48);
      expect(score.points.take(40).where((p) => p == 1), hasLength(30));
    });

    test('passed at 60 %, not a point below', () {
      // 28.8 of 48 is the mark: 29 passes, 28 does not.
      expect(paper(29).passed, isTrue);
      expect(paper(28).passed, isFalse);
    });

    test('exactly the mark passes', () {
      final score = scorePaper(
        <({ExamItem item, String? given, String? rubric})>[
          for (var i = 0; i < 5; i++)
            (
              item: word(ExamSection.articles, 'die'),
              given: i < 3 ? 'die' : 'der',
              rubric: null,
            ),
        ],
        passPercent: 60,
      );
      expect(score.total / score.max, 0.6);
      expect(score.passed, isTrue);
    });

    test('an empty paper does not pass', () {
      expect(
        scorePaper(
          const <({ExamItem item, String? given, String? rubric})>[],
          passPercent: 0,
        ).passed,
        isFalse,
      );
    });
  });

  test('FR-L12-01 every item of a built paper grades after the codec', () {
    // A word question of each word section, round the codec.
    for (final section in <ExamSection>[
      ExamSection.vocabulary,
      ExamSection.reverse,
      ExamSection.articles,
      ExamSection.wordForms,
      ExamSection.listening,
    ]) {
      final item = WordQuestion(
        section,
        'w',
        prompt: 'x',
        expected: section == ExamSection.articles ? 'der' : 'Haus',
        form: section == ExamSection.wordForms ? FormLabel.plural : null,
      );
      final decoded = ExamItem.decode(item.encode());
      expect(itemPoints(decoded, given: item.expected), 1, reason: '$section');
    }
  });
}
