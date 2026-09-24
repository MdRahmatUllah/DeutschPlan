import 'package:deutschplan/domain/cloze.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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

  group('#325 reflexives, phrases, participles and split verbs', () {
    test('a reflexive verb without its sich', () {
      expect(
        blank('Du solltest dich mehr bewegen.', 'sich bewegen', pos: 'verb'),
        'bewegen',
      );
      expect(
        blank(
          'Wir bemühen uns um eine Lösung.',
          'sich bemühen um',
          pos: 'verb',
        ),
        'bemühen',
      );
      expect(
        blank('Sie haben sich gut benommen.', 'sich benehmen', pos: 'verb'),
        isNull,
        reason: 'never the sich alone',
      );
    });

    test("a phrase's words in a row, without its punctuation", () {
      expect(
        blank('Wie geht es Ihnen, Frau Weber?', 'Wie geht es Ihnen?'),
        'Wie geht es Ihnen',
      );
      expect(blank("Hallo Anna, wie geht's?", "Wie geht's?"), "wie geht's");
    });

    test('a phrase not in a row: its noun, else its longest word', () {
      expect(
        blank(
          'Die Firma stellt uns einen Laptop zur Verfügung.',
          'zur Verfügung stellen',
          pos: 'phrase',
        ),
        'Verfügung',
      );
      expect(
        blank('Ich habe heute keine Lust zu kochen.', 'Ich habe keine Lust'),
        'Lust',
      );
      expect(
        blank('Ich mache mir Sorgen.', 'sich Sorgen machen', pos: 'phrase'),
        'Sorgen',
      );
      expect(
        blank('Der Datenschutz hegt Bedenken.', 'Zweifel hegen'),
        'hegt',
        reason: 'an infinitive in a phrase is matched as a verb',
      );
    });

    test("a verb's participle", () {
      expect(
        blank('Der Aufwand hat sich gelohnt.', 'sich lohnen', pos: 'verb'),
        'gelohnt',
      );
      expect(
        blank('Ich habe das Paket aufgegeben.', 'aufgeben', pos: 'verb'),
        'aufgegeben',
      );
    });

    test("a separable verb split: its stem, with the particle after it", () {
      expect(
        blank('Ich räume die Wohnung auf.', 'aufräumen', pos: 'verb'),
        'räume',
      );
      expect(
        blank(
          'Ich arbeite mit dem Team zusammen.',
          'zusammenarbeiten',
          pos: 'verb',
        ),
        'arbeite',
      );
      expect(
        blank('Auf dem Tisch räume ich.', 'aufräumen', pos: 'verb'),
        isNull,
        reason: 'the particle has to come after the verb',
      );
    });
  });

  test('#325 over the real course, most examples have their gap', () {
    final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
    addTearDown(db.close);
    final missed = <String, int>{};
    final total = <String, int>{};
    for (final row in db.select(
      'SELECT w.german AS word, w.pos, e.german FROM word_examples e '
      'JOIN words w ON w.uid = e.word_uid',
    )) {
      final word = row['word'] as String;
      final kind = word.startsWith('sich ')
          ? 'reflexive'
          : row['pos'] as String? ?? '';
      total.update(kind, (n) => n + 1, ifAbsent: () => 1);
      if (clozeGap(row['german'] as String, word, pos: row['pos'] as String?) ==
          null) {
        missed.update(kind, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    double rate(String kind) => (missed[kind] ?? 0) / total[kind]!;
    // Before #325: reflexives 99 %, phrases 64 %, verbs 44 %, all 25 %.
    expect(rate('reflexive'), lessThan(0.15));
    expect(rate('phrase'), lessThan(0.15));
    expect(rate('verb'), lessThan(0.2));
    final all = missed.values.fold(0, (a, b) => a + b);
    expect(all / total.values.fold(0, (a, b) => a + b), lessThan(0.1));
  });
}
