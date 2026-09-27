@TestOn('vm')
library;

import 'package:sogda/domain/answer_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answer checking — #75, BR-ANS-01…04.
///
/// The four criteria on the issue, plus the cases where being lenient would
/// mark a genuinely wrong answer right — which is the failure that matters
/// here. A learner told they were right when they were not never learns the
/// word.
void main() {
  group('BR-ANS-01 — DE→EN meanings', () {
    test('any synonym in the list counts', () {
      const expected = 'house / home, building';

      for (final given in <String>['house', 'home', 'building']) {
        expect(checkMeaning(given, expected), Verdict.correct, reason: given);
      }
    });

    test('and one that is not in it does not', () {
      expect(checkMeaning('flat', 'house / home'), Verdict.wrong);
    });

    test('case is ignored', () {
      for (final given in <String>['HOUSE', 'House', 'hOuSe']) {
        expect(checkMeaning(given, 'house'), Verdict.correct, reason: given);
      }
    });

    test('a leading "to " is ignored, on either side', () {
      expect(checkMeaning('to go', 'go'), Verdict.correct);
      expect(checkMeaning('go', 'to go'), Verdict.correct);
      expect(checkMeaning('to go', 'to go'), Verdict.correct);
      expect(checkMeaning('To Go', 'go'), Verdict.correct);
    });

    test('but only at the front, and only as a word', () {
      expect(checkMeaning('tomato', 'tomato'), Verdict.correct);
      expect(checkMeaning('mato', 'tomato'), Verdict.wrong);
      expect(checkMeaning('point to it', 'point to it'), Verdict.correct);

      // Both sides asymmetric on purpose. An unanchored `to\s+` mangles the
      // given and the expected identically, so a same-string case cannot see
      // it — I only found that by planting the bug and watching the test
      // above stay green.
      expect(checkMeaning('it', 'point to it'), Verdict.wrong);
      expect(checkMeaning('point to it', 'it'), Verdict.wrong);
      expect(checkMeaning('the shop', 'walk to the shop'), Verdict.wrong);
    });

    test('a one-character typo on a word of six or more is almost', () {
      for (final pair in const <(String, String)>[
        ('understnad', 'understand'), // transposition
        ('understnd', 'understand'), // deletion
        ('understaand', 'understand'), // insertion
        ('undarstand', 'understand'), // substitution
        ('windo', 'window'), // exactly six
      ]) {
        expect(checkMeaning(pair.$1, pair.$2), Verdict.almost, reason: '$pair');
      }
    });

    test('and on a shorter word it is wrong, not almost', () {
      // Five letters and one edit apart is usually a different word. Being
      // generous here marks a genuinely wrong answer right.
      for (final pair in const <(String, String)>[
        ('hous', 'house'),
        ('bread', 'break'),
        ('sonne', 'sohne'),
        ('cat', 'car'),
      ]) {
        expect(checkMeaning(pair.$1, pair.$2), Verdict.wrong, reason: '$pair');
      }
    });

    test('two characters out is wrong however long the word', () {
      expect(checkMeaning('undrstnad', 'understand'), Verdict.wrong);
      expect(checkMeaning('xxxxxxxxxx', 'understand'), Verdict.wrong);
    });

    test('the length that matters is the expected word, not the guess', () {
      // A learner who types four letters at a ten-letter answer has not made
      // a typo. Judging by what they typed would let it through.
      expect(checkMeaning('und', 'understand'), Verdict.wrong);
    });

    test('the best verdict across the list wins, not the first', () {
      // "wlak" is wrong against "go" and almost against "walk". Stopping at
      // the first candidate would call it wrong.
      expect(checkMeaning('wlak', 'go / walk'), Verdict.wrong);
      expect(checkMeaning('walkign', 'go / walking'), Verdict.almost);
      expect(checkMeaning('walking', 'walkign / go'), Verdict.almost);
    });

    test('a German article is not stripped off an English meaning', () {
      // `text_norm` peels der/die/das because PIPE-04 says so for German.
      // `die` is an ordinary English verb, and with the strip on, "die out"
      // keyed to "out" — so typing half the answer scored full marks.
      for (final expected in const <String>[
        'die out',
        'die down',
        'die away',
        'die young',
      ]) {
        final tail = expected.split(' ').last;
        expect(checkMeaning(tail, expected), Verdict.wrong, reason: expected);
        expect(checkMeaning(expected, expected), Verdict.correct);

        // Both sides, because stripping only the given or only the expected
        // leaves the other case passing. This is the direction that scored a
        // half-answer full marks.
        expect(checkMeaning(expected, tail), Verdict.wrong, reason: expected);
      }
    });

    test('the typo allowance is per word, not per phrase', () {
      // "go out" is six characters and no word in it is six letters, so a
      // different preposition is a different answer, not a typo.
      expect(checkMeaning('go put', 'go out'), Verdict.wrong);
      expect(checkMeaning('go ou', 'go out'), Verdict.wrong);
      expect(checkMeaning('sit dowo', 'sit down'), Verdict.wrong);

      // The word that matters is the one that was mistyped, not the longest
      // in the answer. "after" is five letters, so it stays wrong even beside
      // a ten-letter word.
      expect(checkMeaning('to look aftre', 'to look after'), Verdict.wrong);
      expect(
        checkMeaning('look aftre understand', 'look after understand'),
        Verdict.wrong,
      );

      // And a long word in a phrase does earn it.
      expect(
        checkMeaning('look after understnad', 'look after understand'),
        Verdict.almost,
      );

      // Two words out is not one typo, however long they are. Both
      // orderings, because a loop that keeps only the first difference and
      // one that keeps only the last each pass the other case.
      expect(
        checkMeaning('loko after understnad', 'look after understand'),
        Verdict.wrong,
      );
      expect(
        checkMeaning('understnad after goo', 'understand after go'),
        Verdict.wrong,
      );

      // A missing space is a typo with no one word to blame it on, so it
      // falls back to the longest expected word — which still has to be six.
      expect(checkMeaning('goout', 'go out'), Verdict.wrong);
      expect(
        checkMeaning('lookafter understand', 'look after understand'),
        Verdict.almost,
        reason: 'a missing space is one edit, and the phrase has a long word',
      );
    });

    test('a semicolon separates too, and empty entries are skipped', () {
      expect(checkMeaning('home', 'house; home'), Verdict.correct);
      expect(checkMeaning('home', 'house / / home,'), Verdict.correct);
    });

    test('nothing typed is wrong, and so is nothing expected', () {
      expect(checkMeaning('', 'house'), Verdict.wrong);
      expect(checkMeaning('   ', 'house'), Verdict.wrong);
      expect(checkMeaning('house', ''), Verdict.wrong);
      expect(checkMeaning('', ''), Verdict.wrong);
    });
  });

  group('BR-ANS-02 — EN→DE', () {
    test('with or without the article', () {
      expect(checkGerman('Haus', 'Haus', article: 'das'), Verdict.correct);
      expect(checkGerman('das Haus', 'Haus', article: 'das'), Verdict.correct);
      expect(checkGerman('Das Haus', 'Haus', article: 'das'), Verdict.correct);
    });

    test('and when the article is carried on the German instead', () {
      // The source spreadsheets have it both ways.
      expect(checkGerman('Haus', 'das Haus'), Verdict.correct);
      expect(checkGerman('das Haus', 'das Haus'), Verdict.correct);
    });

    test('ä, ae and a are all accepted', () {
      for (final given in <String>['Tür', 'Tuer', 'Tur']) {
        expect(checkGerman(given, 'Tür'), Verdict.correct, reason: given);
      }
      for (final given in <String>['schön', 'schoen', 'schon']) {
        expect(checkGerman(given, 'schön'), Verdict.correct, reason: given);
      }
      for (final given in <String>['Mädchen', 'Maedchen', 'Madchen']) {
        expect(checkGerman(given, 'Mädchen'), Verdict.correct, reason: given);
      }
    });

    test('ß and ss are the same word', () {
      expect(checkGerman('Straße', 'Strasse'), Verdict.correct);
      expect(checkGerman('Strasse', 'Straße'), Verdict.correct);
      expect(checkGerman('groß', 'gross'), Verdict.correct);
    });

    test('a wrong article on a correct noun is wrongArticle', () {
      expect(
        checkGerman('der Haus', 'Haus', article: 'das'),
        Verdict.wrongArticle,
      );
      expect(checkGerman('die Haus', 'das Haus'), Verdict.wrongArticle);
    });

    test('and a wrong article on a wrong noun is just wrong', () {
      // Naming the article would bury the thing they actually got wrong.
      expect(checkGerman('der Tisch', 'Haus', article: 'das'), Verdict.wrong);
    });

    test('no article typed is not a wrong article', () {
      // BR-ANS-02 accepts the word without it. Only a *stated* wrong one
      // counts against the learner.
      expect(checkGerman('Haus', 'Haus', article: 'das'), Verdict.correct);
    });

    test('#614 a typo under the wrong article is wrong: never more than the '
        'right noun under it', () {
      expect(
        checkGerman('die Kühlschrank', 'Kühlschrank', article: 'der'),
        Verdict.wrongArticle,
      );
      expect(
        checkGerman('die Kühlschrnak', 'Kühlschrank', article: 'der'),
        Verdict.wrong,
      );
      expect(checkGerman('das Kühlschrnak', 'der Kühlschrank'), Verdict.wrong);
      expect(
        checkGerman('die Kühlschrnak', 'Kühlschrank', article: 'der').score,
        lessThanOrEqualTo(
          checkGerman('die Kühlschrank', 'Kühlschrank', article: 'der').score,
        ),
      );
    });

    test('a typo under the right article is still almost', () {
      expect(
        checkGerman('das Fentser', 'Fenster', article: 'das'),
        Verdict.almost,
      );
    });

    test('an article on a word that has none is ignored', () {
      // Verbs and adjectives have no article to get wrong, so a stray one is
      // just part of what was typed.
      expect(checkGerman('der gehen', 'gehen'), Verdict.correct);
    });

    test('a typo rule that applies here too', () {
      expect(checkGerman('Fentser', 'Fenster'), Verdict.almost);
      expect(
        checkGerman('Hasu', 'Haus'),
        Verdict.wrong,
        reason: 'four letters',
      );
    });

    test('an umlaut does not buy a typo allowance', () {
      // The expanded key turns "Bäume" into "baeume" — six characters for a
      // five-letter word. Measuring that would forgive a typo BR-ANS-01 does
      // not: the rule is six *letters*.
      expect(checkGerman('Bäuem', 'Bäume'), Verdict.wrong);
      expect(checkGerman('Baume', 'Bäume'), Verdict.correct, reason: 'ä/a');
      expect(checkGerman('Blüemn', 'Blümen'), Verdict.almost, reason: 'six');
    });

    test('nothing typed is wrong', () {
      expect(checkGerman('', 'Haus', article: 'das'), Verdict.wrong);
      expect(checkGerman('das', 'Haus', article: 'das'), Verdict.wrong);
    });

    test('and nothing expected is wrong, not trivially correct', () {
      // Two empty keys compare equal. `words.forms` is nullable and the
      // pipeline writes an empty string for a word with no plural, so a forms
      // card can genuinely reach here with nothing on either side — and
      // "correct" would mean the learner scores by submitting a blank box.
      expect(checkGerman('', ''), Verdict.wrong);
      expect(checkGerman('   ', '  '), Verdict.wrong);
      expect(checkForm('', ''), Verdict.wrong);
      expect(checkForm('!', '?'), Verdict.wrong, reason: 'keys to nothing');
    });
  });

  group('BR-ANS-03 — the articles quiz', () {
    test('exact der/die/das', () {
      for (final article in <String>['der', 'die', 'das']) {
        expect(checkArticle(article, article), Verdict.correct);
      }
    });

    test('case and spacing are forgiven', () {
      expect(checkArticle('DER', 'der'), Verdict.correct);
      expect(checkArticle('  Die  ', 'die'), Verdict.correct);
    });

    test('and nothing else is', () {
      expect(checkArticle('die', 'der'), Verdict.wrong);
      expect(checkArticle('das', 'die'), Verdict.wrong);
      expect(checkArticle('den', 'der'), Verdict.wrong);
    });

    test('there is no almost — a near-miss here is a guess', () {
      // Three options of three or four letters. "dre" is not a typo worth
      // half a mark, it is one of three answers mistyped.
      expect(checkArticle('dre', 'der'), Verdict.wrong);
      expect(checkArticle('de', 'der'), Verdict.wrong);
    });

    test('nothing typed is wrong', () {
      expect(checkArticle('', 'der'), Verdict.wrong);
      expect(checkArticle('der', ''), Verdict.wrong);
      expect(checkArticle('', ''), Verdict.wrong);
    });
  });

  group('the forms quiz', () {
    test('matches like checkGerman does', () {
      expect(checkForm('Häuser', 'Häuser'), Verdict.correct);
      expect(checkForm('Haeuser', 'Häuser'), Verdict.correct);
      expect(checkForm('gegangen', 'gegangen'), Verdict.correct);
    });

    test('a typo is almost', () {
      expect(checkForm('geganegn', 'gegangen'), Verdict.almost);
    });

    test('and never reports a wrong article', () {
      // A plural or a participle has no article of its own to get wrong, so
      // there is no verdict to report about one.
      for (final given in <String>['die Häuser', 'der Häuser', 'Häuser']) {
        expect(checkForm(given, 'Häuser'), Verdict.correct, reason: given);
      }
    });
  });

  group('BR-ANS-04 — scoring', () {
    test('correct 1 · almost 0.5 · wrongArticle 0 · wrong 0', () {
      expect(Verdict.correct.score, 1.0);
      expect(Verdict.almost.score, 0.5);
      expect(Verdict.wrongArticle.score, 0.0);
      expect(Verdict.wrong.score, 0.0);
    });

    test('only correct counts as right', () {
      // `wrongArticle` scores zero like `wrong`, but the screen treats them
      // differently — one names the article it wanted.
      expect(Verdict.correct.isRight, isTrue);
      for (final verdict in <Verdict>[
        Verdict.almost,
        Verdict.wrongArticle,
        Verdict.wrong,
      ]) {
        expect(verdict.isRight, isFalse, reason: verdict.name);
      }
    });

    test('every verdict scores between zero and one', () {
      for (final verdict in Verdict.values) {
        expect(verdict.score, inInclusiveRange(0.0, 1.0), reason: verdict.name);
      }
    });
  });

  group('splitMeanings', () {
    test('splits on / , and ;', () {
      expect(splitMeanings('house / home, building; flat'), <String>[
        'house',
        'home',
        'building',
        'flat',
      ]);
    });

    test('trims and drops the empties', () {
      expect(splitMeanings('  house /  , home  '), <String>['house', 'home']);
      expect(splitMeanings(''), isEmpty);
      expect(splitMeanings('  '), isEmpty);
    });

    test('keeps a single meaning whole', () {
      expect(splitMeanings('to look after'), <String>['to look after']);
    });

    test('#645 never splits inside brackets: they hold one note', () {
      expect(splitMeanings('stop (bus/tram), halt'), <String>[
        'stop (bus/tram)',
        'halt',
      ]);
      expect(splitMeanings('drugstore (dm, Rossmann)'), <String>[
        'drugstore (dm, Rossmann)',
      ]);
    });
  });

  group('#645 notes in brackets and alternatives', () {
    test('BR-ANS-01 a meaning counts with or without its note', () {
      for (final (given, expected) in const <(String, String)>[
        ('to save', 'to save (a file)'),
        ('save', 'to save (a file)'),
        ('to save a file', 'to save (a file)'),
        ('deposit', 'deposit (on bottles)'),
        ('turn', 'to turn (off)'),
        ('to change', 'to change (trains)'),
        ('stop', 'stop (bus/tram)'),
        ('drugstore', 'drugstore (dm, Rossmann)'),
        ('to miss', 'to miss (a train, an event)'),
        ('সাজানো', 'সাজানো (ঘর)'),
      ]) {
        expect(
          checkMeaning(given, expected),
          Verdict.correct,
          reason: '$given for $expected',
        );
      }
    });

    test('BR-ANS-01 the whole cell, typed as shown, counts', () {
      // "Zahlen, bitte!": a phrase with a comma is not two synonyms, and the
      // learner who types exactly what the card says is right.
      expect(
        checkMeaning('the bill, please', 'the bill, please'),
        Verdict.correct,
      );
      expect(
        checkMeaning('the bill please', 'the bill, please'),
        Verdict.correct,
      );
    });

    test('BR-ANS-01 and a word from inside the note is not the meaning', () {
      for (final (given, expected) in const <(String, String)>[
        ('tram', 'stop (bus/tram)'),
        ('bus', 'stop (bus/tram)'),
        ('Rossmann', 'drugstore (dm, Rossmann)'),
        ('an event', 'to miss (a train, an event)'),
      ]) {
        expect(
          checkMeaning(given, expected),
          Verdict.wrong,
          reason: '$given for $expected',
        );
      }
    });

    test('BR-ANS-02 any one German alternative counts, not a mix', () {
      expect(checkGerman('etwa', 'circa / etwa / rund'), Verdict.correct);
      expect(checkGerman('prima', 'prima / super / klasse'), Verdict.correct);
      expect(checkGerman('klasse', 'prima / super / klasse'), Verdict.correct);
      expect(
        checkGerman('super klasse', 'prima / super / klasse'),
        isNot(Verdict.correct),
      );
    });

    test('BR-ANS-02 and a German note may be left out, never answered '
        'alone', () {
      expect(checkGerman('denn', 'denn (Partikel)'), Verdict.correct);
      expect(checkGerman('sollen', 'sollen (Hörensagen)'), Verdict.correct);
      expect(checkGerman('Tram', 'Haltestelle (Bus / Tram)'), Verdict.wrong);
      expect(
        checkGerman('Haltestelle', 'Haltestelle (Bus / Tram)'),
        Verdict.correct,
      );
    });

    test('BR-ANS-02 each alternative keeps its own article', () {
      expect(checkGerman('das Auto', 'der Wagen / das Auto'), Verdict.correct);
      expect(
        checkGerman('die Auto', 'der Wagen / das Auto'),
        Verdict.wrongArticle,
      );
      expect(
        checkGerman('die Straße', 'Straße (Weg)', article: 'die'),
        Verdict.correct,
      );
    });

    test('a forms cell takes each side of its slash, and leaves out its '
        'note', () {
      expect(
        checkForm('hat aufgebrochen', 'hat/ist aufgebrochen'),
        Verdict.correct,
      );
      expect(
        checkForm('ist aufgebrochen', 'hat/ist aufgebrochen'),
        Verdict.correct,
      );
      expect(checkForm('hat', 'hat/ist aufgebrochen'), Verdict.wrong);
      expect(checkForm('hat gehabt', 'hat gehabt (hatte)'), Verdict.correct);
    });
  });

  group('punctuation and spacing the learner did not mean', () {
    test('a trailing full stop or spaces do not fail an answer', () {
      expect(checkMeaning('house.', 'house'), Verdict.correct);
      expect(checkMeaning('  house  ', 'house'), Verdict.correct);
      expect(checkGerman('Haus!', 'Haus'), Verdict.correct);
    });

    test('and doubled spaces inside one do not either', () {
      expect(checkMeaning('look  after', 'look after'), Verdict.correct);
    });
  });
}
