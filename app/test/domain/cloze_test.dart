import 'package:deutschplan/domain/cloze.dart';
import 'package:flutter_test/flutter_test.dart';

/// FR-T2-10 — the cloze card's gap.
void main() {
  String? blank(String sentence, String german, {String? pos}) {
    final gap = clozeGap(sentence, german, pos: pos);
    return gap == null ? null : sentence.substring(gap.start, gap.end);
  }

  test('FR-T2-10 the headword itself', () {
    expect(
      blank('Ich habe die Rechnung noch nicht bezahlt.', 'Rechnung'),
      'Rechnung',
    );
  });

  test('its inflected form, by search-key prefix', () {
    expect(blank('Die Rechnungen liegen hier.', 'Rechnung'), 'Rechnungen');
  });

  test('case and umlauts are folded as the search key folds them', () {
    expect(blank('Die TÜR ist offen.', 'Tür'), 'TÜR');
    expect(blank('Wir gehen über die Straße.', 'Straße'), 'Straße');
  });

  test("a verb's infinitive ending is dropped first", () {
    expect(blank('Er arbeitet heute.', 'arbeiten', pos: 'verb'), 'arbeitet');
    expect(blank('Er arbeitet heute.', 'arbeiten'), isNull);
  });

  test('a phrase is matched whole', () {
    expect(
      blank('Auf Wiedersehen, Frau Schmidt.', 'Auf Wiedersehen'),
      'Auf Wiedersehen',
    );
    expect(
      blank('Vielen Dank und auf Wiedersehen!', 'Auf Wiedersehen'),
      'auf Wiedersehen',
    );
  });

  test('a short key only as a whole word', () {
    expect(blank('Wir gehen ins Kino.', 'in'), isNull);
    expect(blank('Er ist in Berlin.', 'in'), 'in');
  });

  test('the first match, not a later one', () {
    final gap = clozeGap('Haus und Haus.', 'Haus')!;
    expect(gap.start, 0);
  });

  test('none: null, and the card stays plain', () {
    expect(blank('Das ist gut.', 'Rechnung'), isNull);
  });
}
