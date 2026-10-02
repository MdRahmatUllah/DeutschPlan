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
      words('Einladung\n\nSehr geehrte Frau Okafor,\nmit diesem Schreiben'),
      <List<String>>[
        <String>['Einladung'],
        <String>[
          'Sehr',
          'geehrte',
          'Frau',
          'Okafor',
          ',',
          'mit',
          'diesem',
          'Schreiben',
        ],
      ],
    );
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
}
