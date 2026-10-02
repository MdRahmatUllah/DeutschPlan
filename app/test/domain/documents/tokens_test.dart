import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/clean.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/tokens.dart';

import 'lemmatiser_test.dart' show courseEntries;

List<List<String>> words(String text) => <List<String>>[
  for (final sentence in splitText(text)) sentence.words,
];

void main() {
  late Lemmatiser lemmatiser;

  setUpAll(() => lemmatiser = Lemmatiser(courseEntries()));

  test('#1224: sentences end at a full stop, but not after an abbreviation '
      'or a day as digits; a year ends one', () {
    expect(
      words('Bitte zahlen Sie z. B. bis zum 14. Oktober. Danke!'),
      <List<String>>[
        <String>['Bitte', 'zahlen', 'Sie', 'bis', 'zum', 'Oktober'],
        <String>['Danke'],
      ],
    );
    expect(words('Zimmer Nr. 5 ist frei.'), hasLength(1));
    expect(words('Das war 2025. Jetzt ist es anders.'), hasLength(2));
    expect(words('Das ist so. Wir kommen.'), hasLength(2));
  });

  test('#1224: a blank line ends a sentence; one line break doesn\'t', () {
    expect(
      words('Einladung\n\nWir schreiben Ihnen,\nmit diesem Brief'),
      <List<String>>[
        <String>['Einladung'],
        <String>['Wir', 'schreiben', 'Ihnen', ',', 'mit', 'diesem', 'Brief'],
      ],
    );
  });

  test('#1297 a salutation alone on its line is a sentence of its own, '
      'though the letter goes on in lower case', () {
    for (final (greeting, rest) in <(String, String)>[
      ('Sehr geehrter Herr Becker,', 'leider müssen wir'),
      ('Liebe Eltern,', 'am kommenden Montag'),
      ('Guten Tag,', 'wir schreiben Ihnen'),
    ]) {
      final sentences = splitText('$greeting\n$rest.');
      expect(sentences, hasLength(2), reason: greeting);
      expect(
        '$rest.'.startsWith(sentences.last.tokens.first.text),
        isTrue,
        reason: greeting,
      );
    }
    // A comma at a line's end in a sentence that isn't a greeting stays.
    expect(splitText('Wir bitten Sie,\nuns anzurufen.'), hasLength(1));
  });

  test('#1224: every token points at itself in the text', () {
    final text = cleanPages(<String>[
      File('test/fixtures/documents/corpus/letter_jobcenter.txt')
          .readAsStringSync(),
    ]);
    final sentences = splitText(text);
    expect(sentences, isNotEmpty);
    for (final sentence in sentences) {
      for (final token in sentence.tokens) {
        expect(text.substring(token.start, token.end), token.text);
      }
    }
  });

  test('#1224: addresses, IBANs, numbers and lone letters are no words; a '
      'hyphenated word is one', () {
    expect(
      words(
        'Schreiben Sie an info@sogda.de oder www.sogda.de: IBAN '
        'DE89 3704 0044 0532 0130 00, Ihre E-Mail, 245,80 Euro, Niveau B1',
      ).single,
      <String>[
        'Schreiben',
        'Sie',
        'an',
        'oder',
        ':',
        'IBAN',
        ',',
        'Ihre',
        'E-Mail',
        ',',
        'Euro',
        ',',
        'Niveau',
      ],
    );
  });

  test('#1224: a capital the course doesn\'t know, in the middle of a '
      'sentence, is likely a name, unless it ends like a noun or follows an '
      'article', () {
    bool name(String token, {String? previous, bool start = false}) =>
        likelyName(
          token,
          sentenceStart: start,
          compound: lemmatiser.compoundParts(token) != null,
          previous: previous,
        );
    expect(name('Okafor', previous: 'Frau'), isTrue);
    expect(name('Jung', previous: 'Frau'), isTrue, reason: 'a title wins');
    expect(name('Mitgliedschaft', previous: 'neue'), isFalse);
    expect(name('Hansen', previous: 'Hausverwaltung'), isTrue);
    expect(name('Krefeld', previous: 'in'), isTrue);
    expect(name('Handwerker', previous: 'Die'), isFalse);
    expect(name('Kontoführung', previous: 'Die'), isFalse);
    expect(name('Weiterbildung', previous: 'welche'), isFalse);
    expect(name('Nebenkostenabrechnung', previous: 'zur'), isFalse);
    expect(name('Petrović', start: true), isFalse, reason: 'case says nothing');
  });

  test('#1224: a sentence ends inside quotes, after an IBAN, and before a '
      'pronoun after a number; a greeting line ends at its comma', () {
    expect(
      words('Sie sagte: „Ich hole es ab.“ Danach ging sie.'),
      hasLength(2),
    );
    expect(
      words('IBAN DE89 3704 0044 0532 0130 00. Danke für alles!'),
      hasLength(2),
    );
    expect(words('Sie finden uns in Raum 2. Wir warten.'), hasLength(2));
    // A date goes on (agent-3's #1260 re-review).
    for (final date in <String>[
      'Wir kommen am 2. Oktober.',
      'Der Termin ist am 14.10. um 10 Uhr.',
      'Zahlen Sie bis 31.12. den Betrag.',
      'Es gilt vom 1.1. bis 31.3. für alle.',
      'Nach dem 2. Weltkrieg kam er.',
    ]) {
      expect(words(date), hasLength(1), reason: date);
    }
    final greeting = words(
      'Sehr geehrte Frau Okafor,\nVielen Dank für Ihren Brief.',
    );
    expect(greeting, hasLength(2));
    expect(greeting.last.first, 'Vielen');
  });

  test('#1224: the abbreviations of letters end no sentence', () {
    for (final text in <String>[
      'Der Verein e. V. lädt ein.',
      'Bitte z. Hd. Frau Okafor schreiben.',
      'Die Std. kostet fünf Euro.',
      'Gezahlt i. A. der Firma.',
      'Im Jan. kommt er.',
      'Der Preis inkl. MwSt. steht hier.',
    ]) {
      expect(words(text), hasLength(1), reason: text);
    }
  });

  test('#1224: a compound\'s parts are words to learn, as their headwords', () {
    expect(lemmatiser.compoundParts('Wasserzähler')?.first, isNot('was'));
    expect(lemmatiser.compoundParts('Mietvertrags')?.last, 'Vertrag');
  });

  test('#1224 FR-D1-04: capitals and names say nothing either way; a '
      'compound of course words is German', () {
    double share(String text) => germanShare(splitText(text), lemmatiser);
    // Every other word here is German, so each line is 1.0 only by its rule.
    expect(share('Die Miete steigt, sagt REWE.'), 1.0);
    expect(share('Wir sehen Frau Okafor morgen.'), 1.0);
    expect(share('Der Taxifahrer kommt morgen.'), 1.0);
  });

  test('#1224 FR-D1-04: a bank statement of names and capitals is German', () {
    const statement =
        'Kontoauszug Nr. 9\n\n'
        'Buchungstag Verwendungszweck Betrag\n\n'
        '01.10. REWE SAGT DANKE Kartenzahlung -23,45\n\n'
        '02.10. Gutschrift Gehalt Hansen GmbH 2.100,00\n\n'
        '03.10. SEPA-Lastschrift Stadtwerke Strom -54,00\n\n'
        'Alter Kontostand 1.234,56 Neuer Kontostand 3.256,11';
    expect(
      germanShare(splitText(statement), lemmatiser),
      greaterThanOrEqualTo(germanThreshold),
    );
  });

  test('#1224: a compound of course words is split into them, the head '
      'last', () {
    expect(lemmatiser.compoundParts('Nebenkostenabrechnung'), <String>[
      'Nebenkosten',
      'Abrechnung',
    ]);
    expect(lemmatiser.compoundParts('Integrationskurs'), <String>[
      'Integration',
      'Kurs',
    ]);
    expect(lemmatiser.compoundParts('Taxifahrer'), <String>['Taxi', 'Fahrer']);
    expect(lemmatiser.compoundParts('Petrović'), isNull);
  });

  test('#1224 FR-D1-04: German texts are German to the lemmatiser, an English '
      'and a Bangla one aren\'t', () {
    double share(String name) => germanShare(
      splitText(
        cleanPages(<String>[
          File('test/fixtures/documents/corpus/$name.txt').readAsStringSync(),
        ]),
      ),
      lemmatiser,
    );
    for (final name in <String>[
      'letter_landlord',
      'letter_jobcenter',
      'letter_insurer',
      'letter_bank',
      'article_buses',
      'article_housing',
      'article_course',
    ]) {
      expect(share(name), greaterThanOrEqualTo(germanThreshold), reason: name);
    }
    expect(share('english'), lessThan(germanThreshold));
    expect(share('bangla'), lessThan(germanThreshold));
  });

  group('#1227 FR-D1-02 a text over the limit', () {
    test('is cut at the last sentence end before it, with a note', () {
      const text = 'Erster Satz hier. Zweiter Satz da. Dritter Satz dort.';
      // The limit falls inside the third sentence.
      final limited = limitText(text, limit: text.indexOf('dort') + 2);
      expect(limited.text, 'Erster Satz hier. Zweiter Satz da.');
      expect(limited.cut, isTrue);
    });

    test('keeps a sentence that ends on the limit', () {
      const text = 'Erster Satz hier. Zweiter Satz da. Dritter Satz.';
      final limited = limitText(text, limit: text.indexOf('Dritter'));
      expect(limited.text, 'Erster Satz hier. Zweiter Satz da.');
    });

    test('not after an abbreviation, which ends no sentence', () {
      const text =
          'Er kam spät. Bringen Sie z. B. den Pass mit. Und dann mehr.';
      final limited = limitText(text, limit: text.indexOf('Pass'));
      expect(limited.text, 'Er kam spät.');
    });

    test('at the last word end when no sentence ends before it', () {
      final text = 'Wort ' * 10;
      final limited = limitText(text, limit: 12); // «Wort Wort Wo»
      expect(limited.text, 'Wort Wort');
      expect(limited.cut, isTrue);
    });

    test('never splits a surrogate pair', () {
      final text = '${'a' * 9}\u{1F600}${'b' * 9}';
      expect(limitText(text, limit: 10).text, 'a' * 9);
    });

    test('and one at or under the limit is left as it is', () {
      final text = 'Kurz. ${'x' * 19994}';
      expect(text.length, docMaxChars);
      expect(limitText(text), (text: text, cut: false));
      expect(limitText('$text.').cut, isTrue);
    });
  });

  test('#1270: a gender form is one word, as its stem\'s course word', () {
    final sentence = splitText(
      'Alle Kund:innen, Mitarbeiter*innen, Lehrer_innen und Bürger/-innen '
      'und jede Teilnehmer:in kommen um 10:30, auch Kolleg*Innen.',
    ).single;
    expect(sentence.words, <String>[
      'Alle',
      'Kund:innen',
      ',',
      'Mitarbeiter*innen',
      ',',
      'Lehrer_innen',
      'und',
      'Bürger/-innen',
      'und',
      'jede',
      'Teilnehmer:in',
      'kommen',
      'um',
      ',',
      'auch',
      'Kolleg*Innen',
    ]);
    final lemmas = <String>[
      // The course has two Kunde: der Kunde, and C2's die Kunde (tidings).
      for (final entries in lemmatiser.sentence(sentence.words))
        entries.map((e) => e.german).toSet().join('|'),
    ];
    expect(
      <String>[
        for (final i in <int>[1, 3, 5, 7, 10, 15]) lemmas[i],
      ],
      <String>[
        'Kunde',
        'Mitarbeiter',
        'Lehrer',
        'Bürger',
        'Teilnehmer',
        'Kollege',
      ],
    );
  });

  test('#1270: a capital after an adjective or an ordinal with an ending is '
      'a noun; after a preposition it can still be a name', () {
    bool name(String token, String previous) => likelyName(
      token,
      sentenceStart: false,
      compound: false,
      previous: previous,
      previousEntries: lemmatiser.lookup(previous),
    );
    expect(name('Schritt', 'wichtiger'), isFalse);
    expect(name('Login', 'ersten'), isFalse);
    expect(name('Schritt', 'wichtig'), isTrue, reason: 'no ending: an adverb');
    expect(name('Fahrerinnen', 'noch'), isFalse, reason: 'ends like a noun');
    expect(name('Raum', 'in'), isTrue, reason: 'as «in Krefeld»: the corpus');
    // The cost, taken: a place after an adjective reads as a word.
    expect(name('Berlin', 'schönen'), isFalse, reason: '«im schönen Berlin»');
    // FR-D1-04: so Schritt, outside the course, is a word that isn't German.
    expect(
      germanShare(splitText('Das ist ein wichtiger Schritt.'), lemmatiser),
      0.8,
    );
  });
}
