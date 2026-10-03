import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/excerpt.dart';

void main() {
  // An official letter's sentence of 290 characters, the word near its end.
  const long =
      'Bitte reichen Sie bis zum 15. November die folgenden Unterlagen ein: '
      'eine Kopie des Personalausweises, die letzten drei Gehaltsabrechnungen, '
      'eine Bescheinigung über die Höhe der Miete und, falls vorhanden, den '
      'Bescheid über das Wohngeld sowie die Mietschuldenfreiheitsbescheinigung.';

  test('#1233 a sentence that fits stays whole', () {
    expect(excerpt('Er wartet am Bahnhof.', max: 200), 'Er wartet am Bahnhof.');
  });

  test('#1233 a longer one is cut around its word, at word ends, with «…» '
      'where it was cut, within the field', () {
    final cut = excerpt(long, max: 200, around: 'Wohngeld');
    expect(cut.length, lessThanOrEqualTo(200));
    expect(cut, contains('Wohngeld'));
    expect(cut, startsWith('…'));
    expect(long, contains(cut.substring(1, cut.length - 1).trim()));
    // At word ends: what follows the «…» starts a word of the sentence.
    final first = cut.substring(1).split(' ').first;
    expect(long.split(' '), contains(first));
  });

  test('#1233 a word at the very end keeps the sentence\'s end', () {
    final cut = excerpt(
      long,
      max: 200,
      around: 'Mietschuldenfreiheitsbescheinigung',
    );
    expect(cut.length, lessThanOrEqualTo(200));
    expect(cut, endsWith('Mietschuldenfreiheitsbescheinigung.'));
    expect(cut, startsWith('…'));
  });

  test('#1233 a word not in it, or none: the start, cut at a word end', () {
    for (final around in <String?>[null, 'Bänke']) {
      final cut = excerpt(long, max: 200, around: around);
      expect(cut.length, lessThanOrEqualTo(200));
      expect(cut, startsWith('Bitte reichen Sie'));
      expect(cut, endsWith('…'));
      expect(cut.substring(0, cut.length - 1), isNot(endsWith(' ')));
    }
  });

  test('#1233 never half a surrogate pair, with no space to cut at', () {
    final emoji = '😀' * 150; // 300 code units, no spaces.
    // 201: a window of 199 code units would end inside a pair.
    final cut = excerpt(emoji, max: 201);
    expect(cut.length, lessThanOrEqualTo(201));
    expect(cut.runes.every((r) => r == 0x1F600 || r == 0x2026), isTrue);
  });
}
