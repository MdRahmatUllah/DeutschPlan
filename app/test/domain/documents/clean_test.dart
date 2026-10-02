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
