import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/clean.dart';

void main() {
  test('#1224: a word hyphenated across a line end is joined; a capital '
      'keeps the compound\'s hyphen', () {
    expect(
      cleanPages(<String>['Die Ver-\nwaltung schreibt.']),
      'Die Verwaltung schreibt.',
    );
    expect(
      cleanPages(<String>['Die Nebenkosten-\nAbrechnung kommt.']),
      'Die Nebenkosten-Abrechnung kommt.',
    );
    expect(cleanPages(<String>['Ihre E-Mail ist da.']), 'Ihre E-Mail ist da.');
  });

  test('#1224: soft hyphens, odd spaces and ligatures are normalised', () {
    final soft = String.fromCharCode(0xAD);
    final noBreak = String.fromCharCode(0xA0);
    expect(
      cleanPages(<String>['Die Ver${soft}waltung$noBreak  ist ﬁx\r\nda.']),
      'Die Verwaltung ist fix\nda.',
    );
  });

  test('#1224: a suspended hyphen at a line end stays one', () {
    expect(
      cleanPages(<String>['Haus-\nund Gartenpflege']),
      'Haus- und Gartenpflege',
    );
  });

  test('#1224: page numbers go', () {
    expect(
      cleanPages(<String>[
        'Text eins.\n1',
        'Text zwei.\n- 2 -',
        'Drei.\nSeite 3 von 3',
      ]),
      'Text eins.\n\nText zwei.\n\nDrei.',
    );
  });

  test('#1224: a header and a footer repeated on most pages go, and a '
      'one-page letter keeps its letterhead', () {
    const head = 'Hausverwaltung Hansen · Lindenstraße 4';
    const foot = 'Bankverbindung: Musterbank';
    expect(
      cleanPages(<String>[
        '$head\nSeite eins.\n$foot',
        '$head\nSeite zwei.\n$foot',
        '$head\nSeite drei.\n$foot',
      ]),
      'Seite eins.\n\nSeite zwei.\n\nSeite drei.',
    );
    expect(cleanPages(<String>['$head\nEin Brief.']), '$head\nEin Brief.');
  });

  group('#1385 FR-D1-02 the same page twice', () {
    const page =
        'Zweite Seite.\nDie Rechnung kommt mit der Post.\nBitte zahlen '
        'Sie bis Freitag.';

    test('is read once, never emptied', () {
      expect(cleanPages(<String>[page, page]), page);
      expect(cleanPages(List<String>.filled(30, page)), page);
    });

    test('beside another page, is read once, after it', () {
      const first = 'Erste Seite.\nWir schreiben Ihnen heute.';
      expect(cleanPages(<String>[first, page, page]), '$first\n\n$page');
    });

    test(
      'in two shots whose OCR differs by a few characters, is read once',
      () {
        const lines = <String>[
          'Sehr geehrte Frau Okafor,',
          'hier ist die Nebenkostenabrechnung für 2025.',
          'Bitte überweisen Sie die Nachzahlung bis zum 15. November.',
          'Am Dienstag kommt der Hausmeister.',
          'Er will die Heizkörper kontrollieren.',
          'Bitte seien Sie zwischen 9 und 12 Uhr erreichbar.',
          'Bei Fragen rufen Sie uns an.',
          'Mit freundlichen Grüßen',
          'Ihre Hausverwaltung',
        ];
        final shot = lines.join('\n');
        final other = <String>[
          ...lines.take(4),
          'Er wil die Heizkörper kontrolieren.', // OCR's slips
          ...lines.skip(5),
        ].join('\n');
        expect(cleanPages(<String>[shot, other]), shot);
      },
    );

    test('short pages that differ in a line still keep their text', () {
      expect(
        cleanPages(<String>['Kopf\nEins.\nFuß', 'Kopf\nZwei.\nFuß']),
        'Eins.\n\nZwei.',
      );
      expect(
        cleanPages(<String>['Kopf\nFuß', 'Kopf\nFuß\nNoch etwas.']),
        'Kopf\nFuß\n\nNoch etwas.',
        reason: 'a page that is all header and footer keeps them',
      );
    });

    test('a page 2 of letterhead and one line is no copy of page 1', () {
      // Two lines each: page 2 shares four of its five lines with page 1,
      // but the two pages share four of eight.
      const head = 'Hausverwaltung Hansen\nLindenstraße 4, 12345 Berlin';
      const foot = 'Bankverbindung: Musterbank\nTelefon 030 1234567';
      expect(
        cleanPages(<String>[
          '$head\nDer Brief beginnt hier.\nEr geht lange weiter.\n'
              'Und noch weiter.\n$foot',
          '$head\nGruß.\n$foot',
        ]),
        'Der Brief beginnt hier.\nEr geht lange weiter.\nUnd noch weiter.'
        '\n\nGruß.',
      );
    });
  });

  test('#1227 FR-D2-01 a document is named by its first line, cut at a word '
      'end', () {
    expect(
      documentTitle('\n  Nebenkosten 2025  \nSehr geehrte'),
      'Nebenkosten 2025',
    );
    expect(
      documentTitle('Ihre Abrechnung der Betriebskosten für das Jahr', max: 20),
      'Ihre Abrechnung der…',
    );
    expect(documentTitle(' \n\n '), isNull);
    expect(documentTitle('…\n— 2 —\nLieber Max'), 'Lieber Max');
  });

  test("#1227 a letter's title is past its salutation, without a trailing "
      'comma', () {
    expect(
      documentTitle('Liebe Eltern,\n\nam Montag fällt der Unterricht aus.'),
      'am Montag fällt der Unterricht aus.',
    );
    expect(
      documentTitle('Sehr geehrte Damen und Herren,\nIhre Abrechnung 2025'),
      'Ihre Abrechnung 2025',
    );
    expect(
      documentTitle('Betreff: Ihre Kündigung:'),
      'Betreff: Ihre Kündigung',
    );
    // A salutation alone is all there is to name it by.
    expect(documentTitle('Liebe Anna,'), 'Liebe Anna');
    // On one line with the text, it's the first line as it is.
    expect(
      documentTitle('Hallo Max, wie geht es dir?'),
      'Hallo Max, wie geht es dir?',
    );
  });
}
