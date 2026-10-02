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
}
